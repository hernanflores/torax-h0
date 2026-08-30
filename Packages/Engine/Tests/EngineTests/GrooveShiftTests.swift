import XCTest

@testable import Engine

/// Tests del desplazamiento temporal — la aritmética donde vive la corrección de
/// la rebanada 6.
///
/// **Todo en enteros y en nanosegundos.** Esto acaba corriendo en el hilo del
/// scheduler, así que no hay coma flotante ni en la implementación ni en lo que
/// los tests comprueban.
///
/// La duración de Step de referencia es la de 1/16 a 120 BPM: 125 ms exactos, un
/// número redondo contra el que las fracciones se leen sin ruido de redondeo.
final class GrooveShiftTests: XCTestCase {

    /// 1/16 a 120 BPM = 125 ms. Elegido porque las fracciones que interesan
    /// —medio Step, un tercio, un Step entero— caen en números limpios.
    private let step: Int64 = 125_000_000

    private func groove(timing: Int = 50, delay: Int = 0) -> Groove {
        Groove(
            velocity: .default,
            sustain: .default,
            probability: .default,
            timing: Timing(percent: timing)!,
            delay: Delay(percent: delay)!
        )
    }

    // MARK: - La rejilla recta

    /// **El default no mueve nada, y esto es lo que lo fija.** Es la propiedad de
    /// la que depende que la medición de jitter recta de la Fase 6 siga midiendo
    /// la misma rejilla que midió la rebanada 3.
    func testTheDefaultGrooveShiftsNothing() {
        for index in -8...32 {
            XCTAssertEqual(
                Groove.default.shiftNanoseconds(atStep: index, stepDurationNanoseconds: step),
                0,
                "el Step \(index) se movió con el Groove default"
            )
        }
    }

    /// El desplazamiento es cero **contra `MusicalTimeline`**, no contra un cero
    /// escrito a mano: lo que se comprueba es que el instante de emisión sigue
    /// siendo el de la rejilla.
    func testWithTheDefaultGrooveEmissionLandsOnTheGrid() throws {
        let timeline = MusicalTimeline(
            tempo: try XCTUnwrap(Tempo(beatsPerMinute: 120)),
            division: .sixteenth
        )
        let duration = Int64(timeline.stepDurationNanoseconds)

        for index in 0...16 {
            let grid = timeline.nanosecondOffset(forStep: index)
            let shift = Groove.default.shiftNanoseconds(
                atStep: index, stepDurationNanoseconds: duration)

            XCTAssertEqual(grid + shift, grid)
        }
    }

    // MARK: - Timing

