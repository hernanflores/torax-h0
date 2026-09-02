import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del avance de Cycle en el límite de vuelta.
///
/// **Es la fase que hace que Cycles se oiga**, y la que toca el hilo de tiempo
/// real. Se testea sobre `PatternScheduler` y no sobre `SchedulerThread` por la
/// misma razón que el resto del scheduling: aquí el horizonte se da a mano, así
/// que «la vuelta siguiente» es un hecho comprobable y no una carrera contra el
/// reloj.
final class CycleAdvanceTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private let stepNanoseconds: Int64 = 125_000_000

    /// Un Cycle que dispara en todos sus Steps, reconocible por su altura.
    ///
    /// La altura es lo que identifica al Cycle en lo emitido: es el dato que
    /// llega hasta el emisor, así que un test que la mire está comprobando lo
    /// que de verdad sonaría.
    private func cycle(steps: Int = 16, pitch: Int, division: Division = .sixteenth) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(steps)!, pulses: Pulses(steps)!, division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Un Track con N Cycles activos, cada uno con su altura.
    private func track(_ pitches: [Int], steps: Int = 16, division: Division = .sixteenth)
        -> Track
    {
        var track = Track(cycle(steps: steps, pitch: pitches[0], division: division))
        track = track.withActiveCount(pitches.count)
        for (index, pitch) in pitches.enumerated() {
            track = track.replacing(
                cycle(steps: steps, pitch: pitch, division: division), at: index)
        }
        return track
    }

    private func pattern(_ tracks: [Int: Track]) -> Pattern {
        tracks.reduce(into: Pattern()) { $0 = $0.replacing($1.value, at: $1.key) }
    }

    /// Lo emitido por un Track: el Step y la altura, que es quien delata el
    /// Cycle vigente.
    private func emitted(
        _ scheduler: PatternScheduler,
        upToStep stepIndex: Int,
        track wanted: Int = 0
    ) -> [(step: Int, pitch: Int?)] {
        var events: [(step: Int, pitch: Int?)] = []
        scheduler.advance(
            toHorizon: Int64(stepIndex) * stepNanoseconds,
            refreshingFrom: nil
        ) { track, _, step, pitch, _, _ in
            guard track == wanted else { return }
            events.append((step, pitch?.value))
        }
        return events
    }

    // MARK: - La vuelta propia

    /// **FR5 — el cambio ocurre en el Step 0 de la vuelta siguiente.** Se
    /// comprueba sobre el índice de Step y no de oído: un Track de 16 Steps con
    /// dos Cycles suena el primero en los Steps 0–15 y el segundo desde el 16.
    func testTheCycleChangesAtStepZeroOfTheNextTurn() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60])]))
        let events = emitted(scheduler, upToStep: 32)

        for event in events {
            let expected = (event.step / 16) % 2 == 0 ? 48 : 60
            XCTAssertEqual(event.pitch, expected, "Step \(event.step)")
        }
        XCTAssertEqual(events.count, 32, "faltan Steps")
    }

    /// Y vuelve al primero al cerrar la segunda vuelta: es un recorrido, no un
    /// cambio de una vez.
    func testTheTraversalWrapsBackToTheFirstCycle() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let events = emitted(scheduler, upToStep: 64)

        let byTurn = (0..<4).map { turn in events.filter { $0.step / 16 == turn }.map(\.pitch) }
        XCTAssertEqual(byTurn[0], Array(repeating: 48, count: 16))
        XCTAssertEqual(byTurn[1], Array(repeating: 60, count: 16))
        XCTAssertEqual(byTurn[2], Array(repeating: 72, count: 16))
        XCTAssertEqual(byTurn[3], Array(repeating: 48, count: 16), "no volvió al primero")
    }

    /// **FR4 — dos Tracks de longitudes distintas no cambian de Cycle a la vez.**
    /// Uno de 16 Steps cambia en el 16; uno de 12, en el 12. Ese desfase es la
    /// función, no un defecto.
    func testTwoTracksOfDifferentLengthsDoNotChangeCycleTogether() {
        let scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track([48, 60], steps: 16),
                1: track([36, 38], steps: 12),
            ])
        )

        var first: [(step: Int, pitch: Int?)] = []
        var second: [(step: Int, pitch: Int?)] = []
        scheduler.advance(toHorizon: 24 * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, pitch, _, _ in
            if track == 0 { first.append((step, pitch?.value)) }
            if track == 1 { second.append((step, pitch?.value)) }
        }

        XCTAssertEqual(first.first(where: { $0.pitch == 60 })?.step, 16)
        XCTAssertEqual(second.first(where: { $0.pitch == 38 })?.step, 12)
    }

    /// Con Divisions distintas cada uno avanza según **su** vuelta, no según el
    /// tiempo del otro: un Track en 1/8 cierra su anillo en el doble de tiempo
    /// que uno en 1/16, y su Cycle cambia ahí.
    func testWithDifferentDivisionsEachAdvancesOnItsOwnTurn() {
        let scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track([48, 60], division: .sixteenth),
                1: track([36, 38], division: .eighth),
            ])
        )

        var changedAt: [Int: Int64] = [:]
        scheduler.advance(toHorizon: 40 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, pitch, _, offset in
            let second = track == 0 ? 60 : 38
            if pitch?.value == second, changedAt[track] == nil { changedAt[track] = offset }
        }

        // El de 1/16 cierra su anillo de 16 Steps en 16 × 125 ms = 2 s; el de
        // 1/8, en 16 × 250 ms = 4 s. El segundo cambia al doble de tiempo.
        XCTAssertEqual(changedAt[0], 2_000_000_000)
        XCTAssertEqual(changedAt[1], 4_000_000_000)
    }

    // MARK: - Sin deriva

    /// **Mil vueltas, no dos compases.** Es como se ven los fallos de fase: un
    /// error de un Step por vuelta es inaudible al principio y evidente al cabo
    /// de un minuto.
    func testAThousandTurnsWithoutDrift() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let events = emitted(scheduler, upToStep: 16 * 1_000)

        XCTAssertEqual(events.count, 16_000)
        for event in events {
            let expected = [48, 60, 72][(event.step / 16) % 3]
            XCTAssertEqual(event.pitch, expected, "derivó en el Step \(event.step)")
        }
    }

    /// Y no depende de cómo se trocee el tiempo: pedir el mismo material en
    /// ventanas pequeñas da lo mismo que pedirlo de una vez. Sin esto, el avance
    /// podría estar contando ventanas en vez de vueltas.
    func testTheResultDoesNotDependOnHowTheHorizonIsChopped() {
        let whole = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let expected = emitted(whole, upToStep: 96)

        let chopped = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        var events: [(step: Int, pitch: Int?)] = []
        for window in 1...96 {
            chopped.advance(toHorizon: Int64(window) * stepNanoseconds, refreshingFrom: nil) {
                track, _, step, pitch, _, _ in
                guard track == 0 else { return }
                events.append((step, pitch?.value))
            }
        }

        XCTAssertEqual(events.map(\.pitch), expected.map(\.pitch))
    }

    // MARK: - No regresión

    /// **FR10 — con un Cycle activo no hay avance y nada cambia.** Es la
    /// condición de no regresión de la rebanada, comprobada donde importa: en lo
    /// que sale del scheduler.
    func testWithASingleActiveCycleNothingChanges() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48])]))
        let events = emitted(scheduler, upToStep: 64)

        XCTAssertEqual(events.count, 64)
        XCTAssertTrue(events.allSatisfy { $0.pitch == 48 }, "cambió algo con un solo Cycle")
    }

    /// Un Track sin Cycles que suenen no rompe el recorrido de los demás: el
    /// coste sigue creciendo con lo que suena (NFR3 de la rebanada 1).
    func testATrackWithNoMaterialDoesNotBreakTheOthers() {
        let silent = Track(
            Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
        ).withActiveCount(3)
        let scheduler = PatternScheduler(
            tempo: tempo, pattern: pattern([0: track([48, 60]), 3: silent]))

        var heard: [Int: Int] = [:]
        scheduler.advance(toHorizon: 32 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, _, _, _ in
            heard[track, default: 0] += 1
        }

        XCTAssertEqual(heard[0], 32)
        XCTAssertNil(heard[3], "un Track sin material emitió")
    }
}
