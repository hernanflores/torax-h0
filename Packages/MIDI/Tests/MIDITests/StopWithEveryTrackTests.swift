import Engine
import XCTest
@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de `Stop` con todos los Tracks sonando.
///
/// **Con un Track, una nota colgada era un descuido; con doce en doce canales,
/// apagar solo uno deja once instrumentos sonando.** Esta suite fija que parar
/// apaga todo, incluido el caso con Delay positivo que la rebanada 6 dejó
/// anotado como deuda: analizado, no reproducido.
final class StopWithEveryTrackTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [(message: MIDIMessage, hostTime: UInt64)] = []

        func record(_ message: MIDIMessage, at hostTime: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            messages.append((message, hostTime))
        }

        var captured: [MIDIMessage] {
            lock.lock()
            defer { lock.unlock() }
            return messages.map(\.message)
        }

        var timed: [(message: MIDIMessage, hostTime: UInt64)] {
            lock.lock()
            defer { lock.unlock() }
            return messages
        }
    }

    /// Cuántas notas quedan encendidas: los note-on menos los note-off, por
    /// canal y altura.
    private func hanging(in messages: [MIDIMessage]) -> [String: Int] {
        var balance: [String: Int] = [:]
        for message in messages {
            switch message {
            case .noteOn(let channel, let note, let velocity) where velocity.value > 0:
                balance["\(channel.number)/\(note.value)", default: 0] += 1
            case .noteOn(let channel, let note, _), .noteOff(let channel, let note, _):
                balance["\(channel.number)/\(note.value)", default: 0] -= 1
            case .controlChange:
                continue
            }
        }
        return balance.filter { $0.value > 0 }
    }

    private func allNotesOffChannels(in messages: [MIDIMessage]) -> Set<Int> {
        var channels: Set<Int> = []
        for case .controlChange(let channel, let controller, _) in messages
        where controller == MIDIController.allNotesOff {
            channels.insert(channel.number)
        }
        return channels
    }

    /// Todos los Tracks con material, cada uno con su altura y su canal.
    private func everyTrack(groove: Groove = .default) -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            let track = Cycle(
                shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48 + index)!),
                groove: groove,
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

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    // MARK: - Parar con todos sonando

    func testStoppingLeavesNoNoteHangingOnAnyChannel() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.play()
        waitUntil { self.hanging(in: recorder.captured).count >= 8 || recorder.captured.count > 64 }
        transport.stop()

        XCTAssertFalse(recorder.captured.isEmpty, "no llegó a sonar nada")
        XCTAssertTrue(
            hanging(in: recorder.captured).isEmpty,
            "quedaron notas colgadas: \(hanging(in: recorder.captured))")
    }

    /// El `all notes off` llega a **todos los canales en uso**, no solo al primero.
    func testStoppingSilencesEveryChannelInUse() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(everyTrack())

        transport.play()
        waitUntil { recorder.captured.count > 16 }
        transport.stop()

        XCTAssertEqual(
            allNotesOffChannels(in: recorder.captured), Set(1...Pattern.trackCount))
    }

    /// **La deuda de la rebanada 6**: con Delay positivo, parar entre el note-on
    /// y su note-off es más probable, porque el evento se emite desplazado
    /// respecto a su rejilla. Con doce Tracks a la vez, más todavía.
    func testStoppingWithPositiveDelayLeavesNothingHanging() {
        let recorder = Recorder()
        let transport = transport(recorder)
        transport.publish(
            everyTrack(
                groove: Groove(
                    velocity: .default,
                    sustain: Sustain(percent: 200)!,
                    probability: .default,
                    delay: Delay(percent: 75)!
                )))

        transport.play()
        waitUntil { recorder.captured.count > 16 }
        transport.stop()

        XCTAssertFalse(recorder.captured.isEmpty, "no llegó a sonar nada")
        XCTAssertTrue(
            hanging(in: recorder.captured).isEmpty,
            "quedaron notas colgadas con Delay positivo: \(hanging(in: recorder.captured))")
    }

    /// **Dos Tracks con Sustain distinto apagan cada uno a su hora.** El gate es
    /// del Track, no del transporte: con un solo emisor compartido, los dos
    /// habrían durado lo mismo.
    func testEachTrackHasItsOwnSustainGate() {
        let recorder = Recorder()
        let transport = transport(recorder)

        var pattern = Pattern()
        for (index, sustain) in [25, 200].enumerated() {
            pattern = pattern.replacing(
                Cycle(
                    shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                    pool: PitchPool().inserting(Pitch(60 + index)!),
                    groove: Groove(
                        velocity: .default,
                        sustain: Sustain(percent: sustain)!,
                        probability: .default
                    ),
                    channel: Channel(index + 1)!
                ),
                at: index
            )
        }
        transport.publish(pattern)

        transport.play()
        waitUntil {
            self.gate(in: recorder, channel: 1) != nil && self.gate(in: recorder, channel: 2) != nil
        }
        transport.stop()

        let short = gate(in: recorder, channel: 1)
        let long = gate(in: recorder, channel: 2)
        XCTAssertNotNil(short, "el Track 1 no llegó a sonar")
        XCTAssertNotNil(long, "el Track 2 no llegó a sonar")
        XCTAssertLessThan(short!, long!, "los dos Tracks apagaron a la misma hora")
    }

    /// La distancia entre el primer note-on de un canal y su note-off.
    private func gate(in recorder: Recorder, channel wanted: Int) -> UInt64? {
        let timed = recorder.timed
        guard
            let on = timed.first(where: {
                if case .noteOn(let channel, _, let velocity) = $0.message {
                    return channel.number == wanted && velocity.value > 0
                }
                return false
            }),
            let off = timed.first(where: {
                if case .noteOff(let channel, _, _) = $0.message {
                    return channel.number == wanted && $0.hostTime > on.hostTime
                }
                return false
            })
        else { return nil }
        return off.hostTime - on.hostTime
    }
}
