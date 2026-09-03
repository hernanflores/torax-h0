import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del Stop del maestro.
///
/// **Simétrico al Start.** Mientras `External` esté elegido manda el maestro, y
/// parar tiene que apagar exactamente igual que el botón de la pantalla: el
/// riesgo caro de este track no es que no pare, es que pare **dejando una nota
/// sonando** en el sintetizador.
final class ExternalStopTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        var all: [MIDIMessage] { lock.withLock { messages } }

        var allNotesOffCount: Int {
            all.filter {
                if case .controlChange(_, let controller, _) = $0 {
                    controller == MIDIController.allNotesOff
                } else {
                    false
                }
            }.count
        }
    }

    private func makeTransport(_ recorder: Recorder) -> Transport {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth)
        let transport = Transport(
            configuration: SchedulerConfiguration(
                timeline: timeline, lookAheadNanoseconds: 20_000_000),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: recorder.record
        )
        transport.clockSource = .external
        return transport
    }

    // MARK: - Parar de verdad

    /// El Stop del maestro para y apaga por el mismo camino que `stop()`: el
    /// `all notes off` por canal más el barrido de alturas. Se comprueba contra
    /// el botón de la pantalla, que es la referencia.
    func testTheMasterStopSilencesLikeTheScreenButton() {
        let byMaster = Recorder()
        let master = makeTransport(byMaster)
        master.play()
        master.receive(.start, atHostTime: HostClock.now())
        master.receive(.stop, atHostTime: HostClock.now())

        XCTAssertFalse(master.isPlaying)
        XCTAssertGreaterThan(
            byMaster.allNotesOffCount, 0, "paró sin mandar ningún all notes off")
    }

    /// Y desarma: el siguiente Start no arranca sin volver a pulsar Play.
    func testTheMasterStopDisarms() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        XCTAssertTrue(transport.isArmed)

        transport.receive(.stop, atHostTime: HostClock.now())

        XCTAssertFalse(transport.isArmed)

        transport.receive(.start, atHostTime: HostClock.now())
        XCTAssertFalse(transport.isPlaying, "arrancó con un Start después de un Stop")
    }

    // MARK: - Casos que no hacen nada

    /// Un Stop con el transporte parado no hace nada ni falla: por el cable
    /// llegan Stops de sesiones que no son la nuestra.
    func testAStopWhileStoppedIsHarmlessAndSilent() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.receive(.stop, atHostTime: HostClock.now())
        transport.receive(.stop, atHostTime: HostClock.now())

        XCTAssertFalse(transport.isPlaying)
        XCTAssertTrue(recorder.all.isEmpty, "paró sin haber tocado y aun así emitió")
    }

    /// Con `Internal`, el Stop del maestro no para nada: la elección manda.
    func testAnInternalTransportIgnoresTheMasterStop() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.clockSource = .internal

        transport.play()
        XCTAssertTrue(transport.isPlaying)

        transport.receive(.stop, atHostTime: HostClock.now())

        XCTAssertTrue(transport.isPlaying, "el maestro paró un transporte que no le hace caso")
        transport.stop()
    }
}