    /// Al 75% —el tope— el Step impar cae medio Step tarde. Es el
    /// desplazamiento máximo que el rango admite, y la razón del tope.
    func testTimingAtItsMaximumDelaysOddStepsByHalfAStep() {
        let swung = groove(timing: 75)

        XCTAssertEqual(swung.shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step), step / 2)
        XCTAssertEqual(swung.shiftNanoseconds(atStep: 3, stepDurationNanoseconds: step), step / 2)
    }

    /// **Los Steps pares no se mueven nunca por Timing**, en todo el rango. Es lo
    /// que hace que el swing sea una rejilla no uniforme y no un Delay con otro
    /// nombre.
    func testTimingNeverMovesEvenSteps() {
        for percent in Timing.validRange {
            let swung = groove(timing: percent)
            for index in stride(from: 0, through: 16, by: 2) {
                XCTAssertEqual(
                    swung.shiftNanoseconds(atStep: index, stepDurationNanoseconds: step),
                    0,
                    "Timing \(percent)% movió el Step par \(index)"
                )
            }
        }
    }

    /// **El tresillo, dentro de tolerancia declarada.** El 2:1 exacto es 66,67% y
    /// el knob va de uno en uno, así que ningún valor cae justo encima. Al 67% la
    /// separación es de 0,83 ms sobre un Step de 125 ms —un 0,67%—, por debajo de
    /// lo que distingue el oído. Ver la enmienda del 2026-08-30 en el plan.
    ///
    /// **La tolerancia es medio clic de knob**, que es la cota general y no un
    /// número ajustado a este caso: cada clic mueve un 2% de la duración del
    /// Step, así que el valor más cercano a cualquier objetivo se separa como
    /// mucho un 1%.
    func testTimingAtSixtySevenPercentIsATripletWithinTolerance() {
        let triplet = step / 3
        let shift = groove(timing: 67).shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step)

        let halfAKnobClick = step / 100
        XCTAssertEqual(shift, triplet, accuracy: halfAKnobClick)
    }

    /// El 66% queda al otro lado del tresillo, y a la misma distancia de clic:
    /// el knob lo cruza, no lo esquiva.
    func testTheTripletFallsBetweenTwoKnobPositions() {
        let triplet = step / 3
        let below = groove(timing: 66).shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step)
        let above = groove(timing: 67).shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step)

        XCTAssertLessThan(below, triplet)
        XCTAssertGreaterThan(above, triplet)
    }

    /// El 50% es la rejilla recta también para los impares: no es un caso
    /// especial que haya que interceptar, sale de la propia fórmula.
    func testTimingAtFiftyPercentLeavesOddStepsAlone() {
        XCTAssertEqual(
            groove(timing: 50).shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step), 0)
    }

    /// **La paridad es la del índice absoluto de la rejilla, no la de la posición
    /// en el anillo.** El swing es una propiedad del tiempo musical, no del
    /// patrón: con un número impar de Steps, el anillo y la rejilla del swing
    /// desfasan de una vuelta a la siguiente, y eso es lo correcto. Ligarlo al
    /// anillo produciría un swing que cambia de sentido al girar el knob de
    /// Steps.
    func testTimingParityFollowsTheAbsoluteIndexAndNotTheRingPosition() {
        let swung = groove(timing: 75)
        let ringSize = 5

        // El Step 0 y el Step 5 son la misma posición del anillo —0 y 5 % 5— y
        // el swing los trata distinto: uno es par y el otro impar.
        XCTAssertEqual(0 % ringSize, 5 % ringSize)
        XCTAssertEqual(swung.shiftNanoseconds(atStep: 0, stepDurationNanoseconds: step), 0)
        XCTAssertEqual(swung.shiftNanoseconds(atStep: 5, stepDurationNanoseconds: step), step / 2)
    }

    /// Los índices negativos siguen la misma paridad. `MusicalTimeline` los
    /// admite desde la rebanada 1 y Delay es quien los produce.
    func testTimingParityHoldsForNegativeIndices() {
        let swung = groove(timing: 75)

        XCTAssertEqual(swung.shiftNanoseconds(atStep: -2, stepDurationNanoseconds: step), 0)
        XCTAssertEqual(swung.shiftNanoseconds(atStep: -1, stepDurationNanoseconds: step), step / 2)
        XCTAssertEqual(swung.shiftNanoseconds(atStep: -3, stepDurationNanoseconds: step), step / 2)
    }

    // MARK: - Delay

    func testDelayAtItsEndsMovesAWholeStep() {
        XCTAssertEqual(
            groove(delay: 100).shiftNanoseconds(atStep: 4, stepDurationNanoseconds: step), step)
        XCTAssertEqual(
            groove(delay: -100).shiftNanoseconds(atStep: 4, stepDurationNanoseconds: step), -step)
    }

    /// **Delay se aplica a todos los Steps por igual**, pares e impares, que es
    /// lo que lo distingue de Timing: mueve la voz entera, no la rejilla.
    func testDelayAppliesEquallyToEveryStep() {
        let delayed = groove(delay: 50)
        let expected = step / 2

        for index in -4...16 {
            XCTAssertEqual(
                delayed.shiftNanoseconds(atStep: index, stepDurationNanoseconds: step),
                expected,
                "el Step \(index) no recibió el mismo Delay"
            )
        }
    }

    // MARK: - Los dos a la vez

    /// Se suman. El Step impar recibe el swing y el Delay; el par, solo el Delay.
    func testTimingAndDelayAddUp() {
        let both = groove(timing: 75, delay: 50)

        XCTAssertEqual(both.shiftNanoseconds(atStep: 0, stepDurationNanoseconds: step), step / 2)
        XCTAssertEqual(both.shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step), step)
    }

    /// Un Delay negativo puede cancelar el swing de un Step impar y dejarlo justo
    /// sobre la rejilla. No es un caso especial: es la suma.
    func testANegativeDelayCanCancelTheSwing() {
        let both = groove(timing: 75, delay: -50)

        XCTAssertEqual(both.shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step), 0)
        XCTAssertEqual(both.shiftNanoseconds(atStep: 2, stepDurationNanoseconds: step), -step / 2)
    }
}

/// La invariante de orden: **ningún Step se emite antes que su predecesor.**
///
/// Es la razón declarada del tope de Timing, y la propiedad de la que depende
/// que el desplazamiento no produzca notas fuera de sitio. Si este barrido falla,
/// lo que está mal es el rango del parámetro o la fórmula — nunca el test.
final class GrooveShiftOrderTests: XCTestCase {

    private let step: Int64 = 125_000_000

