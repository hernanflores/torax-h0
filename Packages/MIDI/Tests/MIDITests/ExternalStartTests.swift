import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del arranque con un maestro externo.
///
/// **Un solo maestro manda.** Con `External`, el botón de la pantalla arma y el
/// Start del hardware dispara: no hay estado en el que la app y el controlador
/// lleven transportes distintos.
///
/// Los tests que arrancan de verdad el bucle del scheduler se agrupan a
/// propósito —igual que en `TransportTests`—: cada reproducción crea un hilo de
/// prioridad máxima y acumularlos empeora el flake de CoreMIDI.
final class ExternalStartTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        var all: [MIDIMessage] { lock.withLock { messages } }
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

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    // MARK: - Armar no es sonar

    /// Pulsar Play con `External` no suena: deja el transporte esperando el
    /// Start del maestro. Es lo que la pantalla enseña como `Waiting for clock`.
    func testPlayArmsWithoutSounding() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()

        XCTAssertTrue(transport.isArmed)
        XCTAssertFalse(transport.isPlaying)
        XCTAssertTrue(recorder.all.isEmpty, "armado y aun así emitió")
    }

    /// Un Start que llega sin haber armado no arranca nada: el transporte lo
    /// pide la app, y el maestro solo decide **cuándo**.
    func testAStartWithoutArmingDoesNothing() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.receive(.start, atHostTime: HostClock.now())

        XCTAssertFalse(transport.isPlaying)
        XCTAssertFalse(transport.isArmed)
        XCTAssertTrue(recorder.all.isEmpty)
    }

    /// Y desarmar desde la pantalla deja el transporte insensible al Start.
    func testStoppingWhileArmedDisarms() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        transport.stop()

        XCTAssertFalse(transport.isArmed)

        transport.receive(.start, atHostTime: HostClock.now())
        XCTAssertFalse(transport.isPlaying)
    }

    /// Armar dos veces no cambia nada: el botón no acumula estado.
    func testArmingTwiceIsIdempotent() {
        let transport = makeTransport(Recorder())

        transport.play()
        transport.play()

        XCTAssertTrue(transport.isArmed)
        XCTAssertFalse(transport.isPlaying)
    }

    // MARK: - El Start dispara

    /// Ciclo completo con el maestro: armar, Start, sonar, y que el origen de la
    /// rejilla sea el instante del Start.
    ///
    /// Va todo en un test —y no en cuatro— porque cada arranque del bucle
    /// empeora el flake de CoreMIDI de la suite.
    func testTheMasterStartTriggersPlaybackFromItsOwnInstant() throws {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        let origin = HostClock.now()
        transport.receive(.start, atHostTime: origin)

        XCTAssertTrue(transport.isPlaying)
        XCTAssertFalse(transport.isArmed, "sonando ya no está armado, está tocando")

        // El origen de la rejilla es el instante del Start, no el del arranque
        // del hilo: el playhead se mide contra él. Se espera a que el hilo lo
        // publique —lo hace nada más entrar en el bucle— porque `start` vuelve
        // sin esperarlo.
        waitUntil { transport.playheadClock.elapsedNanoseconds() != nil }
        let playhead = try XCTUnwrap(transport.playheadClock.elapsedNanoseconds())
        let sinceStart = HostClock.nanoseconds(fromHostTicks: HostClock.now() &- origin)
        XCTAssertEqual(
            Double(playhead), Double(sinceStart), accuracy: 5_000_000,
            "el origen no es el instante del Start")

        waitUntil { !recorder.all.isEmpty }
        XCTAssertFalse(recorder.all.isEmpty, "arrancó con el Start y no emitió nada")

        transport.stop()
        XCTAssertFalse(transport.isPlaying)
    }
}
