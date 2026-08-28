import XCTest
@testable import Engine

/// Tests del texto con el que Shape se muestra en pantalla.
///
/// Vive en `Engine` y no en la app porque es donde está el vocabulario, y
/// porque aquí sí se puede testear: el proyecto de app no tiene target de test
/// y la máquina no tiene runtime de simulador.
///
/// `product-guidelines.md` fija dos reglas que estos tests vigilan: «Preciso, no
/// conversacional» —`Steps 16 · Pulses 5`, no «Has elegido 5 pulsos»— y
/// «Vocabulario de la Pre Spec, en inglés, sin traducir».
final class ShapeDescriptionTests: XCTestCase {

    private func shape(
        steps stepCount: Int,
        pulses pulseCount: Int,
        rotate amount: Int = 0,
        division: Division = .sixteenth
    ) -> Shape {
        let steps = Steps(stepCount)!
        return Shape(
            steps: steps,
            pulses: Pulses(pulseCount)!,
            rotate: Rotate(amount),
            division: division
        )
    }

    // MARK: - Formato

    func testDivisionReadsAsAFraction() {
        XCTAssertEqual(Division.sixteenth.description, "1/16")
        XCTAssertEqual(Division.quarter.description, "1/4")
        XCTAssertEqual(Division.eighth.description, "1/8")
    }

    func testShapeReadsAsItsParameters() {
        XCTAssertEqual(
            shape(steps: 16, pulses: 5).description,
            "Steps 16 · Pulses 5 · Rotate 0 · Division 1/16"
        )
    }

    func testShapeShowsTheValuesItActuallyHas() {
        XCTAssertEqual(
            shape(steps: 12, pulses: 7, rotate: 3, division: .eighth).description,
            "Steps 12 · Pulses 7 · Rotate 3 · Division 1/8"
        )
    }

    /// Rotate negativo se muestra tal cual: es el valor del parámetro, no el
    /// giro ya normalizado sobre el anillo.
    func testNegativeRotateIsShownAsGiven() {
        XCTAssertEqual(
            shape(steps: 16, pulses: 4, rotate: -2).description,
            "Steps 16 · Pulses 4 · Rotate -2 · Division 1/16"
        )
    }

    // MARK: - Guardias sobre las guidelines

    /// «Preciso, no conversacional. La app no explica ni acompaña: informa.»
    func testDescriptionIsNotConversational() {
        let forbidden = ["has ", "you ", "your ", "elegido", "seleccionado", "!", "?"]
        let description = shape(steps: 16, pulses: 5).description.lowercased()
        for word in forbidden {
            XCTAssertFalse(description.contains(word), "«\(description)» suena conversacional")
        }
    }

    /// «Vocabulario de la Pre Spec, en inglés, sin traducir.»
    func testVocabularyIsThePreSpecTermsInEnglish() {
        let description = shape(steps: 16, pulses: 5).description
        for term in ["Steps", "Pulses", "Rotate", "Division"] {
            XCTAssertTrue(description.contains(term), "falta el término «\(term)»")
        }
        for translation in ["Pasos", "Pulsos", "Giro", "División"] {
            XCTAssertFalse(description.contains(translation), "traduce «\(translation)»")
        }
    }

    /// **Nada debe sugerir una nota fija por paso.** `product-guidelines.md`
    /// advierte que contradice el modelo de pool de la Pre Spec, y la altura de
    /// esta rebanada es una constante provisional del camino MIDI, no un valor
    /// musical que la pantalla deba mostrar.
    func testDescriptionSaysNothingAboutPitch() {
        let description = shape(steps: 16, pulses: 5).description.lowercased()
        for term in ["note", "pitch", "nota", "c3", "midi", "48"] {
            XCTAssertFalse(description.contains(term), "«\(description)» sugiere una altura fija")
        }
    }
}
