import Engine
import XCTest

@testable import MIDI

/// Tests de que el preset del repositorio y `ControlMapping` dicen lo mismo.
///
/// **El README lo prometía y nadie lo comprobaba.** Su primera línea dice «los
/// mismos números que declara `ControlMapping`: si uno de los dos cambia, el
/// otro está mal», y hasta el 2026-09-05 esa frase era un ruego. El preset es
/// lo que se carga en MIDI Control Center y la app es lo que escucha: si se
/// separan, los knobs mueven lo que no dice la etiqueta y el síntoma no se
/// parece a la causa — la misma clase de avería que la nota del 2026-08-28
/// sobre los encoders.
///
/// Se escribe al remapear tres knobs, que es cuando el riesgo dejó de ser
/// teórico.
final class PresetFileTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    /// El JSON del repositorio, localizado desde este fichero.
    ///
    /// **No se copia al bundle de tests a propósito.** Lo que hay que verificar
    /// es el fichero que el usuario carga en MIDI Control Center, no una copia
    /// suya: una copia que se quedara atrás pasaría el test y rompería el
    /// controlador.
    private func preset() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MIDITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MIDI
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // raíz
        let url = root.appendingPathComponent("preset/torax-h0.beatstep-pro.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func readme() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("preset/README.md"))
    }

    // MARK: - Los knobs

    /// Cada knob asignado en el JSON mueve en la app lo que el JSON dice.
    func testEveryAssignedKnobInThePresetMatchesTheMapping() throws {
        let knobs = try XCTUnwrap(try preset()["knobs"] as? [String: Any])
        let assigned = try XCTUnwrap(knobs["assigned"] as? [[String: Any]])

        let names: [String: TrackParameter] = Dictionary(
            uniqueKeysWithValues: TrackParameter.allCases.map { ($0.description, $0) })

        for entry in assigned {
            let cc = try XCTUnwrap(entry["cc"] as? Int)
            let name = try XCTUnwrap(entry["parameter"] as? String)
            let controller = try XCTUnwrap(MIDIController(cc))

            if let parameter = names[name] {
                XCTAssertEqual(
                    mapping.parameter(for: controller), parameter,
                    "el preset dice que CC \(cc) es \(name)")
            } else {
                // La única entrada asignada que no es un `TrackParameter`.
                XCTAssertEqual(
                    mapping.editingCycleController, controller,
                    "el preset dice que CC \(cc) es «\(name)»")
            }
        }
    }

    /// Y los declarados libres no mueven nada.
    func testEveryFreeKnobInThePresetMovesNothing() throws {
        let knobs = try XCTUnwrap(try preset()["knobs"] as? [String: Any])
        let free = try XCTUnwrap(knobs["free"] as? [[String: Any]])

        for entry in free {
            let cc = try XCTUnwrap(entry["cc"] as? Int)
            let controller = try XCTUnwrap(MIDIController(cc))
            XCTAssertNil(mapping.parameter(for: controller), "CC \(cc)")
            XCTAssertNotEqual(mapping.editingCycleController, controller, "CC \(cc)")
        }
    }

    /// **Ningún knob se queda sin declarar.** Asignados y libres suman los
    /// dieciséis: sin esto, borrar una entrada del JSON no rompería nada.
    func testThePresetDeclaresAllSixteenKnobs() throws {
        let knobs = try XCTUnwrap(try preset()["knobs"] as? [String: Any])
        let assigned = try XCTUnwrap(knobs["assigned"] as? [[String: Any]])
        let free = try XCTUnwrap(knobs["free"] as? [[String: Any]])
        let numbers = (assigned + free).compactMap { $0["cc"] as? Int }.sorted()

        XCTAssertEqual(numbers, mapping.declaredNumbers.knobs)
    }

    // MARK: - Los step buttons

    /// El bloque del JSON es el que la app resuelve, y el step 14 es el índice 13.
    ///
    /// **La constante `ctrlAllModifierIndex` no se toca aquí**: es de la fase del
    /// gesto. Lo que este test fija es la mitad que sí existe ya — que el preset
    /// y el mapeo cuentan los step buttons igual.
    func testThePresetStepButtonBlockMatchesTheMapping() throws {
        let block = try XCTUnwrap(
            (try preset()["step_buttons"] as? [String: Any])?["block"] as? [String: Any])
        let first = try XCTUnwrap(block["first_cc"] as? Int)

        XCTAssertEqual(first, mapping.stepButtonBlock.number)
        XCTAssertEqual(
            mapping.stepButtonIndex(for: try XCTUnwrap(MIDIController(first + 13))), 13)
    }

    /// **El step 14 ya no dice «nada».** El preset lo declara como Ctrl All antes
    /// de que la app lo haga: la fase del gesto cierra esa ventana.
    func testThePresetDeclaresStepFourteenAsCtrlAll() throws {
        let steps = try XCTUnwrap(try preset()["step_buttons"] as? [String: Any])
        let layout = try XCTUnwrap(steps["layout"] as? [[String: Any]])
        let fourteen = try XCTUnwrap(layout.first { $0["step_button"] as? Int == 14 })

        XCTAssertEqual(fourteen["cc"] as? Int, 115)
        let meaning = try XCTUnwrap(fourteen["meaning"] as? String)
        XCTAssertTrue(meaning.contains("Ctrl All"), "el step 14 dice «\(meaning)»")
    }

    // MARK: - El README

    /// **El README lleva los mismos números.** Es la tabla que se lee con el
    /// controlador delante, así que quedarse atrás es peor que no existir.
    func testTheReadmeCarriesTheSameNumbersAsTheMapping() throws {
        let text = try readme()

        for parameter in TrackParameter.allCases {
            let cc = try XCTUnwrap(mapping.controller(for: parameter)?.number)
            XCTAssertTrue(
                text.contains("| \(cc) | \(parameter.description) |"),
                "el README no dice «\(cc) → \(parameter.description)»")
        }

        let cycle = try XCTUnwrap(mapping.editingCycleController?.number)
        XCTAssertTrue(text.contains("| \(cycle) |"), "el README no menciona el CC \(cycle)")
    }
}