    /// Barrido exhaustivo del rango de los dos parámetros sobre una vuelta larga
    /// de la rejilla.
    ///
    /// **Delay no puede romper el orden por sí solo** —desplaza todos los Steps
    /// por igual— pero entra en el barrido igualmente: lo que se verifica es la
    /// combinación, no cada uno por separado.
    func testEmissionOrderIsNonDecreasingAcrossTheWholeRange() {
        for timing in Timing.validRange {
            for delay in stride(from: -100, through: 100, by: 25) {
                let groove = Groove(
                    velocity: .default,
                    sustain: .default,
                    probability: .default,
                    timing: Timing(percent: timing)!,
                    delay: Delay(percent: delay)!
                )

                var previous = Int64.min
                for index in 0...64 {
                    let emission =
                        Int64(index) * step
                        + groove.shiftNanoseconds(atStep: index, stepDurationNanoseconds: step)

                    XCTAssertGreaterThanOrEqual(
                        emission, previous,
                        "Timing \(timing)% y Delay \(delay)% invirtieron el orden en el Step \(index)"
                    )
                    previous = emission
                }
            }
        }
    }

    /// El caso extremo, aislado y explícito: al 75% el Step impar cae medio Step
    /// tarde, justo antes del siguiente, y no lo alcanza.
    func testTheExtremeSwingStillDoesNotOvertakeTheNextStep() {
        let swung = Groove(
            velocity: .default, sustain: .default, probability: .default,
            timing: Timing(percent: 75)!, delay: .default
        )

        let first = step + swung.shiftNanoseconds(atStep: 1, stepDurationNanoseconds: step)
        let second = 2 * step + swung.shiftNanoseconds(atStep: 2, stepDurationNanoseconds: step)

        XCTAssertLessThan(first, second)
    }
}

/// El presupuesto de adelanto — la cantidad de la que dependen las dos piezas de
/// la Fase 3.
///
/// Enmienda fechada del 2026-08-30 en `tech-stack.md`: un evento adelantado tiene
/// que calcularse antes de su instante, o se pide su emisión para un momento que
/// ya pasó.
final class AdvanceBudgetTests: XCTestCase {

    private let step: Int64 = 125_000_000

    private func groove(timing: Int = 50, delay: Int = 0) -> Groove {
        Groove(
            velocity: .default, sustain: .default, probability: .default,
            timing: Timing(percent: timing)!, delay: Delay(percent: delay)!
        )
    }

    /// **Con Delay >= 0 el presupuesto es exactamente cero.** Es lo que garantiza
    /// que la mitad positiva del rango —donde vive el default— no pague ni
    /// latencia de arranque ni horizonte más largo ni respuesta de knob más
    /// lenta.
    func testTheBudgetIsZeroForEveryNonNegativeDelay() {
        for percent in 0...100 {
            XCTAssertEqual(
                groove(delay: percent).advanceBudgetNanoseconds(forStep: step),
                0,
                "Delay \(percent)% reservó presupuesto sin necesitarlo"
            )
        }
    }

    /// Timing no consume presupuesto: solo atrasa.
    func testSwingDoesNotConsumeBudget() {
        for percent in Timing.validRange {
            XCTAssertEqual(groove(timing: percent).advanceBudgetNanoseconds(forStep: step), 0)
        }
    }

    func testTheBudgetIsTheAbsoluteValueOfANegativeDelay() {
        XCTAssertEqual(groove(delay: -100).advanceBudgetNanoseconds(forStep: step), step)
        XCTAssertEqual(groove(delay: -50).advanceBudgetNanoseconds(forStep: step), step / 2)
        XCTAssertEqual(groove(delay: -1).advanceBudgetNanoseconds(forStep: step), step / 100)
    }

    /// **La propiedad que sostiene toda la Fase 3.** Si el desplazamiento pudiera
    /// ser más negativo que el presupuesto, habría un instante que ni el origen
    /// desplazado ni el horizonte ampliado alcanzarían a cubrir — y ese evento se
    /// pediría para un momento que ya pasó.
    func testTheShiftIsNeverMoreNegativeThanTheBudget() {
        for timing in Timing.validRange {
            for delay in -100...100 {
                let groove = groove(timing: timing, delay: delay)
                let budget = groove.advanceBudgetNanoseconds(forStep: step)

                for index in -4...64 {
                    let shift = groove.shiftNanoseconds(
                        atStep: index, stepDurationNanoseconds: step)

                    XCTAssertGreaterThanOrEqual(
                        shift, -budget,
                        "Timing \(timing)% y Delay \(delay)% adelantaron el Step \(index) más allá del presupuesto"
                    )
                }
            }
        }
    }

    /// El presupuesto no es negativo nunca: es una cantidad de tiempo que se
    /// reserva, no un desplazamiento.
    func testTheBudgetIsNeverNegative() {
        for delay in -100...100 {
            XCTAssertGreaterThanOrEqual(
                groove(delay: delay).advanceBudgetNanoseconds(forStep: step), 0)
        }
    }
}
