import Engine
import XCTest

@testable import MIDI

/// Tests de la regla que hace falta para aprender: **un destino, un control**.
///
/// El preset de fábrica cumple la regla por construcción —lo escribió alguien
/// mirando la tabla— y por eso `PresetMappingTests` la comprueba sobre él. Un
/// mapeo aprendido se construye control a control y con el dedo, así que la
/// regla tiene que estar en el tipo y no en el cuidado de quien escribe.
///
/// **Y lo que se queda sin control se tiene que poder nombrar** (FR4). Aprender
/// un knob que ya movía otra cosa deja esa otra cosa muda: es un estado válido
/// —FR5— pero silencioso, y un destino mudo que no se anuncia parece un fallo.
final class LearnedMappingTests: XCTestCase {

    // MARK: - Asignar (FR4)

    func testAssigningAControllerMovesTheParameter() {
        let mapping = ControlMapping(assignments: [:])
            .assigning(MIDIController(20)!, to: .steps)

        XCTAssertEqual(mapping.controller(for: .steps), MIDIController(20)!)
        XCTAssertEqual(mapping.parameter(for: MIDIController(20)!), .steps)
    }

    /// **Un destino tiene un control y solo uno.** Reasignar Steps del 70 al 20
    /// deja el 70 sin dueño, no a Steps con dos knobs.
    func testAssigningReplacesTheParametersPreviousController() {
        let mapping = ControlMapping(assignments: [.steps: 70])
            .assigning(MIDIController(20)!, to: .steps)

        XCTAssertEqual(mapping.controller(for: .steps), MIDIController(20)!)
        XCTAssertNil(mapping.parameter(for: MIDIController(70)!))
    }

    /// **Y un control mueve un destino y solo uno.** Es la mitad que se olvida:
    /// aprender el knob de Steps para Pulses tiene que dejar Steps sin control,
    /// no a los dos escuchando el mismo giro.
    func testAssigningAnOccupiedControllerUnassignsTheOtherParameter() {
        let mapping = ControlMapping(assignments: [.steps: 70, .pulses: 71])
            .assigning(MIDIController(70)!, to: .pulses)

        XCTAssertEqual(mapping.controller(for: .pulses), MIDIController(70)!)
        XCTAssertNil(mapping.controller(for: .steps))
    }

    func testAssigningTheControllerAParameterAlreadyHasChangesNothing() {
        let before = ControlMapping(assignments: [.steps: 70, .pulses: 71])

        XCTAssertEqual(before.assigning(MIDIController(70)!, to: .steps), before)
    }

    /// Los bloques no son de `assignments`, así que asignar un knob no puede
    /// moverlos. Sin este test, un `assigning` escrito con prisa devolvería un
    /// mapeo con los bloques por defecto y los pads se irían de sitio.
    func testAssigningKeepsTheBlocks() {
        let before = ControlMapping(
            assignments: [.steps: 70],
            padBlock: MIDINote(60)!,
            knobBlock: MIDIController(20)!,
            stepButtonBlock: MIDIController(40)!
        )

        let after = before.assigning(MIDIController(21)!, to: .steps)

        XCTAssertEqual(after.padBlock, before.padBlock)
        XCTAssertEqual(after.knobBlock, before.knobBlock)
        XCTAssertEqual(after.stepButtonBlock, before.stepButtonBlock)
    }

    // MARK: - Lo que se queda mudo (FR4, FR5)

    func testAMappingWithNothingAssignedLeavesEveryParameterWithoutAControl() {
        let mapping = ControlMapping(assignments: [:])

        XCTAssertEqual(
            Set(mapping.parametersWithoutController), Set(TrackParameter.allCases))
    }

    func testTheFactoryPresetLeavesNoParameterWithoutAControl() {
        XCTAssertEqual(ControlMapping.beatStepPro.parametersWithoutController, [])
    }

    /// El caso que la pantalla tiene que poder contar: aprender un control
    /// ocupado deja **al otro** mudo, y hay que saber cuál.
    ///
    /// **Se pregunta por los dos, no por la lista entera.** Un mapeo de prueba
    /// con dos asignaciones deja mudos a los otros diez de todas formas, así que
    /// comparar contra `[.steps]` probaría el material de prueba y no la regla.
    func testTheDisplacedParameterIsListed() {
        let mapping = ControlMapping(assignments: [.steps: 70, .pulses: 71])
            .assigning(MIDIController(70)!, to: .pulses)

        XCTAssertTrue(mapping.parametersWithoutController.contains(.steps))
        XCTAssertFalse(mapping.parametersWithoutController.contains(.pulses))
    }

    /// **El orden es el del dominio, no el de un diccionario.** Un listado que
    /// baila entre ejecuciones haría que la pantalla reordenara sola.
    func testTheListingKeepsTheDomainOrder() {
        let mapping = ControlMapping(assignments: [:])

        XCTAssertEqual(mapping.parametersWithoutController, TrackParameter.allCases)
    }

    // MARK: - Las tres familias no se pisan

    /// Knobs y step buttons son los dos CC, así que **un mapeo aprendido sí
    /// puede solaparlos** — el de fábrica no lo hace porque alguien lo escribió
    /// mirando la tabla. Los pads son notas y no entran en la comparación.
    func testAKnobFallingInTheStepButtonBlockIsReportedAsOverlap() {
        let mapping = ControlMapping(
            assignments: [:], knobBlock: MIDIController(102)!,
            stepButtonBlock: MIDIController(102)!)

        XCTAssertTrue(mapping.hasFamilyOverlap)
    }

    func testTheFactoryPresetHasNoOverlap() {
        XCTAssertFalse(ControlMapping.beatStepPro.hasFamilyOverlap)
    }

    /// Solaparse a medias sigue siendo solaparse: basta un número compartido.
    func testAPartialOverlapIsStillAnOverlap() {
        let mapping = ControlMapping(
            assignments: [:], knobBlock: MIDIController(100)!,
            stepButtonBlock: MIDIController(102)!)

        XCTAssertTrue(mapping.hasFamilyOverlap)
    }

    func testBlocksThatDoNotTouchAreNotAnOverlap() {
        let mapping = ControlMapping(
            assignments: [:], knobBlock: MIDIController(20)!,
            stepButtonBlock: MIDIController(102)!)

        XCTAssertFalse(mapping.hasFamilyOverlap)
    }
}
