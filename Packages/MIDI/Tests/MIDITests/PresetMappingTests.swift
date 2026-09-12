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
            // La fila de arriba, que son los CC 78-85: el card Shape entero.
            78: .steps, 79: .pulses, 80: .rotate, 81: .division,
            82: .repeats, 83: .repeatTime, 84: .ramp, 85: .pace,
            // La de abajo, que son los CC 70-77: el card Groove.
            70: .velocity, 71: .sustain, 72: .probability, 73: .timing, 74: .delay,
            // Tonal cierra la fila de abajo (`pitch-harmony_20260912`).
            75: .pitch,
        ]
        for (number, parameter) in expected {
            XCTAssertEqual(mapping.controller(for: parameter)?.number, number, "\(parameter)")
        }
        XCTAssertEqual(expected.count, TrackParameter.allCases.count, "falta algún parámetro")
    }

    /// **Los cuatro del Note Repeater cierran la fila de arriba**, en los CC 82
    /// a 85, justo detrás de los cuatro del ritmo. Es la segunda línea del card
    /// Shape (FR15) puesta bajo la mano.
    ///
    /// > **Estaban en los CC 79, 80, 81 y 83 hasta el 2026-09-12**, salteando el
    /// > 82 porque ahí vivía el knob del Cycle. Ahora ese hueco no existe: los
    /// > ocho de la fila son los ocho de Shape, sin saltos.
    func testTheNoteRepeaterKnobsCloseTheTopRow() throws {
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(82))), .repeats)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(83))), .repeatTime)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(84))), .ramp)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(85))), .pace)
    }

    /// **La fila de arriba es el card Shape y la de abajo el card Groove.** Es
    /// la regla entera de `knob-layout_20260912`, escrita como lo que se puede
    /// comprobar: qué ocho CC son de una familia y qué cinco de la otra.
    ///
    /// **Los CC de la fila de arriba son los 78-85 y los de abajo los 70-77.**
    /// No es un despiste: `Torax.beatsteppro` asigna los controlId 32-39 -la
    /// fila de arriba- al 78-85, y los 40-47 -la de abajo- al 70-77. Se verificó
    /// en dispositivo el 2026-09-12, después de que una premisa contraria
    /// dejara el knob del Cycle en la esquina que no era.
    func testEachKnobRowCarriesOneScreenCard() throws {
        let topRow = 78...85
        let bottomRow = 70...77

        for number in topRow {
            let parameter = try XCTUnwrap(
                mapping.parameter(for: try XCTUnwrap(MIDIController(number))),
                "CC \(number) no mueve nada")
            XCTAssertEqual(parameter.family, .shape, "CC \(number) es \(parameter)")
        }

        // **Desde el 2026-09-12 la fila de abajo termina en Tonal**
        // (`pitch-harmony_20260912`): los cinco de Groove y, detrás, en los
        // knobs que quedaban libres, los de Tonal. La regla de una fila por card
        // se cumple a medias y es una decisión, no un descuido: no hay una
        // tercera fila.
        let bottom = bottomRow.compactMap {
            mapping.parameter(for: MIDIController($0)!)
        }
        XCTAssertEqual(
            bottom.filter { $0.family == .groove }.count, 5,
            "la fila de abajo no lleva los cinco de Groove")
        XCTAssertEqual(
            bottom.map(\.family), [.groove, .groove, .groove, .groove, .groove, .tonal],
            "Tonal no va detrás de Groove")
    }

    /// Y dentro de cada fila, el orden es el de la pantalla.
    func testEachRowFollowsTheOrderOfItsCard() throws {
        let shapeRhythm: [TrackParameter] = [.steps, .pulses, .rotate, .division]
        let noteRepeater: [TrackParameter] = [.repeats, .repeatTime, .ramp, .pace]
        let groove: [TrackParameter] = [.velocity, .sustain, .probability, .timing, .delay]

        for (offset, parameter) in (shapeRhythm + noteRepeater).enumerated() {
            XCTAssertEqual(
                mapping.controller(for: parameter)?.number, 78 + offset, "\(parameter)")
        }
        for (offset, parameter) in groove.enumerated() {
            XCTAssertEqual(
                mapping.controller(for: parameter)?.number, 70 + offset, "\(parameter)")
        }
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
        XCTAssertEqual(moved.editingCycleController?.number, 27)
    }

    /// **El intercambio del 2026-09-05 se deshizo el 2026-09-12.** Delay y
    /// Probability se habían cruzado para que la fila de knobs no siguiera al
    /// orden de la pantalla; ahora lo sigue, así que Groove va en el orden del
    /// dominio y el cruce desaparece.
    func testGrooveIsNoLongerCrossed() throws {
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(72))), .probability)
        XCTAssertEqual(mapping.parameter(for: try XCTUnwrap(MIDIController(74))), .delay)
    }

    /// **Los dos restantes están declarados y sin asignar.** No es un olvido: su
    /// sitio es de v2 —Accent, Voicing, Range—, y hasta entonces girarlos no
    /// publica nada.
    ///
    /// > **Eran siete hasta el 2026-09-07.** Cuatro se los llevó el Note
    /// > Repeater y el quinto es el knob del Cycle en edición, que nunca fue
    /// > libre.
    ///
    /// > **Ya no son los dos últimos del bloque, y por eso se buscan.** Esto
    /// > decía `knobs.suffix(2)`, que valía mientras los libres cerraran la
    /// > numeración. Desde el 2026-09-12 son los CC 75 y 76, en medio de la fila
    /// > de abajo: lo que define a un knob libre es no tener dueño, no estar al
    /// > final.
    private var freeKnobs: [Int] {
        mapping.declaredNumbers.knobs.filter {
            mapping.parameter(for: MIDIController($0)!) == nil
                && mapping.editingCycleController?.number != $0
        }
    }

    /// **Uno desde el 2026-09-12**: Pitch ocupa el 75 y el 76 espera a Harmony.
    func testOneKnobCarriesNoParameter() throws {
        XCTAssertEqual(freeKnobs, [76])
        for number in freeKnobs {
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
        for number in freeKnobs {
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
        XCTAssertEqual(mapping.editingCycleController?.number, 77)
    }

    /// **Los knobs 14 y 15, CC 75 y 76, son de Tonal.** Estaban libres entre
    /// Delay y la esquina desde `knob-layout_20260912`; Pitch ocupa el 75
    /// (`pitch-harmony_20260912`) y el 76 sigue libre hasta que entre Harmony.
    /// Ninguno es el knob del Cycle.
    func testTheKnobsBetweenGrooveAndTheCornerAreTonal() throws {
        let seventyFive = try XCTUnwrap(MIDIController(75))
        XCTAssertEqual(mapping.parameter(for: seventyFive), .pitch)

        let seventySix = try XCTUnwrap(MIDIController(76))
        XCTAssertNil(mapping.parameter(for: seventySix))

        for controller in [seventyFive, seventySix] {
            XCTAssertNotEqual(mapping.editingCycleController, controller)
        }
    }

    /// **El CC 79 no es el knob del Cycle, y desde el 2026-09-12 es Pulses.**
    /// Lo fue hasta el 2026-09-05, y entre esa fecha y el 2026-09-12 fue
    /// Repeats. Lo que el test comprueba no ha cambiado en ninguna de las tres:
    /// que mueve un parámetro y no el cursor.
    func testTheSeventyNineMovesAParameterAndNotTheCycle() throws {
        let seventyNine = try XCTUnwrap(MIDIController(79))
        XCTAssertEqual(mapping.parameter(for: seventyNine), .pulses)
        XCTAssertNotEqual(mapping.editingCycleController, seventyNine)

        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            publish: { _ in }
        )
        XCTAssertTrue(
            input.receive(
                .controlChange(channel: MIDIChannel(1)!, controller: seventyNine, value: 1)),
            "el CC 79 no movió Pulses")
    }

    /// **El número sigue al bloque, no está clavado al 82.** Es lo que separa un
    /// dato del mapeo de una constante repartida por el código: mover
    /// `knobBlock` mueve los dieciséis knobs a la vez, éste incluido.
    func testTheEditingCycleKnobFollowsItsBlock() throws {
        let moved = ControlMapping(
            assignments: [.steps: 20],
            knobBlock: try XCTUnwrap(MIDIController(20))
        )
        XCTAssertEqual(moved.editingCycleController?.number, 27)
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
