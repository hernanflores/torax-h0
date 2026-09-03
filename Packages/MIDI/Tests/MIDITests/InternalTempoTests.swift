import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del tempo interno editable.
///
/// Era una constante de 120 BPM desde la rebanada 1. Ahora se edita, y **viaja
/// por el mismo camino que el tempo de un maestro externo**: el scheduler no
/// distingue de dónde viene el periodo de la negra, así que hay un solo
/// mecanismo que mantener.
final class InternalTempoTests: XCTestCase {

    private func makeTransport() -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
            ),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: { _, _ in }
        )
    }

    // MARK: - El valor por defecto

    /// Sin tocar nada, el tempo es el de la configuración: la app suena como
    /// sonaba.
    func testTheDefaultIsTheConfiguredTempo() {
        XCTAssertEqual(makeTransport().tempo.beatsPerMinute, 120)
    }

    // MARK: - Editar

    func testSettingATempoInsideTheRangeIsAccepted() {
        let transport = makeTransport()

        XCTAssertTrue(transport.setTempo(beatsPerMinute: 174))

        XCTAssertEqual(transport.tempo.beatsPerMinute, 174)
    }

    /// Los dos extremos entran: son el rango que el tipo `Tempo` declara.
    func testBothEndsOfTheRangeAreAccepted() {
        let transport = makeTransport()

        XCTAssertTrue(transport.setTempo(beatsPerMinute: 20))
        XCTAssertTrue(transport.setTempo(beatsPerMinute: 300))
        XCTAssertEqual(transport.tempo.beatsPerMinute, 300)
    }

    /// **Fuera de rango se rechaza sin romper el vigente.** Un control que se
    /// pasa de rango no puede dejar el transporte sin tempo.
    func testATempoOutOfRangeIsRejectedAndTheCurrentOneSurvives() {
        let transport = makeTransport()
        transport.setTempo(beatsPerMinute: 174)

        XCTAssertFalse(transport.setTempo(beatsPerMinute: 400))
        XCTAssertFalse(transport.setTempo(beatsPerMinute: 0))

        XCTAssertEqual(transport.tempo.beatsPerMinute, 174)
    }

    // MARK: - Llega al scheduler

    /// El tempo interno cruza por el mismo sitio que el del maestro: el
    /// scheduler no distingue de dónde viene.
    func testTheInternalTempoReachesTheScheduler() {
        let transport = makeTransport()

        transport.setTempo(beatsPerMinute: 60)

        XCTAssertEqual(transport.clockHandoff.reading.quarterNoteNanoseconds, 1_000_000_000)
    }

    /// Con `External` manda el maestro: editar el tempo de la app no le pisa el
    /// periodo al que se está siguiendo.
    func testWithAnExternalMasterTheInternalTempoDoesNotPublish() {
        let transport = makeTransport()
        transport.clockSource = .external
        transport.receive(.timingClock, atHostTime: 0)
        for index in 1...24 {
            transport.receive(
                .timingClock,
                atHostTime: HostClock.hostTicks(
                    fromNanoseconds: UInt64(index * 20_833_333)))
        }
        let followed = transport.clockHandoff.reading.quarterNoteNanoseconds

        transport.setTempo(beatsPerMinute: 60)

        XCTAssertEqual(transport.clockHandoff.reading.quarterNoteNanoseconds, followed)
        XCTAssertEqual(transport.tempo.beatsPerMinute, 60, "la app olvidó su propio tempo")
    }

    /// Y al volver a `Internal`, el tempo de la app vuelve a mandar sin tener
    /// que tocarlo otra vez.
    func testGoingBackToInternalRepublishesTheAppTempo() {
        let transport = makeTransport()
        transport.clockSource = .external
        transport.setTempo(beatsPerMinute: 60)

        transport.clockSource = .internal

        XCTAssertEqual(transport.clockHandoff.reading.quarterNoteNanoseconds, 1_000_000_000)
    }
}
