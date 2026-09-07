import Engine
import XCTest

@testable import MIDI

/// Tests de la tirada: qué repeticiones salen del `TrackScheduler` y dónde caen.
///
/// **Las repeticiones salen por un cierre propio y el Pulse por el de siempre.**
/// No es duplicar el camino: los dos acaban en la misma
/// `NoteEmitter.emit(pitch:velocity:gateNanoseconds:…)`. Lo que hace la
/// separación es que **el camino del Pulse quede intacto**, que es la forma más
/// fuerte de cumplir FR16 — con Repeats en 0 no hay nada nuevo ni siquiera en la
/// firma por la que sale.
///
/// Los números son a 120 BPM con Division 1/16: un Step de 125 ms.
final class RepetitionEmissionTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000

    private struct Repetition {
        let step: Int
        let velocity: Int
        let gateNanoseconds: Int64
        let offsetNanoseconds: Int64
    }

    private func timeline() -> MusicalTimeline {
        MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
    }

    /// Recorre una vuelta entera y recoge Pulses y repeticiones por separado.
    private func run(
        _ cycle: Cycle,
        steps: Int = 16
    ) -> (pulses: [Int], repetitions: [Repetition]) {
        var scheduler = TrackScheduler(timeline: timeline(), material: .cycle(cycle))
        var pulses: [Int] = []
        var repetitions: [Repetition] = []

        scheduler.advance(
            toHorizon: Int64(steps) * stepNanoseconds,
            refreshingFrom: PatternHandoff?.none,
            emitRepetition: { _, step, _, velocity, gate, offset in
                repetitions.append(
                    Repetition(
                        step: step, velocity: velocity.value, gateNanoseconds: gate,
                        offsetNanoseconds: offset))
            },
            emit: { _, step, _, _, _ in pulses.append(step) }
        )
        return (pulses, repetitions)
    }

    private func cycle(
        steps: Int = 16,
        pulses: Int = 4,
        repeats: Int = 0,
        time: RepeatTime = .default,
        ramp: Int = 0,
        pace: Int = 0,
        groove: Groove = .default,
        pool: PitchPool = PitchPool().inserting(Pitch(48)!)
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!),
            pool: pool,
            groove: groove,
            noteRepeater: NoteRepeater(
                repeats: Repeats(repeats)!,
                time: time,
                ramp: Ramp(percent: ramp)!,
                pace: Pace(percent: pace)!
            )
        )
    }

    private func groove(timing: Int = 50, delay: Int = 0, sustain: Int = 100, velocity: Int = 100)
        -> Groove
    {
        Groove(
            velocity: Velocity(velocity)!,
            sustain: Sustain(percent: sustain)!,
            probability: .default,
            timing: Timing(percent: timing)!,
            delay: Delay(percent: delay)!
        )
    }

    // MARK: - Cuántas y dónde

    /// **Con Repeats 3 y Time 1/32 sobre un Track en 1/16, cada Pulse entrega
    /// cuatro note-on**: el suyo en la rejilla y tres separados por un 1/32.
    func testEachPulseDeliversItsRepetitions() {
        let result = run(cycle(repeats: 3))

        XCTAssertEqual(result.pulses, [0, 4, 8, 12])
        XCTAssertEqual(result.repetitions.count, 12)

        let fromFirst = result.repetitions.filter { $0.step == 0 }
        XCTAssertEqual(
            fromFirst.map(\.offsetNanoseconds),
            [62_500_000, 125_000_000, 187_500_000]
        )
    }

    /// La primera repetición cae un hueco después del Pulse, no encima de él.
    func testTheFirstRepetitionFallsOneGapAfterThePulse() {
        let result = run(cycle(repeats: 1))
        XCTAssertEqual(result.repetitions.first?.offsetNanoseconds, 62_500_000)
    }

    // MARK: - FR16 y NFR3: con Repeats en 0 no pasa nada

    func testWithoutRepeatsNothingIsEmittedOnTheNewPath() {
        let result = run(cycle(repeats: 0))

        XCTAssertEqual(result.pulses, [0, 4, 8, 12])
        XCTAssertTrue(result.repetitions.isEmpty)
    }

    /// Y los Pulses caen donde caían: la tirada no toca sus instantes.
    func testThePulsesKeepTheirInstantsWithAndWithoutRepeats() {
        XCTAssertEqual(run(cycle(repeats: 0)).pulses, run(cycle(repeats: 8)).pulses)
    }

    // MARK: - FR10: la tirada viaja con el Pulse

    /// **La tirada arranca en el Pulse ya desplazado** por Timing y Delay, y
    /// ninguna repetición recibe swing propio: los huecos son todos iguales con
    /// Pace 0, también sobre un Pulse impar.
    func testTheBurstStartsAtTheShiftedPulse() {
        let swung = cycle(pulses: 5, repeats: 2, groove: groove(timing: 66))
        let result = run(swung)

        let shift = swung.groove.shiftNanoseconds(
            atStep: 3, stepDurationNanoseconds: stepNanoseconds)
        XCTAssertGreaterThan(shift, 0)

        let fromThird = result.repetitions.filter { $0.step == 3 }.map(\.offsetNanoseconds)
        let pulseInstant = 3 * stepNanoseconds + shift
        XCTAssertEqual(
            fromThird, [pulseInstant + 62_500_000, pulseInstant + 125_000_000])
    }

    /// Delay desplaza la tirada entera con su Pulse, sin cambiar los huecos.
    func testDelayMovesTheWholeBurst() {
        let straight = run(cycle(repeats: 2)).repetitions.map(\.offsetNanoseconds)
        let delayed = run(cycle(repeats: 2, groove: groove(delay: 40))).repetitions
            .map(\.offsetNanoseconds)

        let shift = stepNanoseconds * 40 / 100
        XCTAssertEqual(delayed, straight.map { $0 + shift })
    }

    // MARK: - FR9: el corte

    /// **Con Repeats 8 y Time 1/8 en un Track en 1/16, solo se emiten las que
    /// caben antes del Pulse siguiente.** Un hueco de 1/8 son dos Steps, y entre
    /// dos Pulses de 16/4 hay cuatro: caben una.
    func testOnlyTheRepetitionsThatFitAreEmitted() {
        let result = run(cycle(repeats: 8, time: RepeatTime.ordered.first!))

        XCTAssertEqual(result.repetitions.filter { $0.step == 0 }.count, 1)
    }

    /// Y ninguna cae en el Pulse siguiente o después: el corte es estricto.
    func testNoRepetitionReachesTheNextPulse() {
        let result = run(cycle(repeats: 8, time: RepeatTime.ordered[2]))

        for repetition in result.repetitions where repetition.step == 0 {
            XCTAssertLessThan(repetition.offsetNanoseconds, 4 * stepNanoseconds)
        }
    }

    /// Las repeticiones **cruzan los Steps vacíos** del reparto: con 16/1 y
    /// Repeats 8 salen las ocho, que abarcan más de un Step.
    func testRepetitionsCrossTheEmptySteps() {
        let result = run(cycle(pulses: 1, repeats: 8))

        XCTAssertEqual(result.repetitions.count, 8)
        XCTAssertGreaterThan(result.repetitions.last!.offsetNanoseconds, stepNanoseconds)
    }

    // MARK: - FR11: la altura y el pool

    /// **Todas las repeticiones suenan a la altura del Pulse**, y el recorrido
    /// del pool no se acelera: dos Pulses seguidos con Repeats altos siguen
    /// avanzando el pool de uno en uno.
    func testTheRepetitionsShareThePulsePitchAndDoNotAdvanceThePool() {
        let pool = PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!)
        var scheduler = TrackScheduler(
            timeline: timeline(), material: .cycle(cycle(repeats: 3, pool: pool)))

        var pulsePitches: [Int] = []
        var repetitionPitches: [Int: [Int]] = [:]

        scheduler.advance(
            toHorizon: 16 * stepNanoseconds,
            refreshingFrom: PatternHandoff?.none,
            emitRepetition: { _, step, pitch, _, _, _ in
                repetitionPitches[step, default: []].append(pitch!.value)
            },
            emit: { _, _, pitch, _, _ in pulsePitches.append(pitch!.value) }
        )

        // El pool avanza un paso por Pulse, no uno por evento.
        XCTAssertEqual(pulsePitches, [48, 55, 48, 55])
        XCTAssertEqual(repetitionPitches[0], [48, 48, 48])
        XCTAssertEqual(repetitionPitches[4], [55, 55, 55])
    }

    // MARK: - Ramp y el gate

    /// La velocity de cada repetición sale de la rampa, y el Pulse no participa.
    func testTheRampWritesTheRepetitionVelocities() {
        let result = run(cycle(repeats: 4, ramp: 100, groove: groove(velocity: 100)))

        XCTAssertEqual(
            result.repetitions.filter { $0.step == 0 }.map(\.velocity), [106, 113, 120, 127])
    }

    /// El gate de cada repetición se mide sobre su hueco, no sobre el Step.
    func testTheGateIsMeasuredOverTheGap() {
        let result = run(cycle(repeats: 2, groove: groove(sustain: 100)))

        for repetition in result.repetitions {
            XCTAssertEqual(repetition.gateNanoseconds, 62_500_000)
        }
    }

    /// Con Pace, cada repetición dura lo suyo.
    func testWithPaceEachRepetitionCarriesItsOwnGate() {
        let result = run(cycle(pulses: 1, repeats: 4, pace: 100, groove: groove(sustain: 100)))
        let gates = result.repetitions.map(\.gateNanoseconds)

        XCTAssertEqual(gates.count, 4)
        XCTAssertTrue(zip(gates, gates.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: - El arnés

    /// El arnés declara el `NoteRepeater` neutro, junto a su `Groove` por
    /// defecto: mide la rejilla temporal, no el material musical (FR14).
    func testTheHarnessDeclaresTheNeutralRepeater() {
        XCTAssertEqual(SchedulerMaterial.everyStep.noteRepeater, NoteRepeater.default)
    }

    /// Y un Cycle declara el suyo.
    func testACycleDeclaresItsOwnRepeater() {
        let ratcheted = cycle(repeats: 5)
        XCTAssertEqual(
            SchedulerMaterial.cycle(ratcheted).noteRepeater, ratcheted.noteRepeater)
    }

    /// El arnés de medición no repite: mide la rejilla temporal, no el material.
    func testTheMeasurementHarnessDoesNotRepeat() {
        var scheduler = TrackScheduler(timeline: timeline(), material: .everyStep)
        var repetitions = 0
        var pulses = 0

        scheduler.advance(
            toHorizon: 16 * stepNanoseconds,
            refreshingFrom: PatternHandoff?.none,
            emitRepetition: { _, _, _, _, _, _ in repetitions += 1 },
            emit: { _, _, _, _, _ in pulses += 1 }
        )

        XCTAssertEqual(pulses, 16)
        XCTAssertEqual(repetitions, 0)
    }
}
