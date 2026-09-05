import Engine
import XCTest
@testable import MIDI

/// Tests del preset como tabla completa: las tres familias del BeatStep Pro y lo
/// que deliberadamente no se asigna.
///
/// **Un preset no es una lista de asignaciones**; es también la lista de lo que
/// se ignora. Sin eso, cualquier mensaje inesperado parece un defecto.
final class PresetMappingTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    // MARK: - Las tres familias

    /// Cada familia declara dieciséis controles contiguos, como el hardware.
    func testEachFamilyDeclaresSixteenContiguousControls() {
        let numbers = mapping.declaredNumbers
        for family in [numbers.knobs, numbers.pads, numbers.stepButtons] {
            XCTAssertEqual(family.count, 16)
            XCTAssertEqual(family, Array(family.first!...family.last!))
        }
    }

    /// **Ningún número aparece en dos familias.** Un solape haría que un control
    /// moviera dos cosas, y ningún test de una familia suelta lo detectaría.
    func testNoNumberIsSharedBetweenFamilies() {
        let numbers = mapping.declaredNumbers
        let all = numbers.knobs + numbers.pads + numbers.stepButtons
        XCTAssertEqual(Set(all).count, all.count, "hay números repetidos entre familias: \(all)")
    }

    /// Los tres bloques caben enteros en el rango del protocolo.
    func testEveryDeclaredNumberIsValid() {
        let numbers = mapping.declaredNumbers
        for number in numbers.knobs + numbers.stepButtons {
            XCTAssertNotNil(MIDIController(number), "CC \(number)")
        }
        for number in numbers.pads {
            XCTAssertNotNil(MIDINote(number), "nota \(number)")
        }
    }

    // MARK: - Los knobs

    /// Los nueve primeros knobs son los nueve parámetros, en la tabla que
    /// declara el preset.
    ///
    /// > **El orden dejó de seguir a `TrackParameter` el 2026-09-05.** Este test
    /// > se llamaba `…AreTheNineParametersInOrder` y recorría `allCases`
    /// > confiando en que el knob N fuera el parámetro N. Con Delay en el 76 y
    /// > Probability en el 78 eso ya no es cierto, así que la tabla se escribe
    /// > entera: un test que deduce lo que debería comprobar no protege nada, y
    /// > éste habría seguido pasando con los dos knobs intercambiados si el
    /// > intercambio hubiera sido un error de dedo.
    ///
    /// La pantalla **sí** conserva el orden de `TrackParameter`
    /// —`Velocity · Sustain · Probability · Timing · Delay`—: el orden de lectura
    /// es del dominio y el de los knobs es de la mano, y desde esta fecha son dos
    /// cosas distintas.
    func testTheFirstNineKnobsCarryTheDeclaredParameters() {
        let expected: [Int: TrackParameter] = [
            70: .steps, 71: .pulses, 72: .rotate, 73: .division,
            74: .velocity, 75: .sustain, 76: .delay, 77: .timing, 78: .probability,
        ]
        for (number, parameter) in expected {
            XCTAssertEqual(mapping.controller(for: parameter)?.number, number, "\(parameter)")
        }
        XCTAssertEqual(expected.count, TrackParameter.allCases.count, "falta algún parámetro")
    }

    /// El intercambio del 2026-09-05, escrito aparte porque es lo que se pidió.
    func testDelayIsOnSeventySixAndProbabilityOnSeventyEight() throws {
        XCTAssertEqual(
            mapping.parameter(for: try XCTUnwrap(MIDIController(76))), .delay)
        XCTAssertEqual(
            mapping.parameter(for: try XCTUnwrap(MIDIController(78))), .probability)
    }

    /// Y ningún otro parámetro se movió de sitio con el intercambio.
    func testNoOtherParameterChangedController() throws {
        let untouched: [Int: TrackParameter] = [
            70: .steps, 71: .pulses, 72: .rotate, 73: .division,
            74: .velocity, 75: .sustain, 77: .timing,
        ]
        for (number, parameter) in untouched {
            XCTAssertEqual(
                mapping.parameter(for: try XCTUnwrap(MIDIController(number))), parameter,
                "CC \(number)")
        }
    }

    /// **Los siete restantes están declarados y sin asignar.** No es un olvido:
    /// su sitio es de v2, y hasta entonces girarlos no publica nada.
    func testTheLastSevenKnobsCarryNoParameter() throws {
        let knobs = mapping.declaredNumbers.knobs
        for number in knobs.suffix(7) {
            let controller = try XCTUnwrap(MIDIController(number))
            XCTAssertNil(mapping.parameter(for: controller), "CC \(number)")
        }
    }

    /// Y girarlos no publica: el mapeo y la entrada dicen lo mismo.
    func testTurningAFreeKnobPublishesNothing() throws {
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            publish: { _ in }
        )
        for number in mapping.declaredNumbers.knobs.suffix(7) {
            let controller = try XCTUnwrap(MIDIController(number))
            XCTAssertFalse(
                input.receive(
                    .controlChange(channel: MIDIChannel(1)!, controller: controller, value: 1)),
                "CC \(number)")
        }
    }

    // MARK: - Los step buttons

    func testTheStepButtonBlockResolvesToItsIndices() throws {
        let base = mapping.stepButtonBlock.number
        for offset in 0..<16 {
            let controller = try XCTUnwrap(MIDIController(base + offset))
            XCTAssertEqual(mapping.stepButtonIndex(for: controller), offset)
        }
    }

    func testControllersOutsideTheStepButtonBlockHaveNoIndex() throws {
        let base = mapping.stepButtonBlock.number
        for number in 0...127 where !(base..<(base + 16)).contains(number) {
            let controller = try XCTUnwrap(MIDIController(number))
            XCTAssertNil(mapping.stepButtonIndex(for: controller), "CC \(number)")
        }
    }

    /// Los bloques son datos del mapeo: moverlos mueve los dieciséis a la vez.
    func testMovingABlockMovesItsWholeFamily() throws {
        let moved = ControlMapping(
            assignments: [.steps: 70],
            knobBlock: try XCTUnwrap(MIDIController(20)),
            stepButtonBlock: try XCTUnwrap(MIDIController(40))
        )
        XCTAssertEqual(moved.declaredNumbers.knobs.first, 20)
        XCTAssertEqual(moved.stepButtonIndex(for: try XCTUnwrap(MIDIController(55))), 15)
        XCTAssertNil(moved.stepButtonIndex(for: try XCTUnwrap(MIDIController(56))))
    }
}
