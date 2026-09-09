import Engine
import XCTest

@testable import MIDI

/// Tests de la traducción entre el mapeo y sus números.
///
/// **`Engine` no puede ver CoreMIDI**, así que el `Project` guarda el mapeo en
/// números y `MIDI` lo convierte en las dos direcciones. Es el mismo reparto por
/// el que el destino se guarda por su nombre y no por su `MIDIEndpointRef`.
final class MappingNumbersTests: XCTestCase {

    func testAMappingSurvivesTheRoundTripThroughNumbers() {
        let mapping = ControlMapping(
            assignments: [.steps: 20, .pace: 31],
            padBlock: MIDINote(60)!,
            knobBlock: MIDIController(20)!,
            stepButtonBlock: MIDIController(40)!
        )

        XCTAssertEqual(ControlMapping(mapping.numbers), mapping)
    }

    func testTheFactoryPresetSurvivesTheRoundTrip() {
        XCTAssertEqual(
            ControlMapping(ControlMapping.beatStepPro.numbers), ControlMapping.beatStepPro)
    }

    /// **Un número que no es un controlador válido se descarta.** El disco lo
    /// puede traer, porque un `Int` no promete nada; el mapeo no puede quedarse
    /// con una asignación imposible.
    func testAnOutOfRangeNumberIsDropped() {
        let numbers = ControlNumbers(
            assignments: [.steps: 999], padBlock: 36, knobBlock: 70, stepButtonBlock: 102)

        XCTAssertNil(ControlMapping(numbers).controller(for: .steps))
    }

    /// Y un bloque imposible cae en el de fábrica, en vez de dejar la app sin
    /// pads: es el mismo criterio que una escala desconocida cayendo en `minor`.
    func testAnOutOfRangeBlockFallsBackToTheFactoryOne() {
        let numbers = ControlNumbers(
            assignments: [:], padBlock: 999, knobBlock: 999, stepButtonBlock: 999)

        let mapping = ControlMapping(numbers)

        XCTAssertEqual(mapping.padBlock, ControlMapping.defaultPadBlock)
        XCTAssertEqual(mapping.knobBlock, ControlMapping.defaultKnobBlock)
        XCTAssertEqual(mapping.stepButtonBlock, ControlMapping.defaultStepButtonBlock)
    }

    /// Lo que se aprende es lo que se guarda: el caso entero, de aprender a
    /// números.
    func testWhatIsLearnedIsWhatGetsWritten() {
        let learned = ControlMapping.beatStepPro.assigning(MIDIController(20)!, to: .steps)

        XCTAssertEqual(learned.numbers.assignments[.steps], 20)
        XCTAssertEqual(ControlMapping(learned.numbers), learned)
    }
}
