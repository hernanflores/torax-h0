import XCTest

@testable import Engine

/// Tests de los cuatro tipos del Note Repeater: `Repeats`, `RepeatTime`, `Ramp`
/// y `Pace`.
///
/// **Los cuatro validan en el inicializador**, como `Velocity`, `Sustain` y
/// `Division`: un valor que existe es siempre emisible, y ningún sitio de uso
/// vuelve a comprobar el rango.
///
/// **Ninguno envuelve.** Es el criterio de `Steps` y `Division` y no el de
/// `Rotate`: girar de más contra un tope devuelve el mismo valor, porque saltar
/// de ocho repeticiones a ninguna convierte un ajuste fino en un cambio brutal
/// —`product-guidelines.md` pide que girar produzca «siempre un cambio inmediato
/// y proporcional»—.
final class NoteRepeaterTypesTests: XCTestCase {

    // MARK: - Repeats

    /// El default del producto es 0, y de él depende toda la no regresión de la
    /// rebanada (FR16): sin repeticiones, la salida es la de antes.
    func testRepeatsDefaultsToZero() {
        XCTAssertEqual(Repeats.default.count, 0)
    }

    /// 0–8, y no el 0–48 de la Pre Spec. La desviación está fechada el
    /// 2026-09-07 en `Pre Spec Torax H-0.md`.
    func testRepeatsAcceptsItsWholeRange() {
        for count in 0...8 {
            XCTAssertEqual(Repeats(count)?.count, count)
        }
    }

    func testRepeatsRejectsValuesOutsideItsRange() {
        XCTAssertNil(Repeats(-1))
        XCTAssertNil(Repeats(9))
    }

    func testRepeatsMovesByTheKnobDelta() {
        XCTAssertEqual(Repeats(3)!.advanced(by: 2).count, 5)
        XCTAssertEqual(Repeats(3)!.advanced(by: -2).count, 1)
    }

    /// **Se detiene en los extremos, no envuelve.**
    func testRepeatsStopsAtBothEnds() {
        XCTAssertEqual(Repeats(8)!.advanced(by: 1).count, 8)
        XCTAssertEqual(Repeats(0)!.advanced(by: -1).count, 0)
        XCTAssertEqual(Repeats(0)!.advanced(by: 40).count, 8)
        XCTAssertEqual(Repeats(8)!.advanced(by: -40).count, 0)
    }

    // MARK: - Time

    /// Default 1/32, literal de la especificación de la rebanada.
    func testTimeDefaultsToAThirtySecond() {
        XCTAssertEqual(RepeatTime.default.fraction, Division(numerator: 1, denominator: 32))
    }

    /// **Las nueve posiciones, de más lenta a más rápida**: rectos y sus
    /// tresillos.
    func testTimeRunsThroughNineFractionsFromSlowestToFastest() {
        let expected = [8, 12, 16, 24, 32, 48, 64, 96, 128]
        XCTAssertEqual(RepeatTime.ordered.count, expected.count)
        for (time, denominator) in zip(RepeatTime.ordered, expected) {
            XCTAssertEqual(time.fraction.numerator, 1)
            XCTAssertEqual(time.fraction.denominator, denominator)
        }
    }

    func testTimeMovesForwardTowardsTheFasterFractions() {
        XCTAssertEqual(RepeatTime.default.advanced(by: 1), RepeatTime.ordered[5])
        XCTAssertEqual(RepeatTime.default.advanced(by: -1), RepeatTime.ordered[3])
    }

    /// **Se detiene en los extremos, no envuelve** — igual que `Division`.
    func testTimeStopsAtBothEnds() {
        XCTAssertEqual(RepeatTime.ordered.last!.advanced(by: 1), RepeatTime.ordered.last!)
        XCTAssertEqual(RepeatTime.ordered.first!.advanced(by: -1), RepeatTime.ordered.first!)
        XCTAssertEqual(RepeatTime.ordered.first!.advanced(by: 40), RepeatTime.ordered.last!)
    }

    /// Una Time que no está en la lista se devuelve intacta al avanzar, con el
    /// mismo criterio que `Division`: el recorrido no puede inventar un punto de
    /// partida que no existe.
    func testATimeOutsideTheListIsReturnedUnchanged() {
        let unlisted = RepeatTime(numerator: 3, denominator: 7)!
        XCTAssertEqual(unlisted.advanced(by: 1), unlisted)
        XCTAssertEqual(unlisted.advanced(by: -1), unlisted)
    }

    /// Se lee como la fracción que es, que es lo que la pantalla enseña al
    /// girar el knob: `1/32`.
    func testTimeReadsAsItsFraction() {
        XCTAssertEqual(RepeatTime.default.description, "1/32")
        XCTAssertEqual(RepeatTime.ordered.first!.description, "1/8")
    }

    func testTimeRejectsFractionsThatAreNotPositive() {
        XCTAssertNil(RepeatTime(numerator: 0, denominator: 16))
        XCTAssertNil(RepeatTime(numerator: 1, denominator: 0))
        XCTAssertNil(RepeatTime(numerator: -1, denominator: 16))
    }

    /// **La lista de Time es suya y no amplía la de Division.** Meter tresillos
    /// en `Division.ordered` cambiaría por dónde pasa otro knob.
    func testTimeDoesNotExtendTheDivisionList() {
        XCTAssertEqual(Division.ordered.count, 6)
        XCTAssertEqual(Division.ordered.last, Division.thirtySecond)
    }

    // MARK: - Ramp

    func testRampDefaultsToZero() {
        XCTAssertEqual(Ramp.default.percent, 0)
    }

    /// Bipolar y simétrico, como `Delay`: el cero es el centro, no un extremo.
    func testRampAcceptsItsWholeRange() {
        XCTAssertEqual(Ramp(percent: -100)?.percent, -100)
        XCTAssertEqual(Ramp(percent: 0)?.percent, 0)
        XCTAssertEqual(Ramp(percent: 100)?.percent, 100)
    }

    func testRampRejectsValuesOutsideItsRange() {
        XCTAssertNil(Ramp(percent: -101))
        XCTAssertNil(Ramp(percent: 101))
    }

    func testRampStopsAtBothEnds() {
        XCTAssertEqual(Ramp(percent: 100)!.advanced(by: 1).percent, 100)
        XCTAssertEqual(Ramp(percent: -100)!.advanced(by: -1).percent, -100)
        XCTAssertEqual(Ramp(percent: 0)!.advanced(by: -40).percent, -40)
    }

    // MARK: - Pace

    func testPaceDefaultsToZero() {
        XCTAssertEqual(Pace.default.percent, 0)
    }

    func testPaceAcceptsItsWholeRange() {
        XCTAssertEqual(Pace(percent: -100)?.percent, -100)
        XCTAssertEqual(Pace(percent: 0)?.percent, 0)
        XCTAssertEqual(Pace(percent: 100)?.percent, 100)
    }

    func testPaceRejectsValuesOutsideItsRange() {
        XCTAssertNil(Pace(percent: -101))
        XCTAssertNil(Pace(percent: 101))
    }

    func testPaceStopsAtBothEnds() {
        XCTAssertEqual(Pace(percent: 100)!.advanced(by: 1).percent, 100)
        XCTAssertEqual(Pace(percent: -100)!.advanced(by: -1).percent, -100)
        XCTAssertEqual(Pace(percent: 0)!.advanced(by: 40).percent, 40)
    }
}
