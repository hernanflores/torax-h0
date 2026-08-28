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

    func testPulsesAcceptsTheWholeValidRange() {
        for count in 1...16 {
            XCTAssertEqual(Pulses(count)?.count, count)
        }
    }

    func testPulsesRejectsZeroAndNegativeCounts() {
        XCTAssertNil(Pulses(0))
        XCTAssertNil(Pulses(-3))
    }

    func testPulsesRejectsCountsAboveSixteen() {
        XCTAssertNil(Pulses(17))
        XCTAssertNil(Pulses(64))
    }

    /// El rango de Pulses es el de Steps: no puede haber más Pulses que
    /// posiciones donde ponerlos, ni siquiera en el anillo más largo.
    func testPulsesRangeMatchesTheStepsRange() {
        XCTAssertEqual(Pulses.validRange, Steps.validRange)
    }

    /// **Pulses ya no se valida contra un Steps concreto.**
    ///
    /// Antes su inicializador exigía el anillo y rechazaba cualquier valor
    /// mayor. Eso hacía que girar Steps hacia abajo destruyera Pulses, y
    /// `product-guidelines.md` lo prohíbe: «cambiar un parámetro nunca destruye
    /// material». Ahora el valor guardado es la intención y el reparto usa lo
    /// que cabe — igual que `Rotate`, que tampoco se valida contra el anillo
    /// porque es el reparto quien conoce su tamaño.
    func testPulsesMayExceedTheRingItWillBePlacedIn() {
        XCTAssertEqual(Pulses(9)?.count, 9)
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
