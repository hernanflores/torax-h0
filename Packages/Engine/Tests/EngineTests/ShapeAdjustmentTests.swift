import XCTest
@testable import Engine

/// Tests de aplicar un desplazamiento a un parámetro de Shape.
///
/// Es lo que produce un giro de knob, expresado sin saber nada de MIDI.
final class ShapeAdjustmentTests: XCTestCase {

    private func shape(
        steps: Int = 16, pulses: Int = 4, rotate: Int = 0, division: Division = .sixteenth
    ) -> Shape {
        Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate), division: division)
    }

    // MARK: - Identidad y aislamiento

    func testApplyingZeroChangesNothing() {
        let original = shape(steps: 12, pulses: 7, rotate: 3, division: .eighth)
        for parameter in ShapeParameter.allCases {
            XCTAssertEqual(original.applying(0, to: parameter), original, "\(parameter)")
        }
    }

    /// Mover un parámetro no puede tocar los otros tres.
    func testAdjustingOneParameterLeavesTheOthersAlone() {
        let original = shape(steps: 12, pulses: 7, rotate: 3, division: .eighth)

        let steps = original.applying(1, to: .steps)
        XCTAssertEqual(steps.pulses, original.pulses)
        XCTAssertEqual(steps.rotate, original.rotate)
        XCTAssertEqual(steps.division, original.division)

        let pulses = original.applying(1, to: .pulses)
        XCTAssertEqual(pulses.steps, original.steps)
        XCTAssertEqual(pulses.rotate, original.rotate)
        XCTAssertEqual(pulses.division, original.division)
    }

    // MARK: - Steps

    func testStepsMovesWithinItsRange() {
        XCTAssertEqual(shape(steps: 8).applying(3, to: .steps).steps.count, 11)
        XCTAssertEqual(shape(steps: 8).applying(-3, to: .steps).steps.count, 5)
    }

    func testStepsStopsAtItsEnds() {
        XCTAssertEqual(shape(steps: 16).applying(5, to: .steps).steps.count, 16)
        XCTAssertEqual(shape(steps: 1, pulses: 1).applying(-5, to: .steps).steps.count, 1)
    }

    // MARK: - Pulses

    func testPulsesMovesWithinItsRange() {
        XCTAssertEqual(shape(pulses: 4).applying(3, to: .pulses).pulses.count, 7)
        XCTAssertEqual(shape(pulses: 4).applying(-3, to: .pulses).pulses.count, 1)
    }

    /// **Pulses no se frena en Steps, solo en su propio rango.** Frenarlo antes
    /// sería el acotado destructivo que la Fase 1 eliminó.
    func testPulsesIsNotLimitedByStepsWhenAdjusted() {
        let adjusted = shape(steps: 4, pulses: 4).applying(5, to: .pulses)
        XCTAssertEqual(adjusted.pulses.count, 9, "se frenó en Steps en vez de en su rango")
        XCTAssertEqual(adjusted.effectivePulses, 4, "sonaron más de los que caben")
    }

    func testPulsesStopsAtItsEnds() {
        XCTAssertEqual(shape(pulses: 16).applying(5, to: .pulses).pulses.count, 16)
        XCTAssertEqual(shape(pulses: 1).applying(-5, to: .pulses).pulses.count, 1)
    }

    /// Bajar Steps hasta el fondo y volver a subirlo conserva Pulses: es la
    /// propiedad de la Fase 1, ahora a través de los giros de knob.
    func testTurningStepsDownAndBackUpKeepsPulses() {
        var current = shape(steps: 16, pulses: 12)
        for _ in 0..<15 { current = current.applying(-1, to: .steps) }
        XCTAssertEqual(current.steps.count, 1)
        XCTAssertEqual(current.pulses.count, 12, "el giro de Steps destruyó Pulses")

        for _ in 0..<15 { current = current.applying(1, to: .steps) }
        XCTAssertEqual(current, shape(steps: 16, pulses: 12))
    }

    // MARK: - Rotate

    /// **Rotate sí envuelve, al contrario que Division.** Es un giro sobre un
    /// anillo cerrado: pasarse del último Step y aparecer en el primero es el
    /// comportamiento correcto, no un desbordamiento.
    func testRotateWrapsAroundTheRing() {
        XCTAssertEqual(shape(steps: 16, rotate: 15).applying(1, to: .rotate).rotate, Rotate(0))
        XCTAssertEqual(shape(steps: 16, rotate: 0).applying(-1, to: .rotate).rotate, Rotate(15))
    }

    /// Girar tanto como Steps devuelve el patrón al punto de partida.
    func testAFullTurnOfRotateReturnsToTheStart() {
        let original = shape(steps: 12, pulses: 7)
        var current = original
        for _ in 0..<12 { current = current.applying(1, to: .rotate) }
        XCTAssertEqual(current, original)
    }

    /// Un giro largo no desborda ni deja el valor fuera del anillo.
    func testLargeRotateDeltasStayInsideTheRing() {
        for delta in [100, -100, 10_000, -10_000] {
            let rotate = shape(steps: 16).applying(delta, to: .rotate).rotate.amount
            XCTAssertTrue((0..<16).contains(rotate), "delta \(delta) dejó Rotate en \(rotate)")
        }
    }

    // MARK: - Division

    func testDivisionStepsThroughTheList() {
        XCTAssertEqual(shape(division: .quarter).applying(1, to: .division).division, .eighth)
        XCTAssertEqual(shape(division: .quarter).applying(-1, to: .division).division, .half)
    }

    /// Division **no** envuelve: saltar de 1/16 a 1/1 sería un cambio de
    /// velocidad de 16x en un clic.
    func testDivisionStopsAtItsEnds() {
        XCTAssertEqual(shape(division: .sixteenth).applying(9, to: .division).division, .sixteenth)
        XCTAssertEqual(shape(division: .whole).applying(-9, to: .division).division, .whole)
    }
}
