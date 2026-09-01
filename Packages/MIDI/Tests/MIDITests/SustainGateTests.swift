import Engine
import XCTest

@testable import MIDI

/// Tests de la duración de nota.
///
/// Hasta esta rebanada el gate era una constante de 25 ms que el propio
/// `NoteEmitter` declaraba provisional, y cuyo valor salía de una restricción
/// —que cupiera en el Step más corto— y no de un criterio musical. Ahora sale
/// de Sustain, que es lo que la Pre Spec pone en su sitio.
final class SustainGateTests: XCTestCase {

    /// 120 BPM en 1/16: un Step dura 125 ms exactos, que es un número redondo
    /// contra el que comparar sin arrastrar redondeos.
    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private func groove(sustain: Int) -> Groove {
        Groove(velocity: .default, sustain: Sustain(percent: sustain)!, probability: .default)
    }

    private func gateTicks(sustain: Int) -> UInt64 {
        let emitter = NoteEmitter()
        var sent: [(MIDIMessage, UInt64)] = []
        emitter.emit(
            pitch: Pitch(60)!, groove: groove(sustain: sustain), on: MIDIChannel(1)!,
            stepDurationNanoseconds: Int64(timeline.stepDurationNanoseconds), atHostTime: 0
        ) {
            message, time in
            sent.append((message, time))
        }
        return sent[1].1
    }

    // MARK: - El 100% es una Division completa

    /// **Comparado contra `MusicalTimeline` y no contra un número escrito a
    /// mano.** Si el gate se calculara con otra idea de cuánto dura un Step, un
    /// literal en el test no lo detectaría: coincidirían los dos errores.
    func testFullSustainLastsExactlyOneDivision() {
        let expected = HostClock.hostTicks(
            fromNanoseconds: UInt64(timeline.stepDurationNanoseconds))
        XCTAssertEqual(gateTicks(sustain: 100), expected)
    }

    // MARK: - Los extremos

    func testOnePercentIsPercussive() {
        let step = timeline.stepDurationNanoseconds
        let expected = HostClock.hostTicks(fromNanoseconds: UInt64(step / 100))
        XCTAssertEqual(gateTicks(sustain: 1), expected)
    }

    /// El 200% liga sobre el Step siguiente y no alcanza el tercero: es lo que
    /// acota el solape a un solo vecino.
    func testTwoHundredPercentLastsTwoDivisions() {
        let step = timeline.stepDurationNanoseconds
        let expected = HostClock.hostTicks(fromNanoseconds: UInt64(step * 2))
        XCTAssertEqual(gateTicks(sustain: 200), expected)
    }

    func testTheGateGrowsWithSustain() {
        let short = gateTicks(sustain: 25)
        let medium = gateTicks(sustain: 100)
        let long = gateTicks(sustain: 200)

        XCTAssertLessThan(short, medium)
        XCTAssertLessThan(medium, long)
    }

    // MARK: - El note-off sigue sellado, no programado

    /// La precisión la da el timestamp, no el momento del envío: los dos
    /// mensajes salen en la **misma** llamada, cada uno con su instante.
    func testBothMessagesAreDeliveredInTheSameCall() {
        let emitter = NoteEmitter()
        var sent: [(MIDIMessage, UInt64)] = []
        emitter.emit(
            pitch: Pitch(60)!, groove: groove(sustain: 200), on: MIDIChannel(1)!,
            stepDurationNanoseconds: Int64(timeline.stepDurationNanoseconds), atHostTime: 7_000
        ) {
            message, time in
            sent.append((message, time))
        }

        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].1, 7_000)
        XCTAssertGreaterThan(sent[1].1, sent[0].1)
    }
}

/// Tests del apagado al parar, con gates que ya pueden ser largos.
///
/// Mientras el gate era una constante de 25 ms, una altura que sonara y ya no
/// estuviera en el pool se apagaba sola antes de que nadie la oyera. Con Sustain
/// al 200% sobre una Division lenta puede colgarse segundos, así que el hueco
/// que `Transport.stop()` documentaba deja de ser teórico.
final class StopSilencesEverythingTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, at hostTime: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            messages.append(message)
        }

        var captured: [MIDIMessage] {
            lock.lock()
            defer { lock.unlock() }
            return messages
        }
    }

    private func transport(pool: PitchPool, recorder: Recorder) -> Transport {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth)
        return Transport(
            configuration: SchedulerConfiguration(
                timeline: timeline,
                lookAheadNanoseconds: 20_000_000
            ),
            track: Track(shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!), pool: pool),
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }

    /// **El caso que el barrido del pool no cubre.** El Track suena con una
    /// altura, esa altura sale del pool, y se para: el barrido ya no la conoce.
    func testStoppingSendsAllNotesOffForPitchesNoLongerInThePool() {
        let recorder = Recorder()
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)

        let transport = transport(pool: pool, recorder: recorder)
        transport.play()
        transport.publish(
            Track(shape: transport.track.shape, pool: PitchPool(), groove: transport.track.groove))
        transport.stop()

        let allNotesOff = recorder.captured.contains { message in
            if case .controlChange(_, let controller, let value) = message {
                return controller == MIDIController.allNotesOff && value == 0
            }
            return false
        }
        XCTAssertTrue(allNotesOff, "parar no mandó All Notes Off")
    }

    /// **El barrido sigue haciendo falta.** No todos los sintetizadores honran
    /// el CC 123; los note-offs explícitos son la red para esos.
    func testStoppingStillSweepsThePoolWithExplicitNoteOffs() {
        let recorder = Recorder()
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        pool = pool.toggling(Pitch(64)!)

        let transport = transport(pool: pool, recorder: recorder)
        transport.play()
        transport.stop()

        let silenced = Set(
            recorder.captured.compactMap { message -> UInt8? in
                if case .noteOff(_, let note, let velocity) = message, velocity.value == 0 {
                    return note.value
                }
                return nil
            })
        XCTAssertTrue(silenced.contains(60))
        XCTAssertTrue(silenced.contains(64))
    }
}
