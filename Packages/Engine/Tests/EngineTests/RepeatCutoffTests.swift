import XCTest

@testable import Engine

/// Tests del límite de la tirada de repeticiones.
///
/// **El corte lo pone el Pulse siguiente, y en su defecto el cierre de la
/// vuelta** (FR9). Una repetición se emite si su instante cae **estrictamente
/// antes** del límite.
///
/// **Se mide contra el instante de emisión, no contra la rejilla recta.** Con
/// swing, medir contra la rejilla cortaría de más o de menos según el paso.
///
/// **El límite no cruza la vuelta.** Qué Cycle viene después lo decide el hilo
/// del scheduler al cerrar, y mirar dentro rompería que el Cycle nuevo entre
/// limpio en su primer Step.
///
/// Los números son a 120 BPM con Division 1/16: un Step de 125 ms.
final class RepeatCutoffTests: XCTestCase {

    private let step: Int64 = 125_000_000

    /// 16/4 reparte en 0, 4, 8 y 12 — cuatro huecos iguales.
    private func fourOnTheFloor(_ groove: Groove = .default) -> Cycle {
        Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!), groove: groove)
    }

    /// 16/5 reparte en 0, 3, 6, 9 y 12: «x..x..x..x..x...» de la Pre Spec. El 3
    /// y el 9 son impares, que es donde el swing se ve.
    private func fiveOnSixteen(_ groove: Groove = .default) -> Cycle {
        Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!), groove: groove)
    }

    private func groove(timing: Int = 50, delay: Int = 0) -> Groove {
        Groove(
            velocity: .default,
            sustain: .default,
            probability: .default,
            timing: Timing(percent: timing)!,
            delay: Delay(percent: delay)!
        )
    }

    // MARK: - El Pulse siguiente

    /// Con la rejilla recta, el límite es la distancia al Pulse siguiente.
    func testTheLimitIsTheDistanceToTheNextPulse() {
        let cycle = fourOnTheFloor()

        XCTAssertEqual(
            cycle.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step), step * 4)
        XCTAssertEqual(
            cycle.repeatWindowNanoseconds(fromStep: 4, stepDurationNanoseconds: step), step * 4)
    }

    /// **Las repeticiones cruzan los Steps vacíos del reparto.** Es lo que hace
    /// funcionar un roll largo sobre un ritmo disperso: entre el Pulse 0 y el 4
    /// hay tres Steps sin disparo y la ventana los abarca enteros.
    func testTheWindowCrossesTheEmptySteps() {
        let cycle = fourOnTheFloor()
        for empty in 1...3 {
            XCTAssertFalse(cycle.triggers(atStep: empty), "el Step \(empty) no debería disparar")
        }
        XCTAssertGreaterThan(
            cycle.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step), step * 3)
    }

    /// Un reparto disperso da ventanas largas: 16/1 deja una vuelta entera.
    func testASparseRhythmGivesAWholeTurn() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!))
        XCTAssertEqual(
            cycle.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step), step * 16)
    }

    // MARK: - El cierre de la vuelta

    /// **Sin más Pulses por delante, el límite es el cierre de la vuelta**, y no
    /// el primer Pulse de la vuelta siguiente.
    func testWithoutAFurtherPulseTheLimitIsTheTurnClose() {
        let cycle = fourOnTheFloor()

        // Desde el último Pulse (12) quedan cuatro Steps hasta cerrar.
        XCTAssertEqual(
            cycle.repeatWindowNanoseconds(fromStep: 12, stepDurationNanoseconds: step), step * 4)
    }

    /// Y con la vuelta acabando justo detrás del Pulse, la ventana es de un
    /// Step: 16/16 dispara en todos.
    func testTheLastPulseOfADenseRhythmGetsOneStep() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!))
        XCTAssertEqual(
            cycle.repeatWindowNanoseconds(fromStep: 15, stepDurationNanoseconds: step), step)
    }

    /// **Cada Cycle cierra con su propia longitud.** Un anillo de 12 Steps mide
    /// su vuelta en 12 y no en 16.
    func testTheTurnCloseUsesTheCyclesOwnLength() {
        let twelve = Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(1)!))
        XCTAssertEqual(
            twelve.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step), step * 12)
    }

    // MARK: - El instante de emisión, no la rejilla

    /// **Con swing, el límite se mide contra el Pulse ya desplazado.** En 16/5 el
    /// Pulse siguiente al 0 es el 3, que es impar y cae tarde: la ventana se
    /// alarga exactamente lo que el swing lo aparta.
    func testSwingOnTheNextPulseStretchesTheWindow() {
        let swung = fiveOnSixteen(groove(timing: 66))
        let straight = fiveOnSixteen()

        let shift = swung.groove.shiftNanoseconds(atStep: 3, stepDurationNanoseconds: step)
        XCTAssertGreaterThan(shift, 0)
        XCTAssertEqual(
            swung.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step),
            straight.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step) + shift
        )
    }

    /// Y al revés: cuando el swing desplaza el Pulse **de partida**, la ventana
    /// se acorta en la misma cantidad.
    func testSwingOnTheStartingPulseShrinksTheWindow() {
        let swung = fiveOnSixteen(groove(timing: 66))
        let straight = fiveOnSixteen()

        let shift = swung.groove.shiftNanoseconds(atStep: 3, stepDurationNanoseconds: step)
        XCTAssertEqual(
            swung.repeatWindowNanoseconds(fromStep: 3, stepDurationNanoseconds: step),
            straight.repeatWindowNanoseconds(fromStep: 3, stepDurationNanoseconds: step) - shift
        )
    }

    /// **Delay no mueve el límite**, porque desplaza a los dos Pulses por igual:
    /// la tirada viaja con el Pulse.
    func testDelayDoesNotMoveTheLimit() {
        let straight = fourOnTheFloor().repeatWindowNanoseconds(
            fromStep: 0, stepDurationNanoseconds: step)

        for percent in [-100, -40, 40, 100] {
            let delayed = fourOnTheFloor(groove(delay: percent))
            XCTAssertEqual(
                delayed.repeatWindowNanoseconds(fromStep: 0, stepDurationNanoseconds: step),
                straight,
                "delay \(percent)%"
            )
        }
    }

    // MARK: - Nunca mira la vuelta siguiente

    /// **El límite no cruza la vuelta**, ni siquiera cuando el primer Step de la
    /// siguiente dispara: desde el último Pulse la ventana llega al cierre y no
    /// más allá.
    func testTheLimitNeverReachesIntoTheNextTurn() {
        let cycle = fourOnTheFloor()
        XCTAssertTrue(cycle.triggers(atStep: 0), "el Step 0 dispara, y aun así no cuenta")

        let window = cycle.repeatWindowNanoseconds(fromStep: 12, stepDurationNanoseconds: step)
        XCTAssertEqual(window, step * 4)
        XCTAssertLessThanOrEqual(window, step * 16)
    }

    /// Y con swing tampoco: el cierre de la vuelta es rejilla, no instante de
    /// emisión — el Cycle siguiente arranca donde su primer Step diga.
    func testTheTurnCloseIsGridAndNotAShiftedInstant() {
        let swung = fourOnTheFloor(groove(timing: 75))
        XCTAssertEqual(
            swung.repeatWindowNanoseconds(fromStep: 12, stepDurationNanoseconds: step), step * 4)
    }

    // MARK: - Un Step que no dispara

    /// Preguntar por un Step que no es Pulse devuelve 0: no hay tirada que
    /// acotar. Es un estado que el scheduler no produce —solo pregunta sobre
    /// Pulses— y devolver 0 lo deja inofensivo si alguna vez lo produce.
    func testAStepThatDoesNotTriggerHasNoWindow() {
        XCTAssertEqual(
            fourOnTheFloor().repeatWindowNanoseconds(fromStep: 1, stepDurationNanoseconds: step), 0)
    }
}
