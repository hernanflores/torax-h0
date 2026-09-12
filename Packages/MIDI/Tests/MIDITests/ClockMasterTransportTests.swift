import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de la app como maestro de clock, vista desde el transporte.
///
/// Lo que se comprueba aquí es **lo que sale por el cable en las dos puertas**:
/// que Play mande `start` antes del primer pulso y que Stop mande `stop` junto al
/// apagado. La rejilla del pulso la fijan `ClockPulseSchedulerTests` y
/// `ClockPulseEmissionTests`; esto es el orden, que es lo único que puede dejar a
/// un esclavo corriendo después de parar.
///
/// Los tests que arrancan de verdad el bucle se agrupan a propósito, como en
/// `ExternalStartTests`: cada reproducción crea un hilo de prioridad máxima y
/// acumularlos empeora el flake de CoreMIDI.
final class ClockMasterTransportTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(message: MIDIMessage, hostTime: UInt64)] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { entries.append((message, hostTime)) }
        }

        var all: [(message: MIDIMessage, hostTime: UInt64)] { lock.withLock { entries } }

        func instants(of wanted: MIDIMessage) -> [UInt64] {
            all.filter { $0.message == wanted }.map(\.hostTime)
        }

        var allNotesOffInstants: [UInt64] {
            all.compactMap { entry in
                guard case .controlChange(_, let controller, _) = entry.message,
                    controller == MIDIController.allNotesOff
                else { return nil }
                return entry.hostTime
            }
        }
    }

    /// 300 BPM: el pulso cae cada 8,3 ms, así que los tests no esperan mucho.
    private func makeTransport(_ recorder: Recorder) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    // MARK: - Play manda Start y el pulso

    /// Arrancar emite `start` (FR4).
    func testPlayEmitsStart() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { !recorder.instants(of: .start).isEmpty }
        transport.stop()

        XCTAssertEqual(recorder.instants(of: .start).count, 1)
    }

    /// El transporte emite el pulso mientras suena (FR1).
    func testPlayEmitsClockPulses() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.instants(of: .timingClock).count >= 24 }
        transport.stop()

        XCTAssertGreaterThanOrEqual(recorder.instants(of: .timingClock).count, 24)
    }

    /// **`start` no puede llegar después del primer pulso** (FR4): un esclavo que
    /// recibe clock antes del arranque lo descarta, y se pierde la primera negra.
    func testStartIsStampedNoLaterThanTheFirstPulse() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.instants(of: .timingClock).count >= 8 }
        transport.stop()

        guard let start = recorder.instants(of: .start).first,
            let firstPulse = recorder.instants(of: .timingClock).first
        else { return XCTFail("faltan el Start o el primer pulso") }

        XCTAssertLessThanOrEqual(start, firstPulse)
    }

    // MARK: - Stop manda Stop, y con el apagado

    /// Parar emite `stop` (FR5).
    func testStopEmitsStop() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { !recorder.instants(of: .timingClock).isEmpty }
        transport.stop()

        XCTAssertEqual(recorder.instants(of: .stop).count, 1)
    }

    /// **`stop` va sellado con el apagado y no antes** (FR5). Sellarlo en «ahora»
    /// lo pondría por delante de los note-on ya programados, y el esclavo pararía
    /// mientras la app todavía suena.
    func testStopIsStampedWithTheSilencing() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { !recorder.instants(of: .timingClock).isEmpty }
        transport.stop()

        guard let stop = recorder.instants(of: .stop).first,
            let silence = recorder.allNotesOffInstants.first
        else { return XCTFail("faltan el Stop o el apagado") }

        XCTAssertEqual(stop, silence)
    }

    /// Parar lo ya parado no manda nada (FR6): sin transición no hay nada que
    /// decirle a nadie.
    func testStoppingWhatIsAlreadyStoppedEmitsNothing() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.stop()

        XCTAssertTrue(recorder.all.isEmpty)
    }

    /// **Parado no hay clock en vacío** (FR6): el pulso se acaba con el
    /// transporte.
    func testNoPulsesKeepComingAfterStop() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.instants(of: .timingClock).count >= 8 }
        transport.stop()

        // El hilo puede tardar hasta media ventana en ver la bandera, así que se
        // le da margen antes de tomar la referencia.
        usleep(60_000)
        let settled = recorder.instants(of: .timingClock).count
        usleep(200_000)

        XCTAssertEqual(recorder.instants(of: .timingClock).count, settled)
    }

    // MARK: - Con maestro externo

    /// **Con `External`, `start` sale cuando el transporte arranca de verdad**
    /// (FR8): lo dispara el maestro, y la app dice lo que hace, no lo que le
    /// dicen.
    func testExternalStartMakesTheAppAnnounceItsOwnStart() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.clockSource = .external

        transport.receive(.start, atHostTime: HostClock.now())
        waitUntil { !recorder.instants(of: .start).isEmpty }
        transport.stop()

        XCTAssertEqual(recorder.instants(of: .start).count, 1)
    }
}
