import Engine
import XCTest
@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del barrido de silencio acotado a unos Tracks (FR4).
///
/// **Es el mismo barrido que hace `stop()`, con un ámbito.** Parar apaga los
/// doce; mutear apaga uno. Lo que no puede pasar es que apagar uno toque a los
/// demás: once instrumentos callados por silenciar el bombo sería peor que la
/// nota colgada que esto viene a evitar.
final class TrackSilenceTests: XCTestCase {

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

    // MARK: - El ámbito

    /// Apagar un Track manda su `all notes off` por **su** canal y por ninguno
    /// más.
    func testSilencingOneTrackTouchesOnlyItsChannel() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.silence(tracks: [3], atHostTime: 0)

        XCTAssertEqual(allNotesOffChannels(in: recorder.captured), [4])
    }

    /// Y los note-off del barrido son los de **sus** alturas: el Track 3 lleva
    /// la altura 51, y ninguna de las otras once aparece.
    func testSilencingOneTrackSweepsOnlyItsOwnPitches() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.silence(tracks: [3], atHostTime: 0)

        let swept = noteOffs(in: recorder.captured)
        XCTAssertEqual(swept, [Pair(channel: 4, note: 51)])
    }

    /// Varios a la vez: soltar un solo deja inaudibles a varios Tracks de golpe,
    /// y el barrido tiene que cubrirlos todos.
    func testSilencingSeveralTracksCoversAllOfThem() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.silence(tracks: [0, 5, 11], atHostTime: 0)

        XCTAssertEqual(allNotesOffChannels(in: recorder.captured), [1, 6, 12])
    }

    /// Un conjunto vacío no manda nada. Es el caso de desmutear: nadie se ha
    /// vuelto inaudible, así que no hay nada que apagar.
    func testSilencingNothingSendsNothing() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.silence(tracks: [], atHostTime: 0)

        XCTAssertTrue(recorder.captured.isEmpty)
    }

    // MARK: - Lo que hereda de `stop()`

    /// **Se barren los dieciséis Cycles, no solo el vigente.** El cursor de
    /// reproducción vive en el hilo del scheduler, así que desde aquí no se sabe
    /// cuál suena: una altura que solo existe en el Cycle 5 puede ser justo la
    /// que está sonando.
    func testTheSweepCoversEveryCycleOfTheTrack() {
        let recorder = Recorder()
        let transport = transport(recorder)

        let base = Cycle(
            shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
            pool: PitchPool().inserting(Pitch(60)!),
            channel: Channel(1)!
        )
        let hidden = Cycle(
            shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
            pool: PitchPool().inserting(Pitch(84)!),
            channel: Channel(1)!
        )
        let track = Track(base).replacing(hidden, at: 5)
        transport.publish(Pattern().replacing(track, at: 0))

        transport.silence(tracks: [0], atHostTime: 0)

        XCTAssertTrue(
            noteOffs(in: recorder.captured).contains(Pair(channel: 1, note: 84)),
            "no se barrió la altura que solo vive en el Cycle 6")
    }

    /// **El `all notes off` va primero y los note-off después**, con el mismo
    /// criterio que `stop()`: si el sintetizador honra el primero, lo demás es
    /// confirmación; si no lo honra, el barrido lo cubre.
    func testTheAllNotesOffComesBeforeTheSweep() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.silence(tracks: [0], atHostTime: 0)

        let messages = recorder.captured
        let firstSweep = messages.firstIndex { if case .noteOff = $0 { return true } else { return false } }
        let lastControl = messages.lastIndex { if case .controlChange = $0 { return true } else { return false } }
        XCTAssertNotNil(firstSweep)
        XCTAssertNotNil(lastControl)
        XCTAssertLessThan(lastControl!, firstSweep!)
    }

    /// Un canal compartido por dos Tracks no se apaga dos veces: el barrido no
    /// repite pares canal+altura, como el de `stop()`.
    func testASharedChannelIsNotSilencedTwice() {
        let recorder = Recorder()
        let transport = transport(recorder)

        let shared = Cycle(
            shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
            pool: PitchPool().inserting(Pitch(60)!),
            channel: Channel(7)!
        )
        // `Track(_:)` pone ese Cycle en los dieciséis huecos: si solo se
        // sustituyera el primero, los otros quince conservarían su canal por
        // defecto y el barrido —que los recorre todos, y hace bien— tocaría
        // tres canales en vez de uno.
        transport.publish(
            Pattern().replacing(Track(shared), at: 0).replacing(Track(shared), at: 1))

        transport.silence(tracks: [0, 1], atHostTime: 0)

        let controls = recorder.captured.filter {
            if case .controlChange = $0 { return true } else { return false }
        }
        XCTAssertEqual(controls.count, 1)
        XCTAssertEqual(noteOffs(in: recorder.captured), [Pair(channel: 7, note: 60)])
    }

    // MARK: - Helpers

    private struct Pair: Hashable {
        let channel: Int
        let note: Int
    }

    private func noteOffs(in messages: [MIDIMessage]) -> Set<Pair> {
        var pairs: Set<Pair> = []
        for case .noteOff(let channel, let note, _) in messages {
            pairs.insert(Pair(channel: channel.number, note: Int(note.value)))
        }
        return pairs
    }

    private func allNotesOffChannels(in messages: [MIDIMessage]) -> Set<Int> {
        var channels: Set<Int> = []
        for case .controlChange(let channel, let controller, _) in messages
        where controller == MIDIController.allNotesOff {
            channels.insert(channel.number)
        }
        return channels
    }

    /// Los doce con material: el Track N en el canal N+1, con la altura 48+N.
    private func everyTrack() -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            let track = Cycle(
                shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48 + index)!),
                channel: Channel(index + 1)!
            )
            pattern = pattern.replacing(track, at: index)
        }
        return pattern
    }

    private func transport(_ recorder: Recorder) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            track: Cycle(shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!)),
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }
}
