import XCTest
@testable import Engine

/// Tests del enumerado de parámetros, en su parte de Shape.
///
/// **Conservados tal cual al renombrar `ShapeParameter` a `TrackParameter` en
/// la rebanada 5.** El criterio de aquel renombrado era que los tests de Shape
/// siguieran pasando sin reescribirse: si hubiera que tocarlos, es que cambió el
/// comportamiento y no solo el nombre. Solo cambian el nombre del tipo y el
/// hecho de que ahora la lista tiene además los tres de Groove.
///
/// Es lo que un knob puede mover. Vive en `Engine` y no en la capa de entrada
/// porque nombra conceptos del dominio, no del transporte MIDI: qué se puede
/// ajustar es una propiedad del motor, y por dónde llega la orden es otra cosa.
final class TrackParameterNamesTests: XCTestCase {

    /// Los cuatro de Shape siguen estando, y siguen siendo esos cuatro.
    func testCoversEveryShapeParameter() {
        XCTAssertTrue(
            Set(TrackParameter.allCases).isSuperset(of: [.steps, .pulses, .rotate, .division])
        )
    }

    /// Vocabulario de la Pre Spec, sin sinónimos: los nombres del enumerado son
    /// los términos del documento.
    func testNamesMatchThePreSpecVocabulary() {
        let shapeNames = [TrackParameter.steps, .pulses, .rotate, .division]
            .map(\.description).sorted()
        XCTAssertEqual(shapeNames, ["Division", "Pulses", "Rotate", "Steps"])
    }
}
