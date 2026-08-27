import Engine
import Foundation
import XCTest
@testable import MIDI

/// Tests del transporte.
///
/// El envío se inyecta, así que play y stop se verifican sin sintetizador y sin
/// CoreMIDI: lo que importa aquí es qué mensajes salen y cuándo dejan de salir.
final class TransportTests: XCTestCase {

    /// Recoge los mensajes que salen. El scheduler los emite desde su hilo, así
    /// que la recogida va con lock — es código de test, no del camino de timing.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        var all: [MIDIMessage] { lock.withLock { messages } }
        var noteOnCount: Int { all.filter { if case .noteOn = $0 { true } else { false } }.count }
        var noteOffCount: Int { all.filter { if case .noteOff = $0 { true } else { false } }.count }
    }

    /// 300 BPM con Division 1/16 da Steps de 50 ms. Anillo lleno para que cada
    /// Step dispare y el test no tenga que esperar al reparto euclidiano.
    private func makeTransport(_ recorder: Recorder) -> Transport {
        let steps = Steps(4)!
        return Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            track: Track(shape: Shape(steps: steps, pulses: Pulses(4, in: steps)!)),
            emitter: NoteEmitter(
                channel: MIDIChannel(1)!,
                note: MIDINote(48)!,
                velocity: MIDIVelocity(100)!
            ),
            send: recorder.record
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    // MARK: - Play y stop

    func testTransportStartsStopped() {
        XCTAssertFalse(makeTransport(Recorder()).isPlaying)
    }

    func testPlayStartsTheClock() {
        let transport = makeTransport(Recorder())
        defer { transport.stop() }
        transport.play()
        XCTAssertTrue(transport.isPlaying)
    }

    func testStopStopsTheClock() {
        let transport = makeTransport(Recorder())
        transport.play()
        transport.stop()
        XCTAssertFalse(transport.isPlaying)
    }

    func testPlayingTwiceIsHarmless() {
        let transport = makeTransport(Recorder())
        defer { transport.stop() }
        transport.play()
        transport.play()
        XCTAssertTrue(transport.isPlaying)
    }

    func testStoppingWithoutPlayingIsHarmless() {
        let transport = makeTransport(Recorder())
        transport.stop()
        XCTAssertFalse(transport.isPlaying)
    }

    // MARK: - Play produce sonido

    func testPlayEmitsNotes() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        defer { transport.stop() }

        transport.play()
        waitUntil { recorder.noteOnCount >= 3 }

        XCTAssertGreaterThanOrEqual(recorder.noteOnCount, 3, "el transporte no emitió notas")
    }

    /// Cada pulso emite el par: nunca puede haber más note-on que note-off.
    func testEveryNoteOnIsMatchedByANoteOff() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 4 }
        transport.stop()

        XCTAssertGreaterThanOrEqual(
            recorder.noteOffCount,
            recorder.noteOnCount,
            "quedaron notas sin apagar"
        )
    }

    // MARK: - Stop no deja notas colgadas

    /// Al parar se manda un note-off inmediato, además de los que ya iban
    /// sellados: si el usuario para justo entre el note-on y su note-off, la
    /// nota se queda sonando en el sintetizador hasta que alguien la apague.
    func testStopSendsAnImmediateNoteOff() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }
        let before = recorder.all.count
        transport.stop()

        XCTAssertGreaterThan(recorder.all.count, before, "parar no mandó nada")
        guard case .noteOff = recorder.all.last else {
            return XCTFail("el último mensaje al parar debería ser note-off")
        }
    }

    /// El note-off de parada apaga la misma altura y el mismo canal que se
    /// estaba tocando.
    func testStopNoteOffMatchesTheVoiceBeingPlayed() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }
        transport.stop()

        guard case let .noteOff(channel, note, _) = recorder.all.last else {
            return XCTFail("no se mandó note-off al parar")
        }
        XCTAssertEqual(channel, MIDIChannel(1)!)
        XCTAssertEqual(note, MIDINote(48)!)
    }

    /// Parado no se emite nada más.
    func testNothingIsEmittedAfterStopping() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 2 }
        transport.stop()

        let settled = recorder.all.count
        usleep(300_000)
        XCTAssertEqual(recorder.all.count, settled, "siguió emitiendo después de parar")
    }

    func testStoppingWithoutHavingPlayedEmitsNothing() {
        let recorder = Recorder()
        makeTransport(recorder).stop()
        XCTAssertTrue(recorder.all.isEmpty)
    }

    // MARK: - Publicar mientras suena

    func testTrackCanBePublishedWhilePlaying() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        defer { transport.stop() }

        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }

        let steps = Steps(8)!
        transport.publish(Track(shape: Shape(steps: steps, pulses: Pulses(1, in: steps)!)))

        let after = recorder.noteOnCount
        waitUntil { recorder.noteOnCount > after }
        XCTAssertGreaterThan(recorder.noteOnCount, after, "dejó de sonar tras publicar")
    }
}
