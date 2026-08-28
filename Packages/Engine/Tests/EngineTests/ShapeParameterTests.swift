import XCTest
@testable import Engine

/// Tests del enumerado de parámetros de Shape.
///
/// Es lo que un knob puede mover. Vive en `Engine` y no en la capa de entrada
/// porque nombra conceptos del dominio, no del transporte MIDI: qué se puede
/// ajustar es una propiedad del motor, y por dónde llega la orden es otra cosa.
final class ShapeParameterTests: XCTestCase {

    /// Los cuatro que existen hoy. Tonal y Groove añadirán los suyos.
    func testCoversEveryShapeParameter() {
        XCTAssertEqual(
            Set(ShapeParameter.allCases),
            [.steps, .pulses, .rotate, .division]
        )
    }

    /// Vocabulario de la Pre Spec, sin sinónimos: los nombres del enumerado son
    /// los términos del documento.
    func testNamesMatchThePreSpecVocabulary() {
        XCTAssertEqual(
            ShapeParameter.allCases.map(\.description).sorted(),
            ["Division", "Pulses", "Rotate", "Steps"]
        )
    }
}
