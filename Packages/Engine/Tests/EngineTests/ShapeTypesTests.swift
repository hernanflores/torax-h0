import XCTest

@testable import Engine

/// Tests de los tipos de Shape.
///
/// La validación vive en el inicializador, no en cada sitio de uso
/// (`conductor/code_styleguides/swift.md`): un `Steps` o un `Pulses` que existe
/// es siempre musicalmente válido, y el resto del motor puede confiar en ello
/// sin volver a comprobarlo.
final class ShapeTypesTests: XCTestCase {

    // MARK: - Steps

    func testStepsAcceptsTheWholeValidRange() {
        for count in 1...16 {
            XCTAssertEqual(Steps(count)?.count, count)
        }
    }

    func testStepsRejectsZeroAndNegativeCounts() {
        XCTAssertNil(Steps(0))
        XCTAssertNil(Steps(-1))
    }

    /// El rango 1–64 de la Pre Spec queda fuera de v1: el tipo se valida a 1–16.
    func testStepsRejectsCountsAboveSixteen() {
        XCTAssertNil(Steps(17))
        XCTAssertNil(Steps(64))
    }

    func testStepsValidRangeIsOneToSixteen() {
        XCTAssertEqual(Steps.validRange, 1...16)
    }

    // MARK: - Pulses

    func testPulsesAcceptsOneThroughSteps() {
        let steps = Steps(12)!
        for count in 1...12 {
            XCTAssertEqual(Pulses(count, in: steps)?.count, count)
        }
    }

    func testPulsesRejectsZeroAndNegativeCounts() {
        let steps = Steps(16)!
        XCTAssertNil(Pulses(0, in: steps))
        XCTAssertNil(Pulses(-3, in: steps))
    }

    func testPulsesRejectsMoreThanSteps() {
        let steps = Steps(8)!
        XCTAssertNil(Pulses(9, in: steps))
        XCTAssertNil(Pulses(16, in: steps))
    }

    /// El límite superior depende de Steps, no de una constante: con Steps = 1
    /// el único Pulses válido es 1.
    func testPulsesUpperBoundFollowsSteps() {
        let steps = Steps(1)!
        XCTAssertEqual(Pulses(1, in: steps)?.count, 1)
        XCTAssertNil(Pulses(2, in: steps))
    }

    // MARK: - Rotate

    /// Rotate no se valida contra un rango: es un desplazamiento sobre un
    /// anillo, así que cualquier entero tiene sentido y envuelve.
    func testRotateAcceptsNegativeAmounts() {
        XCTAssertEqual(Rotate(-5).amount, -5)
    }

    func testRotateAcceptsAmountsGreaterThanSteps() {
        XCTAssertEqual(Rotate(37).amount, 37)
    }

    func testRotateZeroIsTheDefault() {
        XCTAssertEqual(Rotate.none.amount, 0)
    }
}
