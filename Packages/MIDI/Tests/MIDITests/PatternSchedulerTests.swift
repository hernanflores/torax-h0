import Engine
import XCTest
@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre en los
/// targets de test.
private typealias Pattern = Engine.Pattern

/// Tests del scheduler que recorre los dieciséis Tracks.
///
/// **Un reloj y dieciséis rejillas.** Lo que estos tests fijan es que recorrer
/// no cambia lo que ya sonaba —la primera comprobación, y la que más importa— y
/// que el coste crece con los Tracks que tienen material, no con dieciséis
/// siempre.
///
/// Se testea aquí y no sobre `SchedulerThread` por la misma razón que
/// `TrackSchedulerTests`: el horizonte se da a mano, así que «la ventana
/// siguiente» es un hecho comprobable y no una carrera contra el reloj.
final class PatternSchedulerTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private let stepNanoseconds: Int64 = 125_000_000

    private func track(
        steps stepCount: Int,
        pulses pulseCount: Int,
        pitch pitchValue: Int = 60,
        division: Division = .sixteenth
    ) -> Track {
        Track(
            shape: Shape(
                steps: Steps(stepCount)!,
                pulses: Pulses(pulseCount)!,
                division: division
            ),
            pool: PitchPool().inserting(Pitch(pitchValue)!)
        )
    }

    /// Un Pattern con material solo en las posiciones dadas.
    private func pattern(_ tracks: [Int: Track]) -> Pattern {
        tracks.reduce(into: Pattern()) { $0 = $0.replacing($1.value, at: $1.key) }
    }

    /// Avanza una ventana y devuelve lo emitido, con el Track de cada evento.
    private func emit(
        _ scheduler: inout PatternScheduler,
        upToStep stepIndex: Int,
        from handoff: PatternHandoff? = nil
    ) -> [(track: Int, step: Int, pitch: Int?)] {
        var events: [(track: Int, step: Int, pitch: Int?)] = []
        scheduler.advance(
            toHorizon: Int64(stepIndex) * stepNanoseconds,
            refreshingFrom: handoff
        ) { track, step, pitch, _, _ in
            events.append((track, step, pitch?.value))
        }
        return events
    }

    // MARK: - No romper lo que ya sonaba

    /// **La regresión que más importa.** Con un solo Track con material, lo
    /// emitido es lo mismo que emitía el scheduler de un Track: mismos Steps, en
    /// el mismo orden, con la misma altura.
    func testWithOneTrackTheOutputIsWhatItAlwaysWas() {
        let only = track(steps: 16, pulses: 4)

        var single = TrackScheduler(timeline: timeline(.sixteenth), material: .track(only))
        var expected: [(step: Int, pitch: Int?)] = []
        single.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: nil) { step, pitch, _, _ in
            expected.append((step, pitch?.value))
        }

        var scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: only]))
        let events = emit(&scheduler, upToStep: 16)

        XCTAssertEqual(events.map(\.step), expected.map(\.step))
        XCTAssertEqual(events.map(\.pitch), expected.map(\.pitch))
        XCTAssertTrue(events.allSatisfy { $0.track == 0 })
    }

    // MARK: - Varios Tracks

    func testTwoTracksBothEmitAtTheirOwnPositions() {
        var scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track(steps: 16, pulses: 4, pitch: 60),
                5: track(steps: 16, pulses: 2, pitch: 72),
            ])
        )

        let events = emit(&scheduler, upToStep: 16)

        XCTAssertEqual(events.filter { $0.track == 0 }.map(\.step), [0, 4, 8, 12])
        XCTAssertEqual(events.filter { $0.track == 5 }.map(\.step), [0, 8])
        XCTAssertTrue(events.filter { $0.track == 0 }.allSatisfy { $0.pitch == 60 })
        XCTAssertTrue(events.filter { $0.track == 5 }.allSatisfy { $0.pitch == 72 })
    }

    /// **Un Track vacío no programa nada** (NFR3): el coste crece con los Tracks
    /// con material, no con dieciséis siempre.
    func testEmptyTracksEmitNothing() {
        var scheduler = PatternScheduler(tempo: tempo, pattern: Pattern())
        XCTAssertTrue(emit(&scheduler, upToStep: 32).isEmpty)
    }

    /// Y los vacíos no estorban a los que sí tienen material.
    func testAnEmptyTrackDoesNotSilenceTheOthers() {
        var scheduler = PatternScheduler(
            tempo: tempo, pattern: pattern([15: track(steps: 16, pulses: 4)]))

        let events = emit(&scheduler, upToStep: 16)
        XCTAssertEqual(events.map(\.step), [0, 4, 8, 12])
        XCTAssertTrue(events.allSatisfy { $0.track == 15 })
    }

    /// Con los dieciséis llenos no se pierde ningún evento dentro de la ventana.
    func testWithSixteenFullTracksNoEventIsLost() {
        var full: [Int: Track] = [:]
        for index in 0..<16 { full[index] = track(steps: 8, pulses: 8, pitch: 48 + index) }

        var scheduler = PatternScheduler(tempo: tempo, pattern: pattern(full))
        let events = emit(&scheduler, upToStep: 8)

        XCTAssertEqual(events.count, 16 * 8, "se perdieron eventos")
        for index in 0..<16 {
            let mine = events.filter { $0.track == index }
            XCTAssertEqual(mine.map(\.step), Array(0..<8), "Track \(index + 1)")
            XCTAssertTrue(mine.allSatisfy { $0.pitch == 48 + index }, "Track \(index + 1)")
        }
    }

    // MARK: - El relevo de snapshot

    /// El Pattern publicado se recoge una vez por ventana y lo ven todos los
    /// Tracks: leerlo dieciséis veces dejaría que dos Tracks tocaran material de
    /// publicaciones distintas.
    func testThePublishedPatternIsPickedUpByEveryTrack() {
        var scheduler = PatternScheduler(tempo: tempo, pattern: Pattern())
        let handoff = PatternHandoff(Pattern())

        var updated: [Int: Track] = [:]
        for index in 0..<16 { updated[index] = track(steps: 4, pulses: 4, pitch: 60) }
        handoff.publish(pattern(updated))

        let events = emit(&scheduler, upToStep: 4, from: handoff)
        XCTAssertEqual(events.count, 16 * 4)
    }

    // MARK: - Helpers

    private func timeline(_ division: Division) -> MusicalTimeline {
        MusicalTimeline(tempo: tempo, division: division)
    }
}
