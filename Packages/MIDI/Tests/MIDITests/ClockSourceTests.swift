import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de quién manda el tempo.
///
/// **La decisión es del usuario, no del cable.** Con `Internal` elegido, un
/// maestro externo puede estar mandando Start, Stop y clock por el mismo puerto
/// del que llegan los knobs, y no puede pasar nada: conectar un controlador no
/// cambia lo que suena.
final class ClockSourceTests: XCTestCase {

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

    /// Sin decir nada, manda el reloj de la app: es lo que hacía antes de que
    /// existiera esta elección, y arrancar siguiendo a un maestro sorprendería.
    func testTheDefaultIsInternal() {
        XCTAssertEqual(makeTransport().clockSource, .internal)
    }

    // MARK: - Internal ignora

    /// Los tres mensajes del maestro no se consumen con `Internal`.
    func testInternalConsumesNothing() {
        let transport = makeTransport()

        for message in [MIDIMessage.timingClock, .start, .stop] {
            XCTAssertFalse(
                transport.receive(message, atHostTime: 1_000),
                "\(message) no debería consumirse con Internal")
        }
    }

    /// Y no arrancan el transporte, que es la consecuencia que se nota.
    func testAStartDoesNotPlayWhileInternal() {
        let transport = makeTransport()

        transport.receive(.start, atHostTime: 1_000)

        XCTAssertFalse(transport.isPlaying)
    }

    // MARK: - External escucha

    /// Con `External`, los tres llegan al transporte.
    func testExternalConsumesTheThree() {
        let transport = makeTransport()
        transport.clockSource = .external

        for message in [MIDIMessage.timingClock, .start, .stop] {
            XCTAssertTrue(
                transport.receive(message, atHostTime: 1_000),
                "\(message) debería consumirse con External")
        }
    }

    /// Lo que no es del reloj no se consume por elegir External: los knobs
    /// siguen su camino.
    func testExternalDoesNotSwallowControlMessages() throws {
        let transport = makeTransport()
        transport.clockSource = .external
        let message = MIDIMessage.controlChange(
            channel: try XCTUnwrap(MIDIChannel(1)),
            controller: try XCTUnwrap(MIDIController(70)),
            value: 1)

        XCTAssertFalse(transport.receive(message, atHostTime: 1_000))
    }

    // MARK: - Cambiar de fuente

    /// La elección se puede cambiar en caliente, que es lo que hace el selector
    /// de la pantalla MIDI.
    func testTheSourceCanBeChangedBackAndForth() {
        let transport = makeTransport()

        transport.clockSource = .external
        XCTAssertTrue(transport.receive(.timingClock, atHostTime: 1_000))

        transport.clockSource = .internal
        XCTAssertFalse(transport.receive(.timingClock, atHostTime: 2_000))
    }
}
