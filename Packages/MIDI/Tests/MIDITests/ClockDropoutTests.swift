import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del corte del reloj externo.
///
/// **Un cable flojo no puede callar la música.** `product-guidelines.md`: un
/// dispositivo MIDI desconectado se comunica con un estado, no con una disculpa.
/// Aquí el estado es «desenganchado», y lo que suena sigue sonando al último
/// tempo conocido.
final class ClockDropoutTests: XCTestCase {

    private func makeTransport() -> Transport {
        let transport = Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
            ),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: { _, _ in }
        )
        transport.clockSource = .external
        return transport
    }

    private func tickInterval(beatsPerMinute: Double) -> Double {
        60.0 / beatsPerMinute * 1_000_000_000.0 / 24.0
    }

    @discardableResult
    private func feed(
        _ transport: Transport, ticks count: Int, beatsPerMinute: Double, from start: Int64 = 0
    ) -> Int64 {
        let interval = tickInterval(beatsPerMinute: beatsPerMinute)
        var instant = start
        for index in 1...count {
            instant = start + Int64((interval * Double(index)).rounded())
            transport.receive(
                .timingClock, atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(instant)))
        }
        return instant
    }

    // MARK: - Enganchado

    /// Con ticks llegando al ritmo esperado, el reloj está enganchado.
    func testAFlowingClockIsFollowed() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let last = feed(transport, ticks: 24, beatsPerMinute: 120)

        XCTAssertFalse(
            transport.clockHasDropped(
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(last + 20_000_000))))
    }

    /// **Un tick perdido no es un corte.** El margen es del orden de una negra,
    /// así que perder uno —o unos cuantos— no saca del modo esclavo.
    func testASingleMissedTickIsNotADropout() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let last = feed(transport, ticks: 24, beatsPerMinute: 120)

        // Dos intervalos de tick sin nada: a 120 BPM son unos 42 ms.
        let silence = Int64(tickInterval(beatsPerMinute: 120) * 2)
        XCTAssertFalse(
            transport.clockHasDropped(
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(last + silence))))
    }

    // MARK: - Cortado

    /// Pasado el margen sin ticks, el reloj se declara cortado.
    func testSilenceLongerThanTheMarginIsADropout() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let last = feed(transport, ticks: 24, beatsPerMinute: 120)

        // Una negra entera sin ticks: a 120 BPM, 500 ms.
        XCTAssertTrue(
            transport.clockHasDropped(
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(last + 600_000_000))))
    }

    /// **El margen es relativo al tempo, no un literal en milisegundos.** A 20
    /// BPM medio segundo es menos de un tick, y un umbral fijo declararía cortes
    /// falsos todo el rato.
    func testTheMarginFollowsTheTempo() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let last = feed(transport, ticks: 24, beatsPerMinute: 20)

        // Medio segundo a 20 BPM son cuatro ticks: no es un corte.
        XCTAssertFalse(
            transport.clockHasDropped(
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(last + 500_000_000))))
    }

    /// El tempo sobrevive al corte: es lo que hace que la música siga sonando
    /// igual en vez de callarse o saltar.
    func testTheTempoSurvivesTheDropout() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        feed(transport, ticks: 24, beatsPerMinute: 120)

        XCTAssertEqual(
            Double(transport.clockHandoff.reading.quarterNoteNanoseconds), 500_000_000,
            accuracy: 200_000)
    }

    // MARK: - Volver

    /// Al volver el clock se re-engancha **sin parar y sin volver al paso 0**.
    func testTheClockCanComeBack() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let last = feed(transport, ticks: 24, beatsPerMinute: 120)

        let afterGap = last + 2_000_000_000
        transport.receive(
            .timingClock, atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(afterGap)))
        feed(transport, ticks: 24, beatsPerMinute: 90, from: afterGap)

        XCTAssertFalse(
            transport.clockHasDropped(
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(afterGap + 700_000_000))))
        XCTAssertEqual(
            Double(transport.clockHandoff.reading.quarterNoteNanoseconds), 666_666_666,
            accuracy: 1_000_000)
    }

    // MARK: - Sin maestro todavía

    /// Sin ningún tick recibido no hay corte que declarar: no se estaba
    /// siguiendo a nadie.
    func testNoClockAtAllIsNotADropout() {
        XCTAssertFalse(makeTransport().clockHasDropped(atHostTime: HostClock.now()))
    }
}
