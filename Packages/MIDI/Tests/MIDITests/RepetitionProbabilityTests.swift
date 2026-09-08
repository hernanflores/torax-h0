import Engine
import XCTest

@testable import MIDI

/// Tests de Probability sobre todas las notas (FR13).
///
/// **Cada evento —el Pulse y cada repetición— consume una tirada**, en orden:
/// primero el Pulse, después las repeticiones.
///
/// **Un Pulse callado no se lleva sus repeticiones.** Son eventos
/// independientes: bajar Probability con Repeats altos perfora la textura en vez
/// de borrar tiradas enteras.
///
/// **Una repetición que el corte descarta no consume tirada.** El corte se
/// decide antes que la tirada, con el mismo criterio que ya separa «primero
/// dispara, después decide si suena»: así girar Time o Pace no desplaza las
/// omisiones de un patrón que nadie tocó.
final class RepetitionProbabilityTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000

    private func timeline() -> MusicalTimeline {
        MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
    }

    private func cycle(
        pulses: Int = 8,
        repeats: Int = 0,
        time: RepeatTime = .default,
        probability: Int = 50,
        pool: PitchPool = PitchPool().inserting(Pitch(48)!)
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: pool,
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: Probability(percent: probability)!
            ),
            noteRepeater: NoteRepeater(repeats: Repeats(repeats)!, time: time)
        )
    }

    private func run(
        _ cycle: Cycle,
        seed: UInt64 = 7,
        steps: Int = 64
    ) -> (pulses: [Int], repetitions: [Int]) {
        var scheduler = TrackScheduler(
            timeline: timeline(), material: .cycle(cycle), seed: seed)
        var pulses: [Int] = []
        var repetitions: [Int] = []

        scheduler.advance(
            toHorizon: Int64(steps) * stepNanoseconds,
            refreshingFrom: PatternHandoff?.none,
            emitRepetition: { _, step, _, _, _, _ in repetitions.append(step) },
            emit: { _, step, _, _, _ in pulses.append(step) }
        )
        return (pulses, repetitions)
    }

    // MARK: - FR16: con Repeats en 0 el consumo no cambia

    /// **La secuencia de omisiones de antes de la rebanada, capturada con
    /// semilla 7 y Probability al 50%.** Es la prueba de que Probability sobre
    /// todas las notas no es una regresión: con Repeats en 0 el consumo de
    /// aleatoriedad es idéntico, así que un Pattern hecho antes omite lo mismo.
    func testWithoutRepeatsTheOmissionsAreTheOnesFromBeforeTheSlice() {
        let reference = [0, 2, 6, 8, 10, 14, 18, 26, 30, 32, 34, 36, 42, 46, 50, 52, 56, 58, 62]

        XCTAssertEqual(run(cycle(repeats: 0)).pulses, reference)
    }

    /// Y pasar el cierre de repeticiones tampoco cambia nada con Repeats en 0:
    /// no hay evento nuevo que consuma tirada.
    func testWithoutRepeatsThePresenceOfTheRepetitionSinkChangesNothing() {
        var scheduler = TrackScheduler(
            timeline: timeline(), material: .cycle(cycle(repeats: 0)), seed: 7)
        var pulses: [Int] = []
        scheduler.advance(
            toHorizon: 64 * stepNanoseconds, refreshingFrom: PatternHandoff?.none
        ) { _, step, _, _, _ in pulses.append(step) }

        XCTAssertEqual(pulses, run(cycle(repeats: 0)).pulses)
    }

    // MARK: - Una tirada por evento

    /// Al 100% no se omite nada: salen todos los Pulses y todas las
    /// repeticiones que quepan.
    func testAtFullProbabilityEveryEventSounds() {
        let result = run(cycle(pulses: 4, repeats: 3, probability: 100), steps: 16)

        XCTAssertEqual(result.pulses.count, 4)
        XCTAssertEqual(result.repetitions.count, 12)
    }

    /// Al 0% no suena nada, tampoco las repeticiones: Probability decide sobre
    /// todas las notas.
    func testAtZeroProbabilityNothingSounds() {
        let result = run(cycle(pulses: 4, repeats: 3, probability: 0), steps: 16)

        XCTAssertTrue(result.pulses.isEmpty)
        XCTAssertTrue(result.repetitions.isEmpty)
    }

    /// Con Probability intermedia, unas repeticiones suenan y otras no: la
    /// textura se perfora en vez de encenderse y apagarse entera.
    func testProbabilityPerforatesTheBurst() {
        let result = run(cycle(pulses: 4, repeats: 8, probability: 50), steps: 16)

        XCTAssertGreaterThan(result.repetitions.count, 0)
        XCTAssertLessThan(result.repetitions.count, 32)
    }

    // MARK: - Un Pulse callado no se lleva sus repeticiones

    /// **Son eventos independientes.** Con la semilla fijada hay al menos un
    /// Step donde el Pulse se omite y sus repeticiones suenan.
    func testASilentPulseKeepsItsRepetitions() {
        let result = run(cycle(pulses: 8, repeats: 4, probability: 50), steps: 64)

        let silentPulseSteps = Set(result.repetitions).subtracting(result.pulses)
        XCTAssertFalse(
            silentPulseSteps.isEmpty,
            "ningún Pulse callado conservó repeticiones; el corte se las llevó con él")
    }

    // MARK: - El corte va antes que la tirada

    /// **Una repetición que el corte descarta no consume tirada.** Con Time 1/8
    /// sobre 16/4 solo cabe una repetición, así que pedir 8 y pedir 1 tienen que
    /// producir exactamente la misma secuencia: si las descartadas tirasen, la
    /// de 8 desplazaría todas las omisiones siguientes.
    func testARepetitionCutByTheLimitDoesNotDraw() {
        let one = run(cycle(pulses: 4, repeats: 1, time: RepeatTime.ordered.first!), steps: 64)
        let eight = run(cycle(pulses: 4, repeats: 8, time: RepeatTime.ordered.first!), steps: 64)

        XCTAssertEqual(one.pulses, eight.pulses)
        XCTAssertEqual(one.repetitions, eight.repetitions)
    }

    // MARK: - Reproducible

    /// Misma semilla, misma secuencia. Es la promesa de `tech-stack.md`: pulsar
    /// Play dos veces reproduce las mismas omisiones.
    func testTheSameSeedGivesTheSameSequence() {
        let first = run(cycle(pulses: 8, repeats: 3), seed: 42)
        let second = run(cycle(pulses: 8, repeats: 3), seed: 42)

        XCTAssertEqual(first.pulses, second.pulses)
        XCTAssertEqual(first.repetitions, second.repetitions)
    }

    /// Y dos semillas distintas no omiten lo mismo.
    func testTwoSeedsDoNotOmitTheSame() {
        let first = run(cycle(pulses: 8, repeats: 3), seed: 1)
        let second = run(cycle(pulses: 8, repeats: 3), seed: 2)

        XCTAssertNotEqual(first.repetitions, second.repetitions)
    }
}
