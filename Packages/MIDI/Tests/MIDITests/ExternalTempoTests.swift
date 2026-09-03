import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de lo que el transporte publica al seguir el reloj del maestro.
///
/// Se comprueba **lo que cruza al hilo del scheduler**, no el bucle: el bucle
/// consume el `ClockHandoff` y la aritmética vive en `TempoMap`, los dos
/// testeados aparte. Arrancar el hilo aquí solo añadiría flake de CoreMIDI sin
/// cubrir nada nuevo.
final class ExternalTempoTests: XCTestCase {

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

    /// Nanosegundos entre ticks a un tempo dado. Una negra son 24 ticks.
    private func tickInterval(beatsPerMinute: Double) -> Double {
        60.0 / beatsPerMinute * 1_000_000_000.0 / 24.0
    }

    /// Manda `count` ticks equiespaciados desde `start`, en ticks de host.
    @discardableResult
    private func feed(
        _ transport: Transport, ticks count: Int, beatsPerMinute: Double, from start: UInt64 = 0
    ) -> UInt64 {
        let interval = tickInterval(beatsPerMinute: beatsPerMinute)
        var instant = start
        for index in 1...count {
            instant =
                start
                &+ HostClock.hostTicks(
                    fromNanoseconds: UInt64((interval * Double(index)).rounded()))
            transport.receive(.timingClock, atHostTime: instant)
        }
        return instant
    }

    // MARK: - El tempo cruza

    /// Veinticuatro ticks a 120 BPM publican una negra de 500 ms.
    func testAQuarterNoteOfTicksPublishesTheTempo() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        feed(transport, ticks: 24, beatsPerMinute: 120)

        let reading = transport.clockHandoff.reading
        XCTAssertTrue(reading.isEstablished)
        XCTAssertEqual(Double(reading.quarterNoteNanoseconds), 500_000_000, accuracy: 200_000)
    }

    /// Antes de cerrar la negra no hay nada publicado: el scheduler no puede
    /// sellar con un tempo que todavía no se sabe.
    func testNothingIsPublishedBeforeTheFirstQuarterNote() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        feed(transport, ticks: 23, beatsPerMinute: 120)

        XCTAssertFalse(transport.clockHandoff.reading.isEstablished)
    }

    /// Un cambio de tempo del maestro se ve en la publicación siguiente.
    func testATempoChangeReachesTheScheduler() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        let afterFirst = feed(transport, ticks: 24, beatsPerMinute: 120)
        feed(transport, ticks: 24, beatsPerMinute: 90, from: afterFirst)

        XCTAssertEqual(
            Double(transport.clockHandoff.reading.quarterNoteNanoseconds), 666_666_666,
            accuracy: 1_000_000)
    }

    // MARK: - La corrección, una vez por negra

    /// **Se corrige una vez cada 24 ticks, no más.** Corregir a 24 ppqn metería
    /// el jitter del cable en cada evento.
    func testThePhaseIsCorrectedOncePerQuarterNote() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)

        var corrections = 0
        var previous = transport.clockHandoff.reading.accumulatedCorrectionNanoseconds
        let interval = tickInterval(beatsPerMinute: 120)
        for index in 1...72 {
            transport.receive(
                .timingClock,
                atHostTime: HostClock.hostTicks(
                    fromNanoseconds: UInt64((interval * Double(index)).rounded())))
            let now = transport.clockHandoff.reading.accumulatedCorrectionNanoseconds
            if now != previous {
                corrections += 1
                previous = now
            }
        }

        XCTAssertLessThanOrEqual(corrections, 3, "se corrigió más de una vez por negra")
    }

    // MARK: - Internal no publica

    /// Con `Internal` el reloj del maestro no llega ni al estimador: lo que
    /// cruza al scheduler sigue siendo el tempo de la app, y una ráfaga de ticks
    /// a otra velocidad no lo mueve.
    ///
    /// *(Desde que el tempo interno también viaja por el handoff —tarea de la
    /// Fase 5—, «no publica nada» dejó de ser cierto y de ser lo que importaba:
    /// lo que importa es que el maestro no pise a la app.)*
    func testInternalIgnoresTheMasterTicks() {
        let transport = makeTransport()
        transport.clockSource = .internal
        transport.setTempo(beatsPerMinute: 120)
        let before = transport.clockHandoff.reading.quarterNoteNanoseconds

        transport.receive(.timingClock, atHostTime: 0)
        feed(transport, ticks: 48, beatsPerMinute: 90)

        XCTAssertEqual(transport.clockHandoff.reading.quarterNoteNanoseconds, before)
        XCTAssertEqual(before, 500_000_000)
    }

    // MARK: - Arrancar olvida al maestro anterior

    /// El tempo del maestro de la sesión anterior no dice nada de la siguiente.
    func testPlayForgetsThePreviousMaster() {
        let transport = makeTransport()
        transport.receive(.timingClock, atHostTime: 0)
        feed(transport, ticks: 24, beatsPerMinute: 120)
        XCTAssertTrue(transport.clockHandoff.reading.isEstablished)

        transport.play()

        XCTAssertFalse(transport.clockHandoff.reading.isEstablished)
    }
}
