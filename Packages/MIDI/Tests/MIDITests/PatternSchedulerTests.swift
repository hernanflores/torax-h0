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
    ) -> Cycle {
        Cycle(
            shape: Shape(
                steps: Steps(stepCount)!,
                pulses: Pulses(pulseCount)!,
                division: division
            ),
            pool: PitchPool().inserting(Pitch(pitchValue)!)
        )
    }

    /// Un Pattern con material solo en las posiciones dadas.
    private func pattern(_ tracks: [Int: Cycle]) -> Pattern {
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
        ) { track, _, step, pitch, _, _ in
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

        var single = TrackScheduler(timeline: timeline(.sixteenth), material: .cycle(only))
        var expected: [(step: Int, pitch: Int?)] = []
        single.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: nil) {
            _, step, pitch, _, _ in
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
        var full: [Int: Cycle] = [:]
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

    // MARK: - Un reloj, dieciséis rejillas

    /// **Dos Divisions distintas comparten origen.** El 1/8 cae exactamente
    /// sobre uno de cada dos 1/16, y sigue cayendo ahí tras muchos ciclos: la
    /// fase se conserva porque las dos rejillas se miden contra el mismo origen,
    /// no porque se ajusten entre sí.
    func testTwoDivisionsShareTheOriginAndDoNotDrift() {
        var scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track(steps: 16, pulses: 16, division: .sixteenth),
                1: track(steps: 16, pulses: 16, division: .eighth),
            ])
        )

        // Cien ciclos de dieciséis Steps a 1/16.
        var offsets: [Int: [Int64]] = [0: [], 1: []]
        scheduler.advance(toHorizon: 1_600 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, _, _, offset in
            offsets[track]?.append(offset)
        }

        let sixteenths = offsets[0]!
        let eighths = offsets[1]!
        XCTAssertEqual(sixteenths.count, 1_600)
        XCTAssertEqual(eighths.count, 800, "el 1/8 debe caer la mitad de veces")

        // Cada 1/8 coincide exactamente con un 1/16 par, hasta el último.
        for (index, offset) in eighths.enumerated() {
            XCTAssertEqual(offset, sixteenths[index * 2], "ciclo \(index): deriva")
        }
    }

    /// Dos Tracks con longitudes distintas —16 y 12 Steps, un Pulse cada uno—
    /// disparan cada uno con su periodo y vuelven a coincidir en el mínimo común
    /// múltiplo, 48, sin deriva acumulada en diez vueltas.
    func testTracksOfDifferentLengthsRealignWithoutDrift() {
        var scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track(steps: 16, pulses: 1),
                1: track(steps: 12, pulses: 1),
            ])
        )

        var offsets: [Int: [Int64]] = [0: [], 1: []]
        scheduler.advance(toHorizon: 480 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, _, _, offset in
            offsets[track]?.append(offset)
        }

        // Cada uno dispara con su propio periodo, exacto hasta el último ciclo.
        XCTAssertEqual(offsets[0]!.count, 30, "16 Steps en 480")
        XCTAssertEqual(offsets[1]!.count, 40, "12 Steps en 480")
        for (cycle, offset) in offsets[0]!.enumerated() {
            XCTAssertEqual(offset, Int64(cycle * 16) * stepNanoseconds, "deriva en el Track 1")
        }
        for (cycle, offset) in offsets[1]!.enumerated() {
            XCTAssertEqual(offset, Int64(cycle * 12) * stepNanoseconds, "deriva en el Track 2")
        }

        // Y coinciden exactamente cada 48 Steps: 480 / 48 = 10 veces.
        let together = Set(offsets[0]!).intersection(Set(offsets[1]!))
        XCTAssertEqual(together.count, 10, "no vuelven a coincidir donde deben")
        XCTAssertTrue(together.allSatisfy { $0 % (48 * stepNanoseconds) == 0 })
    }

    /// **El Timing y el Delay de un Track no desplazan a los otros.** Es la
    /// independencia que hace que dieciséis voces no se contaminen.
    func testTimingAndDelayOfOneTrackDoNotMoveTheOthers() {
        let plain = track(steps: 8, pulses: 8)
        let shifted = Cycle(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(8)!),
            pool: PitchPool().inserting(Pitch(60)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: Timing(percent: 75)!,
                delay: Delay(percent: 50)!
            )
        )

        var alone = PatternScheduler(tempo: tempo, pattern: pattern([0: plain]))
        var withNeighbour = PatternScheduler(
            tempo: tempo, pattern: pattern([0: plain, 1: shifted]))

        XCTAssertEqual(
            offsets(of: &alone, track: 0, upToStep: 8),
            offsets(of: &withNeighbour, track: 0, upToStep: 8),
            "el vecino con Timing y Delay movió al Track 1"
        )
    }

    /// **Cada Track recorre su propia longitud.** El índice de Step que se emite
    /// es absoluto —cuenta desde el arranque, no da la vuelta— así que la
    /// longitud del anillo se ve en *cuándo* dispara cada uno: uno de cada
    /// cuatro Steps contra uno de cada tres.
    func testEachTrackWalksItsOwnLength() {
        var scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track(steps: 4, pulses: 1),
                1: track(steps: 3, pulses: 1),
            ])
        )

        var steps: [Int: [Int]] = [0: [], 1: []]
        scheduler.advance(toHorizon: 12 * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, _, _, _ in
            steps[track]?.append(step)
        }

        XCTAssertEqual(steps[0], [0, 4, 8], "el anillo de cuatro")
        XCTAssertEqual(steps[1], [0, 3, 6, 9], "el anillo de tres")
    }

    // MARK: - Dieciséis generadores

    /// Misma semilla, misma secuencia: pulsar Play dos veces reproduce las
    /// mismas omisiones. Es la promesa de `tech-stack.md`, ahora sobre dieciséis
    /// Tracks a la vez.
    func testTheSameSeedReproducesTheSameOmissions() {
        var first = PatternScheduler(tempo: tempo, pattern: halved(), seed: 12_345)
        var second = PatternScheduler(tempo: tempo, pattern: halved(), seed: 12_345)

        let a = fired(&first, upToStep: 64).map { [$0.track, $0.step] }
        let b = fired(&second, upToStep: 64).map { [$0.track, $0.step] }
        XCTAssertEqual(a, b)
    }

    /// **Dos Tracks con la misma Probability no omiten los mismos Pulses.** Con
    /// un generador compartido —o con la misma semilla— el aleatorio se oiría
    /// como una sola decisión repetida dieciséis veces en vez de como dieciséis
    /// voces independientes.
    func testTwoTracksWithTheSameProbabilityDoNotOmitTheSamePulses() {
        var scheduler = PatternScheduler(tempo: tempo, pattern: halved())
        let events = fired(&scheduler, upToStep: 256)

        let first = Set(events.filter { $0.track == 0 }.map(\.step))
        let second = Set(events.filter { $0.track == 1 }.map(\.step))

        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second, "los dos Tracks omitieron exactamente lo mismo")
    }

    /// Y ningún par de los dieciséis coincide: no es que el 1 y el 2 difieran
    /// por suerte, es que las dieciséis secuencias son distintas.
    func testTheSixteenSequencesAreAllDifferent() {
        var full: [Int: Cycle] = [:]
        for index in 0..<16 { full[index] = halfProbabilityTrack() }

        var scheduler = PatternScheduler(tempo: tempo, pattern: pattern(full))
        let events = fired(&scheduler, upToStep: 256)

        var sequences: [Set<Int>] = []
        for index in 0..<16 {
            sequences.append(Set(events.filter { $0.track == index }.map(\.step)))
        }
        for a in 0..<16 {
            for b in (a + 1)..<16 {
                XCTAssertNotEqual(sequences[a], sequences[b], "Tracks \(a + 1) y \(b + 1)")
            }
        }
    }

    /// **El estado del aleatorio no entra en el snapshot.** Tiene estado mutable
    /// y vive en el scheduler, que es su único dueño; meterlo en el Pattern
    /// rompería la trivialidad y haría que dos hilos mutaran lo mismo.
    func testTheRandomStateStaysOutOfTheSnapshot() {
        XCTAssertTrue(_isPOD(Pattern.self))
        XCTAssertTrue(_isPOD(Cycle.self))
    }

    /// Las semillas derivadas no se pisan entre Tracks contiguos.
    func testDerivedSeedsAreAllDistinct() {
        let seeds = (0..<16).map { PatternScheduler.seed(0, forTrack: $0) }
        XCTAssertEqual(Set(seeds).count, 16)
    }

    // MARK: - El relevo de snapshot

    /// El Pattern publicado se recoge una vez por ventana y lo ven todos los
    /// Tracks: leerlo dieciséis veces dejaría que dos Tracks tocaran material de
    /// publicaciones distintas.
    func testThePublishedPatternIsPickedUpByEveryTrack() {
        var scheduler = PatternScheduler(tempo: tempo, pattern: Pattern())
        let handoff = PatternHandoff(Pattern())

        var updated: [Int: Cycle] = [:]
        for index in 0..<16 { updated[index] = track(steps: 4, pulses: 4, pitch: 60) }
        handoff.publish(pattern(updated))

        let events = emit(&scheduler, upToStep: 4, from: handoff)
        XCTAssertEqual(events.count, 16 * 4)
    }

    // MARK: - Helpers

    /// Un Track que dispara en todos los Steps con Probability al 50%: la mitad
    /// de los Pulses se omite, y cuáles lo decide el generador.
    private func halfProbabilityTrack() -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().inserting(Pitch(60)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: Probability(percent: 50)!
            )
        )
    }

    /// Dos Tracks idénticos con Probability al 50%, para que lo único que pueda
    /// diferenciarlos sea el generador.
    private func halved() -> Pattern {
        pattern([0: halfProbabilityTrack(), 1: halfProbabilityTrack()])
    }

    private func fired(
        _ scheduler: inout PatternScheduler, upToStep stepIndex: Int
    ) -> [(track: Int, step: Int)] {
        var events: [(track: Int, step: Int)] = []
        scheduler.advance(toHorizon: Int64(stepIndex) * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, _, _, _ in
            events.append((track, step))
        }
        return events
    }

    private func offsets(
        of scheduler: inout PatternScheduler, track wanted: Int, upToStep stepIndex: Int
    ) -> [Int64] {
        var found: [Int64] = []
        scheduler.advance(toHorizon: Int64(stepIndex) * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, _, _, offset in
            if track == wanted { found.append(offset) }
        }
        return found
    }

    private func timeline(_ division: Division) -> MusicalTimeline {
        MusicalTimeline(tempo: tempo, division: division)
    }
}
