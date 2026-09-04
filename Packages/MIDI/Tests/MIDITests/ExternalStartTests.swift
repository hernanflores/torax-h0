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

    // MARK: - Play arranca ya

    /// Con `External`, Play suena en el momento: **el maestro manda, pero no
    /// hace falta esperarlo.** Antes armaba y esperaba el Start, y en
    /// dispositivo resultó no ser intuitivo (2026-09-03).
    func testPlayStartsImmediatelyEvenWithAnExternalClock() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()

        XCTAssertTrue(transport.isPlaying)

        waitUntil { !recorder.all.isEmpty }
        XCTAssertFalse(recorder.all.isEmpty, "arrancó y no emitió nada")

        transport.stop()
    }

    // MARK: - El maestro manda

    /// **El Start del maestro arranca aunque nadie haya pulsado Play.** Elegir
    /// `External` es decir que el transporte lo lleva el hardware.
    func testAMasterStartPlaysWithoutTouchingTheApp() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.receive(.start, atHostTime: HostClock.now())

        XCTAssertTrue(transport.isPlaying)
        transport.stop()
    }

    /// Con `Internal` sigue sin arrancar: el selector es lo que decide a quién
    /// se hace caso, y esa parte no cambia.
    func testAMasterStartDoesNothingWhileInternal() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.clockSource = .internal

        transport.receive(.start, atHostTime: HostClock.now())

        XCTAssertFalse(transport.isPlaying)
        XCTAssertTrue(recorder.all.isEmpty)
    }

    // MARK: - El Start dispara

    /// Ciclo completo con el maestro: Start, sonar con el origen en su propio
    /// instante, y parar.
    ///
    /// Va todo en un test —y no en cuatro— porque cada arranque del bucle
    /// empeora el flake de CoreMIDI de la suite.
    func testTheMasterStartTriggersPlaybackFromItsOwnInstant() throws {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        let origin = HostClock.now()
        transport.receive(.start, atHostTime: origin)

        XCTAssertTrue(transport.isPlaying)

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
