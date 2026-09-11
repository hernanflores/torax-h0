import Engine
import XCTest

@testable import MIDI

/// Tests de no regresión de Delay negativo tras un cambio de Division — Fase 4
/// de `division-hot-grid_20260911`, FR17.
///
/// **El presupuesto de adelanto se mide en Steps.** Con Delay negativo cada
/// Step se pide un trozo de Step antes de su rejilla, y `SchedulerThread`
/// reserva ese trozo una sola vez al arrancar, desplazando el origen. Al girar
/// Division el trozo cambia de tamaño: este track no rediseña ese origen, solo
/// comprueba que no se rompe, es decir, que **ningún evento se pida para un
/// instante que ya pasó**.
///
/// **El bucle del hilo se simula a mano**, con sus números: ventanas cada
/// 10 ms —la mitad del look-ahead, que es lo que duerme— y un horizonte 20 ms
/// por delante del presente. El presente se mide contra el origen desplazado,
/// como en `SchedulerThread`, así que un evento está en el pasado si su offset
/// es menor que el presente de la ventana que lo emite.
final class DelayBudgetDivisionTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let lookAhead = SchedulerConfiguration(
        timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
    ).lookAheadNanoseconds
    private var period: Int64 { lookAhead / 2 }

    private func cycle(division: Division, delay: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: .default, sustain: .default, probability: .default,
                timing: .default, delay: Delay(percent: delay)!)
        )
    }

    private struct Event {
        let step: Int
        let offset: Int64
        let now: Int64
    }

    /// Arranca en `before`, gira el knob a `after` a los `changeAt` de reloj y
    /// sigue hasta `until`, ventana a ventana como el hilo.
    private func run(
        delay: Int, from before: Division, to after: Division,
        changeAt: Int64 = 1_000_000_000, until: Int64 = 3_000_000_000
    ) -> (events: [Event], budgetAfter: Int64) {
        var scheduler = TrackScheduler(
            timeline: MusicalTimeline(tempo: tempo, division: before),
            material: .cycle(cycle(division: before, delay: delay)))
        scheduler.refresh(with: Track(cycle(division: before, delay: delay)))

        // El origen se desplaza con el presupuesto del arranque y ya no se
        // mueve, como en `SchedulerThread`.
        let startBudget = scheduler.advanceBudgetNanoseconds

        var events: [Event] = []
        var wall: Int64 = 0
        var changed = false
        while wall < until {
            if !changed, wall >= changeAt {
                scheduler.refresh(with: Track(cycle(division: after, delay: delay)))
                changed = true
            }
            let now = wall - startBudget
            scheduler.advance(toHorizon: now + lookAhead, refreshingFrom: nil) {
                _, step, _, _, offset in
                events.append(Event(step: step, offset: offset, now: now))
            }
            wall += period
        }
        return (events, scheduler.advanceBudgetNanoseconds)
    }

    private func assertNothingInThePast(
        _ events: [Event], _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(events.isEmpty, file: file, line: line)
        for event in events {
            XCTAssertGreaterThanOrEqual(
                event.offset, event.now,
                "\(message): el Step \(event.step) se pidió \(event.now - event.offset) ns tarde",
                file: file, line: line)
        }
        let steps = events.map(\.step)
        XCTAssertEqual(
            steps, Array(steps.first!...steps.last!), "\(message): un Step perdido o repetido",
            file: file, line: line)
    }

    /// Los instantes de giro que se prueban: uno por ventana a lo largo de un
    /// Step de 1/16 entero.
    ///
    /// **Un solo instante no basta, y fue el primer error de este test.** Lo que
    /// decide si el evento llega tarde es cuánto le faltaba al Step aún no
    /// entregado para entrar en la ventana cuando se gira el knob. Justo después
    /// de que un Step entre, al siguiente le falta casi un Step entero de
    /// margen y cualquier crecimiento del presupuesto cabe; justo antes, no le
    /// queda ninguno. Girar a los 1000 ms exactos caía en el primer caso y
    /// pasaba sin probar nada.
    private var changeInstants: [Int64] {
        stride(from: 1_000_000_000, to: 1_125_000_000, by: Int(period)).map { $0 }
    }

    // MARK: - Delay negativo (criterio 9)

    /// **Hacia más lento el presupuesto crece**: con Delay −100% pasa de 125 ms
    /// a 250 ms. Es el caso que puede pedir un evento para un instante ya
    /// entregado.
    func testANegativeDelayAsksForNoPastInstantWhenTheDivisionSlowsDown() {
        for delay in [-25, -50, -100] {
            for changeAt in changeInstants {
                let result = run(delay: delay, from: .sixteenth, to: .eighth, changeAt: changeAt)
                assertNothingInThePast(
                    result.events, "Delay \(delay)%, 1/16 → 1/8 a los \(changeAt) ns")
            }
        }
    }

    /// Hacia más rápido el presupuesto encoge, y lo que falta es no dejar un
    /// hueco que acabe en un evento tardío.
    func testANegativeDelayAsksForNoPastInstantWhenTheDivisionSpeedsUp() {
        for delay in [-25, -50, -100] {
            for changeAt in changeInstants {
                let result = run(
                    delay: delay, from: .sixteenth, to: .thirtySecond, changeAt: changeAt)
                assertNothingInThePast(
                    result.events, "Delay \(delay)%, 1/16 → 1/32 a los \(changeAt) ns")
            }
        }
    }

    // MARK: - Por la otra puerta: el avance de Cycle

    /// Un Track con dos Cycles —el 1 en 1/16 y el 2 en `second`— recorrido
    /// ventana a ventana desde Play, sin tocar nada. `phase` corre todas las
    /// ventanas a la vez, para que el cierre de vuelta caiga en distintos
    /// puntos de la suya.
    private func runCycles(
        first firstDelay: Int, second secondDelay: Int, secondDivision: Division,
        phase: Int64, until: Int64 = 5_000_000_000
    ) -> [Event] {
        let track = Track(cycle(division: .sixteenth, delay: firstDelay))
            .withActiveCount(2)
            .replacing(cycle(division: secondDivision, delay: secondDelay), at: 1)
        var scheduler = TrackScheduler(
            timeline: MusicalTimeline(tempo: tempo, division: .sixteenth),
            material: .cycle(track.cycle(at: 0)!))
        scheduler.refresh(with: track)
        let startBudget = scheduler.advanceBudgetNanoseconds

        // La primera ventana es la de Play, en el instante 0, como en el hilo;
        // la fase corre las siguientes. Arrancar ya desfasado pediría el Step 0
        // para un presente que el hilo nunca tiene, y el test fallaría por su
        // propio montaje.
        var events: [Event] = []
        var wall: Int64 = 0
        while wall < until {
            let now = wall - startBudget
            scheduler.advance(toHorizon: now + lookAhead, refreshingFrom: nil) {
                _, step, _, _, offset in
                events.append(Event(step: step, offset: offset, now: now))
            }
            wall = wall == 0 ? phase + period : wall + period
        }
        return events
    }

    private var phases: [Int64] { stride(from: 0, to: period, by: 2_500_000).map { $0 } }

    /// **El cierre de vuelta cae a mitad de ventana**, que es donde el rango ya
    /// está calculado con el presupuesto viejo. Con Delay −100% en los dos
    /// Cycles, pasar a 1/8 dobla el presupuesto dentro de la ventana.
    func testANegativeDelayAsksForNoPastInstantWhenTheNextCycleIsSlower() {
        for delay in [-50, -100] {
            for phase in phases {
                let events = runCycles(
                    first: delay, second: delay, secondDivision: .eighth, phase: phase)
                assertNothingInThePast(events, "Delay \(delay)%, Cycle 2 en 1/8, fase \(phase)")
            }
        }
    }

    /// **Y cuando el Cycle entrante adelanta menos que el que sale.** El Cycle
    /// 1 pide Delay −100% y el 2 ninguno: el Step del corte puede no caber ya
    /// en la ventana en curso. Tiene que esperar a la suya, no salir dos veces.
    func testACycleThatAdvancesLessNeitherRepeatsNorLosesTheCutStep() {
        for phase in phases {
            let events = runCycles(first: -100, second: 0, secondDivision: .eighth, phase: phase)
            assertNothingInThePast(events, "Cycle 1 a −100%, Cycle 2 a 0%, fase \(phase)")
        }
    }

    // MARK: - Delay ≥ 0: nada cambia

    /// **Con Delay ≥ 0 el presupuesto sigue siendo cero** después del cambio, y
    /// ningún evento se adelanta: es la mitad del rango donde vive el default.
    func testANonNegativeDelayKeepsAZeroBudgetAcrossTheChange() {
        for delay in [0, 25, 50, 100] {
            let result = run(delay: delay, from: .sixteenth, to: .eighth)

            XCTAssertEqual(result.budgetAfter, 0, "Delay \(delay)%")
            assertNothingInThePast(result.events, "Delay \(delay)%")
        }
    }
}
