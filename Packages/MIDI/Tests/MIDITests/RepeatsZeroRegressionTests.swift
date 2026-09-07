import Engine
import XCTest

@testable import MIDI

/// FR16 de punta a punta: **con Repeats en 0 la salida es la de antes de la
/// rebanada**.
///
/// No es una expectativa, es un requisito con test propio. El Pattern de abajo
/// junta lo que la rebanada podría haber roto: dos Tracks con Divisions y
/// longitudes de anillo distintas, swing en uno y Delay en el otro, Probability
/// por debajo del 100% en los dos, pools de dos alturas y canales distintos.
///
/// **La referencia se capturó ejecutando el código, no escribiéndola a mano.**
/// Lo que la hace válida como referencia de «antes de la rebanada» es que el
/// camino del Pulse no cambió: sale por el mismo cierre, con los mismos
/// argumentos, y consume una tirada por Pulse como siempre.
final class RepeatsZeroRegressionTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000

    private func grooves() -> [Groove] {
        [
            Groove(
                velocity: Velocity(100)!, sustain: Sustain(percent: 80)!,
                probability: Probability(percent: 70)!, timing: Timing(percent: 66)!,
                delay: Delay(percent: 0)!),
            Groove(
                velocity: Velocity(64)!, sustain: Sustain(percent: 120)!,
                probability: Probability(percent: 90)!, timing: Timing(percent: 50)!,
                delay: Delay(percent: 25)!),
        ]
    }

    /// Dos Tracks, cada uno con su anillo, su Groove, su pool y su canal.
    private func pattern(repeats: Int) -> Engine.Pattern {
        var pattern = Engine.Pattern()
        for index in 0..<2 {
            let cycle = Cycle(
                shape: Shape(
                    steps: Steps(index == 0 ? 16 : 12)!, pulses: Pulses(index == 0 ? 5 : 7)!),
                pool: PitchPool().inserting(Pitch(48 + index * 7)!).inserting(Pitch(55 + index)!),
                groove: grooves()[index],
                channel: Channel(index + 1)!,
                noteRepeater: NoteRepeater(repeats: Repeats(repeats)!)
            )
            pattern = pattern.replacing(Track(cycle), at: index)
        }
        return pattern
    }

    private func run(repeats: Int) -> (pulses: [String], repetitions: Int) {
        var scheduler = PatternScheduler(
            tempo: Tempo(beatsPerMinute: 120)!, pattern: pattern(repeats: repeats), seed: 11)
        var pulses: [String] = []
        var repetitions = 0

        scheduler.advance(
            toHorizon: 32 * stepNanoseconds,
            refreshingFrom: PatternHandoff?.none,
            emitRepetition: { _, _, _, _, _, _, _ in repetitions += 1 },
            emit: { track, _, step, pitch, groove, offset in
                pulses.append(
                    "\(track):\(step):\(pitch?.value ?? -1):\(groove.velocity.value):\(offset)")
            }
        )
        return (pulses, repetitions)
    }

    /// **La secuencia entera, instante a instante.** Si algo de la rebanada
    /// tocara los Pulses —el orden de las tiradas, el desplazamiento de Groove,
    /// el reparto— esta lista dejaría de cuadrar.
    func testWithRepeatsZeroTheOutputIsTheReference() {
        let reference = [
            "0:0:48:100:0", "0:3:55:100:415000000", "0:6:48:100:750000000",
            "0:9:55:100:1165000000", "0:22:48:100:2750000000", "0:28:48:100:3500000000",
            "1:0:55:64:31250000", "1:2:56:64:281250000", "1:3:55:64:406250000",
            "1:5:56:64:656250000", "1:7:55:64:906250000", "1:8:56:64:1031250000",
        ]

        let result = run(repeats: 0)

        XCTAssertEqual(result.pulses.count, 24)
        XCTAssertEqual(Array(result.pulses.prefix(12)), reference)
        XCTAssertEqual(
            Array(result.pulses.suffix(4)),
            [
                "1:26:56:64:3281250000", "1:27:55:64:3406250000",
                "1:29:56:64:3656250000", "1:31:55:64:3906250000",
            ]
        )
    }

    /// Y no se emite ni una repetición: el camino nuevo no se ejecuta.
    func testWithRepeatsZeroNoRepetitionIsEmitted() {
        XCTAssertEqual(run(repeats: 0).repetitions, 0)
    }

    /// Con Repeats por encima de 0 sí llegan, y llegan **a través del
    /// `PatternScheduler`**: la tirada cruza las tres capas hasta la salida.
    func testWithRepeatsTheBurstReachesThePatternScheduler() {
        XCTAssertGreaterThan(run(repeats: 4).repetitions, 0)
    }

    /// **Los Pulses no se mueven al añadir repeticiones** — salvo por las
    /// tiradas que las repeticiones consumen, que es FR13 y no una regresión.
    /// Con Probability al 100% los dos conjuntos coinciden exactamente.
    func testAtFullProbabilityThePulsesAreIdenticalWithAndWithoutRepeats() {
        func run(repeats: Int) -> [String] {
            var pattern = Engine.Pattern()
            let cycle = Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
                pool: PitchPool().inserting(Pitch(48)!),
                groove: Groove(
                    velocity: Velocity(90)!, sustain: Sustain(percent: 90)!,
                    probability: .default, timing: Timing(percent: 66)!,
                    delay: Delay(percent: -20)!),
                noteRepeater: NoteRepeater(repeats: Repeats(repeats)!)
            )
            pattern = pattern.replacing(Track(cycle), at: 0)

            var scheduler = PatternScheduler(
                tempo: Tempo(beatsPerMinute: 120)!, pattern: pattern, seed: 3)
            var pulses: [String] = []
            scheduler.advance(
                toHorizon: 32 * stepNanoseconds, refreshingFrom: PatternHandoff?.none
            ) { track, _, step, pitch, groove, offset in
                pulses.append(
                    "\(track):\(step):\(pitch?.value ?? -1):\(groove.velocity.value):\(offset)")
            }
            return pulses
        }

        XCTAssertEqual(run(repeats: 0), run(repeats: 6))
    }
}
