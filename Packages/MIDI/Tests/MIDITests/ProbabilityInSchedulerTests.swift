import Engine
import XCTest

@testable import MIDI

/// Tests de la omisión en el camino de emisión.
///
/// **El generador vive en `TrackScheduler` y no en `Track`.** El snapshot tiene
/// que seguir siendo trivial —`_isPOD(Track.self)` lo vigila— y el generador
/// tiene estado mutable. `TrackScheduler` ya es un valor que solo el hilo del
/// scheduler muta, así que es su sitio.
final class ProbabilityInSchedulerTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000
    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private func track(probability: Int, pulses: Int = 16) -> Track {
        Track(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: pool(),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: Probability(percent: probability)!
            )
        )
    }

    private func pool() -> PitchPool {
        var pool = PitchPool()
        for value in [60, 64, 67] { pool = pool.toggling(Pitch(value)!) }
        return pool
    }

    /// Los Steps que sonaron durante `rounds` vueltas completas del anillo.
    private func sounded(
        _ track: Track,
        rounds: Int,
        seed: UInt64 = SeededRandom.defaultSeed
    ) -> [(step: Int, pitch: Pitch?)] {
        var scheduler = TrackScheduler(
            timeline: timeline,
            material: .track(track),
            seed: seed
        )
        var emitted: [(Int, Pitch?)] = []
        scheduler.advance(
            toHorizon: Int64(16 * rounds) * stepNanoseconds,
            refreshingFrom: nil
        ) { step, pitch, _, _ in emitted.append((step, pitch)) }
        return emitted
    }

    // MARK: - Los extremos

    func testFullProbabilitySoundsEveryPulse() {
        XCTAssertEqual(sounded(track(probability: 100), rounds: 1).count, 16)
    }

    /// **Un Pulse omitido no emite nada.** Ni note-on huérfano ni note-off
    /// suelto: no llega a la emisión.
    func testZeroProbabilityEmitsNothingAtAll() {
        XCTAssertTrue(sounded(track(probability: 0), rounds: 4).isEmpty)
    }

    // MARK: - La secuencia

    /// **Dos schedulers recién construidos omiten igual.** Es lo que hace que
    /// pulsar Play dos veces reproduzca la misma sesión.
    func testTwoFreshSchedulersSkipTheSamePulses() {
        let first = sounded(track(probability: 50), rounds: 4).map(\.step)
        let second = sounded(track(probability: 50), rounds: 4).map(\.step)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty, "el test no dice nada si no sonó nada")
    }

    /// **Dos vueltas consecutivas no omiten lo mismo.** Es la diferencia entre
    /// un patrón vivo y un patrón fijo con huecos fijos, y la razón de que el
    /// generador tenga estado en vez de indexarse por Step.
    func testConsecutiveRoundsSkipDifferentPulses() {
        let emitted = sounded(track(probability: 50), rounds: 8).map(\.step)

        // El índice de Step que entrega el scheduler es un contador absoluto y
        // creciente, no una posición envuelta en el anillo: la vuelta es el
        // cociente, y la posición dentro de ella el resto.
        var rounds: [Int: Set<Int>] = [:]
        for step in emitted {
            rounds[step / 16, default: []].insert(step % 16)
        }

        XCTAssertGreaterThan(rounds.count, 2, "no hubo vueltas suficientes que comparar")
        XCTAssertGreaterThan(
            Set(rounds.values).count, 1,
            "todas las vueltas omitieron exactamente lo mismo")
    }

    // MARK: - La altura no depende de la omisión

    /// **Omitir no descoloca el arpegio.** La altura de cada Step sale de su
    /// posición en el anillo, no de cuántos Pulses anteriores sonaron: bajar
    /// Probability perfora la línea, no la ralentiza.
    func testTheSamePitchLandsOnTheSameStepWhateverTheProbability() {
        let full = sounded(track(probability: 100), rounds: 1)
        let half = sounded(track(probability: 50), rounds: 1)

        XCTAssertFalse(half.isEmpty, "el test no dice nada si no sonó nada")
        for (step, pitch) in half {
            let expected = full.first { $0.step == step }?.pitch
            XCTAssertEqual(pitch, expected, "el Step \(step) cambió de altura al omitir otros")
        }
    }

    // MARK: - El arnés no pasa por Probability

    /// El arnés mide la rejilla temporal, no el material musical: un reparto
    /// euclidiano o una omisión solo le quitarían muestras al histograma.
    func testTheMeasurementHarnessNeverSkips() {
        var scheduler = TrackScheduler(timeline: timeline, material: .everyStep)
        var count = 0
        scheduler.advance(toHorizon: 64 * stepNanoseconds, refreshingFrom: nil) { _, _, _, _ in
            count += 1
        }
        XCTAssertEqual(count, 64)
    }
}
