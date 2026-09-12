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
    ///
    /// > **Trece desde el 2026-09-07.** Los cuatro del Note Repeater entran en
    /// > los CC 79, 80, 81 y 83, saltando el 82 porque ahí está el Cycle en
    /// > edición. El nombre del test deja de decir «nueve».
    func testEveryKnobCarriesItsDeclaredParameter() {
        let expected: [Int: TrackParameter] = [
            70: .steps, 71: .pulses, 72: .rotate, 73: .division,
            74: .velocity, 75: .sustain, 76: .delay, 77: .timing, 78: .probability,
            79: .repeats, 80: .repeatTime, 81: .ramp, 83: .pace,
        ]
        for (number, parameter) in expected {
            XCTAssertEqual(mapping.controller(for: parameter)?.number, number, "\(parameter)")
        }
        XCTAssertEqual(expected.count, TrackParameter.allCases.count, "falta algún parámetro")
    }

    /// **Los cuatro del Note Repeater, escritos aparte** porque son lo que la
    /// rebanada 5 de la v2 pidió: CC 79, 80, 81 y 83, saltando el 82.
    func testTheNoteRepeaterKnobsAreSeventyNineToEightyThree() throws {
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(79))), .repeats)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(80))), .repeatTime)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(81))), .ramp)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(83))), .pace)
    }

    /// **El knob del Cycle no lo toca ningún parámetro**, esté donde esté. Se
    /// pregunta al mapeo en vez de escribir el número: el 2026-09-07 el test
    /// decía 82 y el 2026-09-12 dice 85, y lo que se comprueba no ha cambiado
    /// ninguna de las dos veces.
    func testNoParameterLandsOnTheCycleKnob() throws {
        let cycleKnob = try XCTUnwrap(mapping.editingCycleController)
        XCTAssertNil(mapping.parameter(for: cycleKnob))
        XCTAssertFalse(mapping.hasConflict)
    }

    /// **Las tres familias siguen sin pisarse.** Los knobs van del 70 al 85, los
    /// step buttons del 102 al 117 y los pads son notas: ningún CC de knob puede
    /// caer en el bloque de los botones.
    func testTheThreeFamiliesDoNotOverlap() {
        let numbers = mapping.declaredNumbers
        XCTAssertTrue(Set(numbers.knobs).isDisjoint(with: Set(numbers.stepButtons)))
        XCTAssertEqual(Set(numbers.knobs).count, 16)
        XCTAssertEqual(Set(numbers.stepButtons).count, 16)
    }

    /// **Con un `knobBlock` distinto, lo que se declara sigue al bloque.** Los
    /// dieciséis números y el knob del Cycle se recalculan; ninguno queda
    /// clavado al 70.
    ///
    /// > **Lo que NO sigue al bloque son las asignaciones**, y es anterior a esta
    /// > rebanada: `assignments` guarda CC absolutos para los trece parámetros,
    /// > no desplazamientos. Un mapeo con otro bloque hay que construirlo con sus
    /// > números. Los cuatro del Note Repeater entran con el mismo criterio que
    /// > los nueve de antes, así que esto no empeora — queda escrito para que
    /// > nadie lo lea como una promesa que el tipo no hace.
    func testTheDeclaredNumbersFollowTheKnobBlock() {
        let moved = ControlMapping(
            assignments: [.steps: 20], knobBlock: MIDIController(20)!)

        XCTAssertEqual(moved.declaredNumbers.knobs.first, 20)
        XCTAssertEqual(moved.declaredNumbers.knobs.last, 35)
        XCTAssertEqual(moved.editingCycleController?.number, 35)
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

    /// **Los dos restantes están declarados y sin asignar.** No es un olvido: su
    /// sitio es de v2 —Accent, Voicing, Range—, y hasta entonces girarlos no
    /// publica nada.
    ///
    /// > **Eran siete hasta el 2026-09-07.** Cuatro se los llevó el Note
    /// > Repeater y el quinto es el knob del Cycle en edición, que nunca fue
    /// > libre.
    func testTheLastTwoKnobsCarryNoParameter() throws {
        let knobs = mapping.declaredNumbers.knobs
        for number in knobs.suffix(2) {
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
        for number in mapping.declaredNumbers.knobs.suffix(2) {
            let controller = try XCTUnwrap(MIDIController(number))
            XCTAssertFalse(
                input.receive(
                    .controlChange(channel: MIDIChannel(1)!, controller: controller, value: 1)),
                "CC \(number)")
        }
    }

    // MARK: - El knob del Cycle en edición

    /// **El Cycle en edición vive en el knob 16, CC 85** desde el 2026-09-12.
    ///
    /// Estaba en el 13 (CC 82) desde el 2026-09-05, y antes en el 10 (CC 79),
    /// contiguo a los nueve parámetros. Aquella mudanza quería que dejara de
    /// parecer el décimo parámetro, y estando adyacente sólo lo conseguía a
    /// medias: seguía siendo el knob de al lado. En la esquina lo separan dos
    /// knobs libres, que es un hueco que la mano nota sin mirar.
    ///
    /// Lo que se comprueba sigue siendo lo de siempre: mueve *a cuál* de los
    /// parámetros se apunta, no un parámetro.
    func testTheEditingCycleKnobIsTheSixteenth() throws {
        XCTAssertEqual(mapping.editingCycleController?.number, 85)
        XCTAssertEqual(mapping.declaredNumbers.knobs[15], 85)
    }

    /// **El CC 82 deja de ser el knob del Cycle**, y en la Fase 2 pasa a ser
    /// Delay. Aquí sólo se comprueba que ya no apunta al cursor de edición.
    func testTheThirteenthKnobIsNoLongerTheCycleKnob() throws {
        XCTAssertNotEqual(mapping.editingCycleController?.number, 82)
    }

    /// **El CC 79 dejó de ser el knob del Cycle, y desde el 2026-09-07 es
    /// Repeats.** Quedó libre el 2026-09-05 al mover el Cycle al 82, y el Note
    /// Repeater lo ocupó: es el sitio que se le había dejado.
    func testTheTenthKnobIsRepeatsAndNotTheCycleKnob() throws {
        let seventyNine = try XCTUnwrap(MIDIController(79))
        XCTAssertEqual(mapping.parameter(for: seventyNine), .repeats)
        XCTAssertNotEqual(mapping.editingCycleController, seventyNine)

        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            publish: { _ in }
        )
        XCTAssertTrue(
            input.receive(
                .controlChange(channel: MIDIChannel(1)!, controller: seventyNine, value: 1)),
            "el knob 10 no movió Repeats")
    }

    /// **El número sigue al bloque, no está clavado al 82.** Es lo que separa un
    /// dato del mapeo de una constante repartida por el código: mover
    /// `knobBlock` mueve los dieciséis knobs a la vez, éste incluido.
    func testTheEditingCycleKnobFollowsItsBlock() throws {
        let moved = ControlMapping(
            assignments: [.steps: 20],
            knobBlock: try XCTUnwrap(MIDIController(20))
        )
        XCTAssertEqual(moved.editingCycleController?.number, 35)
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
