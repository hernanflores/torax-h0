import Engine
import Foundation
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de qué pasa con los Cycles al arrancar y al parar.
///
/// **Play reinicia y Stop apaga**, y las dos cosas se complican con Cycles.
/// Play, porque el desarrollo tiene que ser reproducible: la promesa de
/// `tech-stack.md` es que pulsar Play dos veces suene igual, y con Cycles eso
/// incluye el orden de los Cycles y las omisiones de cada uno. Stop, porque lo
/// que puede estar sonando ya no es un pool y un canal por Track, sino hasta
/// dieciséis de cada.
final class PlayRestartsCyclesTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000

    private func cycle(
        pitch: Int, pulses: Int = 16, probability: Int = 100, channel: Int = 1,
        delay: Int = 0
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(pitch)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: Probability(percent: probability)!,
                timing: .default,
                delay: Delay(percent: delay)!
            ),
            channel: Channel(channel)!
        )
    }

    private func track(_ cycles: [Cycle]) -> Track {
        var track = Track(cycles[0]).withActiveCount(cycles.count)
        for (index, cycle) in cycles.enumerated() {
            track = track.replacing(cycle, at: index)
        }
        return track
    }

    private func events(_ pattern: Pattern, upToStep stepIndex: Int, seed: UInt64 = 7)
        -> [(step: Int, pitch: Int?)]
    {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern, seed: seed)
        var collected: [(step: Int, pitch: Int?)] = []
        scheduler.advance(toHorizon: Int64(stepIndex) * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, pitch, _, _ in
            guard track == 0 else { return }
            collected.append((step, pitch?.value))
        }
        return collected
    }

    // MARK: - Play reinicia

    /// **FR6 — tras Play los dieciséis arrancan en su Cycle 1.** Se comprueba
    /// donde importa: en lo que emite el scheduler recién construido, que es lo
    /// que hace Play. Un Track dejado en el Cycle 3 con el transporte parado
    /// suena desde el 1.
    func testPlayStartsEveryTrackOnItsFirstCycle() {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            let left = track([cycle(pitch: 48), cycle(pitch: 60), cycle(pitch: 72)])
                .withCursor(2)
            pattern = pattern.replacing(left, at: index)
        }

        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        var firstPitch: [Int: Int?] = [:]
        scheduler.advance(toHorizon: stepNanoseconds, refreshingFrom: nil) {
            track, _, _, pitch, _, _ in
            if firstPitch[track] == nil { firstPitch[track] = pitch?.value }
        }

        XCTAssertEqual(firstPitch.count, Pattern.trackCount)
        for (track, pitch) in firstPitch {
            XCTAssertEqual(pitch, 48, "el Track \(track + 1) no arrancó en su Cycle 1")
        }
    }

    /// **Dos pasadas de Play producen la misma secuencia de Cycles y las mismas
    /// omisiones.** Es la promesa de `tech-stack.md` extendida al desarrollo:
    /// con Probability por medio, «igual» incluye qué Pulses se callan.
    func testTwoPlaysProduceTheSameDevelopmentAndTheSameOmissions() {
        let pattern = Pattern().replacing(
            track([
                cycle(pitch: 48, probability: 50),
                cycle(pitch: 60, probability: 50),
                cycle(pitch: 72, probability: 50),
            ]),
            at: 0
        )

        let first = events(pattern, upToStep: 160)
        let second = events(pattern, upToStep: 160)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.map(\.step), second.map(\.step))
        XCTAssertEqual(first.map(\.pitch), second.map(\.pitch))
    }

    /// **NFR5 — cambiar de Cycle no resiembra el generador de Probability.**
    ///
    /// Se comprueba comparando un Track de tres Cycles idénticos contra uno de
    /// un solo Cycle igual a ellos: si el avance resembrara, las omisiones se
    /// repetirían en cada vuelta y las dos listas dejarían de coincidir. Es una
    /// comprobación fuerte porque no mira el generador sino su efecto.
    func testChangingCycleDoesNotReseedTheRandomGenerator() {
        let quiet = cycle(pitch: 48, probability: 50)
        let three = Pattern().replacing(track([quiet, quiet, quiet]), at: 0)
        let one = Pattern().replacing(track([quiet]), at: 0)

        let withCycles = events(three, upToStep: 160)
        let without = events(one, upToStep: 160)

        XCTAssertFalse(withCycles.isEmpty)
        XCTAssertEqual(
            withCycles.map(\.step), without.map(\.step),
            "avanzar de Cycle movió las omisiones")
    }

    // MARK: - Stop apaga

    /// **Stop apaga lo que pudo estar sonando, y con Cycles eso es más de un
    /// pool y más de un canal.**
    ///
    /// El cursor de reproducción vive en el hilo del scheduler, así que desde
    /// aquí no se sabe qué Cycle estaba sonando al parar — saberlo exigiría que
    /// ese hilo publicara algo por cada vuelta, que es trabajo de tiempo real
    /// para resolver un caso de parada. Así que se apagan **todos los Cycles
    /// activos** de cada Track: sus alturas, por sus canales.
    ///
    /// Va en una sola reproducción porque cada Play arranca un hilo a prioridad
    /// máxima, y acumularlos es la condición que dispara `midi-test-flake`.
    func testStopSilencesEveryActiveCycleOnItsOwnChannel() {
        let recorder = Recorder()
        // Delay positivo: el caso que la rebanada 6 dejó anotado como capaz de
        // dejar notas sonando si Stop no barre lo suficiente.
        let sounding = track([
            cycle(pitch: 48, channel: 3, delay: 40),
            cycle(pitch: 72, channel: 9, delay: 40),
        ])

        let transport = Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            pattern: Pattern().replacing(sounding, at: 0),
            emitter: NoteEmitter(),
            send: recorder.record
        )

        transport.play()
        waitUntil { recorder.noteOnCount >= 4 }
        transport.stop()

        XCTAssertTrue(
            recorder.sawAllNotesOff(onChannel: 3), "no apagó el canal del Cycle 1")
        XCTAssertTrue(
            recorder.sawAllNotesOff(onChannel: 9), "no apagó el canal del Cycle 2")
        XCTAssertTrue(
            recorder.sawNoteOff(note: 48, onChannel: 3), "no barrió el pool del Cycle 1")
        XCTAssertTrue(
            recorder.sawNoteOff(note: 72, onChannel: 9), "no barrió el pool del Cycle 2")
    }

    // MARK: - Utilidades

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        private var all: [MIDIMessage] { lock.withLock { messages } }

        var noteOnCount: Int {
            all.filter { if case .noteOn = $0 { true } else { false } }.count
        }

        func sawAllNotesOff(onChannel number: Int) -> Bool {
            all.contains {
                if case .controlChange(let channel, let controller, _) = $0 {
                    channel.number == number && controller == MIDIController.allNotesOff
                } else {
                    false
                }
            }
        }

        func sawNoteOff(note value: Int, onChannel number: Int) -> Bool {
            all.contains {
                if case .noteOff(let channel, let note, _) = $0 {
                    channel.number == number && Int(note.value) == value
                } else {
                    false
                }
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 6) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(2_000) }
    }
}
