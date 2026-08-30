import Engine
import XCTest

@testable import MIDI

/// Tests del desplazamiento temporal visto desde el scheduler.
///
/// Se testea sobre `TrackScheduler` y no sobre `SchedulerThread` por la misma
/// razón que el resto de `TrackSchedulerTests`: aquí el horizonte se le da a
/// mano, así que lo que se comprueba es un hecho y no una carrera contra el
/// reloj.
final class SchedulerShiftTests: XCTestCase {

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private let step: Int64 = 125_000_000

    private func track(timing: Int = 50, delay: Int = 0) -> Track {
        Track(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().toggling(Pitch(60)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: Timing(percent: timing)!,
                delay: Delay(percent: delay)!
            )
        )
    }

    /// Avanza una ventana y devuelve los pares (Step, offset emitido).
    private func emit(
        _ scheduler: inout TrackScheduler,
        toHorizon horizon: Int64,
        from handoff: TrackHandoff? = nil
    ) -> [(step: Int, offset: Int64)] {
        var emitted: [(step: Int, offset: Int64)] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) { step, _, _, offset in
            emitted.append((step, offset))
        }
        return emitted
    }

    // MARK: - La rejilla recta no se toca

    /// **La propiedad de la que depende la medición de regresión de la Fase 6.**
    /// Con el Groove default cada Step se emite en el offset que ya emitía antes
    /// de la rebanada 6 — el de `MusicalTimeline`, sin sumar ni restar nada.
    func testWithTheDefaultGrooveEveryStepKeepsItsGridOffset() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))

        for (step, offset) in emit(&scheduler, toHorizon: 8 * step) {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }

    /// El modo del arnés de medición tampoco se mueve: usa `Groove.default`, que
    /// es la rejilla recta.
    func testTheMeasurementModeStaysOnTheGrid() {
        var scheduler = TrackScheduler(timeline: timeline, material: .everyStep)

        for (step, offset) in emit(&scheduler, toHorizon: 8 * step) {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }

    // MARK: - El offset emitido lleva el desplazamiento

    func testTheEmittedOffsetIsTheGridPlusTheShift() {
        let swung = track(timing: 75, delay: 25)
        var scheduler = TrackScheduler(timeline: timeline, material: .track(swung))

        for (step, offset) in emit(&scheduler, toHorizon: 8 * self.step) {
            let expected =
                timeline.nanosecondOffset(forStep: step)
                + swung.groove.shiftNanoseconds(atStep: step, stepDurationNanoseconds: self.step)

            XCTAssertEqual(offset, expected, "el Step \(step) no llevó su desplazamiento")
        }
    }

    /// Al 75% los Steps impares caen medio Step tarde y los pares no se mueven:
    /// la rejilla emitida es no uniforme, que es lo que el swing significa.
    func testSwingProducesANonUniformEmittedGrid() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track(timing: 75)))
        let emitted = emit(&scheduler, toHorizon: 4 * step)

        XCTAssertEqual(emitted.map(\.offset), [0, step + step / 2, 2 * step, 3 * step + step / 2])
    }

    /// **Cada Step se sigue emitiendo exactamente una vez.** La invariante de
    /// `LookAheadScheduler` sobrevive al desplazamiento y a la ampliación del
    /// horizonte: los rangos siguen siendo contiguos y la marca de agua solo
    /// avanza.
    func testEveryStepIsStillEmittedExactlyOnceAcrossWindows() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(timing: 75, delay: -100)))

        var steps: [Int] = []
        for window in 1...8 {
            steps += emit(&scheduler, toHorizon: Int64(window) * 4 * step).map(\.step)
        }

        XCTAssertEqual(steps, Array(steps.sorted()), "los Steps salieron desordenados")
        XCTAssertEqual(steps.count, Set(steps).count, "algún Step se emitió dos veces")
    }

    // MARK: - El horizonte se amplía con el presupuesto

    /// **El caso que hace falta para que un evento adelantado no caiga en el
    /// pasado.** Con Delay −100% el Step tiene que calcularse un Step antes de
    /// su rejilla, así que entra en una ventana anterior a la que le tocaría.
    func testANegativeDelaySelectsStepsEarlier() {
        var straight = TrackScheduler(timeline: timeline, material: .track(track()))
        var advanced = TrackScheduler(timeline: timeline, material: .track(track(delay: -100)))

        let horizon = step / 2

        XCTAssertEqual(emit(&straight, toHorizon: horizon).map(\.step), [0])
        XCTAssertEqual(emit(&advanced, toHorizon: horizon).map(\.step), [0, 1])
    }

    /// **Con Delay ≥ 0 el horizonte es idéntico al de hoy.** Es la mitad del
    /// rango donde vive el default, y no puede pagar el coste de la otra mitad:
    /// ni look-ahead más largo ni respuesta de knob más lenta.
    func testANonNegativeDelaySelectsExactlyTheSameStepsAsBefore() {
        for percent in [0, 25, 50, 100] {
            var scheduler = TrackScheduler(
                timeline: timeline, material: .track(track(delay: percent)))

            XCTAssertEqual(
                emit(&scheduler, toHorizon: 4 * step).map(\.step),
                [0, 1, 2, 3],
                "Delay \(percent)% cambió qué Steps caen en la ventana"
            )
        }
    }

    /// El swing tampoco amplía el horizonte: solo atrasa, así que no necesita
    /// presupuesto.
    func testSwingDoesNotWidenTheHorizon() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track(timing: 75)))

        XCTAssertEqual(emit(&scheduler, toHorizon: 4 * step).map(\.step), [0, 1, 2, 3])
    }

    /// **El presupuesto se relee del snapshot, no se fija al construir.** Delay
    /// se puede girar mientras suena, y un presupuesto congelado dejaría de
    /// cubrir el adelanto en cuanto el knob se moviera.
    func testTheBudgetComesFromThePublishedSnapshotAndNotFromConstruction() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))
        let handoff = TrackHandoff(track())

        // Sin Delay: la ventana de medio Step solo alcanza al Step 0.
        XCTAssertEqual(emit(&scheduler, toHorizon: step / 2).map(\.step), [0])

        // Se publica un Delay negativo. La ventana siguiente llega justo al
        // borde del Step 1: sin presupuesto no emitiría nada —el horizonte es
        // exclusivo— y con él lo alcanza. Ese contraste es la señal.
        handoff.publish(track(delay: -100))
        XCTAssertEqual(
            emit(&scheduler, toHorizon: step, from: handoff).map(\.step),
            [1],
            "el presupuesto no se releyó del snapshot"
        )
    }

    /// La otra mitad del contraste anterior: sin Delay, esa misma ventana no
    /// alcanza al Step 1. Están separados para que el que falle diga cuál de las
    /// dos cosas se rompió.
    func testWithoutBudgetTheSameWindowReachesNothing() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))

        XCTAssertEqual(emit(&scheduler, toHorizon: step / 2).map(\.step), [0])
        XCTAssertEqual(emit(&scheduler, toHorizon: step).map(\.step), [])
    }

    /// El desplazamiento sale del **mismo** snapshot que la altura y el Groove:
    /// no son dos lecturas que puedan discrepar en el borde de una ventana.
    func testTheShiftComesFromTheSameSnapshotAsTheGroove() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))
        let handoff = TrackHandoff(track())
        handoff.publish(track(timing: 75, delay: 50))

        var seen: [(groove: Groove, offset: Int64, step: Int)] = []
        scheduler.advance(toHorizon: 4 * step, refreshingFrom: handoff) { step, _, groove, offset in
            seen.append((groove, offset, step))
        }

        XCTAssertFalse(seen.isEmpty)
        for entry in seen {
            let expected =
                timeline.nanosecondOffset(forStep: entry.step)
                + entry.groove.shiftNanoseconds(
                    atStep: entry.step, stepDurationNanoseconds: step)

            XCTAssertEqual(entry.offset, expected)
        }
    }
}
