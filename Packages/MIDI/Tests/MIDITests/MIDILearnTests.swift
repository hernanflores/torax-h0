import Engine
import Foundation
import XCTest

@testable import MIDI

/// `Pattern` colisiona con el de ApplicationServices, como en el resto de la
/// suite.
private typealias Pattern = Engine.Pattern

/// Tests de aprender: qué control físico mueve qué destino.
///
/// **Se aprende destino a destino** (FR6). Se elige el destino, se mueve el
/// control, y ese control queda asignado. No hay recorrido guiado de los
/// cuarenta y ocho: aprender uno es el gesto, y repetirlo es el recorrido.
///
/// **Mientras se aprende no se edita** (FR10). Aprender girando el knob de Steps
/// no puede además cambiar Steps: el mensaje asigna y ahí se acaba.
final class MIDILearnTests: XCTestCase {

    /// Lo publicado, con el mismo candado que el resto de la suite.
    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private var patterns: [Pattern] = []

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return patterns.count
        }

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }
    }

    // MARK: - Entrar y salir (FR6, FR9)

    func testNothingIsBeingLearnedToStartWith() {
        XCTAssertNil(makeInput().learning)
    }

    func testBeginningToLearnNamesTheTarget() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))

        XCTAssertEqual(input.learning, .parameter(.steps))
    }

    /// **Cancelar deja el mapeo como estaba** (FR9). Es lo que permite
    /// equivocarse de destino sin consecuencias.
    func testCancellingLeavesTheMappingUntouched() {
        let input = makeInput()
        let before = input.mapping

        input.beginLearning(.parameter(.steps))
        input.cancelLearning()

        XCTAssertNil(input.learning)
        XCTAssertEqual(input.mapping, before)
    }

    /// Elegir otro destino sin haber aprendido nada es cambiar de idea, no un
    /// error: manda el último.
    func testChoosingAnotherTargetReplacesTheFirst() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.beginLearning(.parameter(.pulses))

        XCTAssertEqual(input.learning, .parameter(.pulses))
    }

    // MARK: - Aprender un knob (FR7)

    func testTurningAKnobWhileLearningAssignsIt() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(input.mapping.controller(for: .steps), MIDIController(20)!)
    }

    /// **Asignar termina el aprendizaje.** Un destino, un gesto.
    func testAssigningEndsTheLearning() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertNil(input.learning)
    }

    /// **Mientras se aprende no se edita** (FR10). El fallo que esto impide es
    /// el más fácil de cometer: aprender el knob de Steps girándolo y encontrar
    /// Steps movido.
    func testLearningDoesNotMoveTheParameter() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .steps)!, by: 1))

        XCTAssertEqual(input.track.shape.steps.count, 8)
    }

    func testLearningDoesNotPublish() {
        let published = Published()
        let input = makeInput(publish: { published.record($0) })

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(published.count, 0)
    }

    /// El mensaje que asigna **sí se consume**: no es un mensaje que no hizo
    /// nada, hizo lo único que se le pedía.
    func testTheAssigningMessageIsConsumed() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))

        XCTAssertTrue(input.receive(knob(MIDIController(20)!, by: 1)))
    }

    // MARK: - Un giro es una asignación (FR8)

    /// **Girar es más de un mensaje.** Sin esto, un giro de tres clics
    /// aprendería tres veces — y las dos últimas sobre destinos que nadie
    /// eligió.
    func testASingleTurnAssignsOnce() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))
        input.beginLearning(.parameter(.pulses))
        input.receive(knob(MIDIController(21)!, by: 1))

        XCTAssertEqual(input.mapping.controller(for: .steps), MIDIController(20)!)
        XCTAssertEqual(input.mapping.controller(for: .pulses), MIDIController(21)!)
    }

    /// **Y los clics que sobran del giro no editan.** Asignar termina el
    /// aprendizaje, así que sin esta regla el resto del giro caería sobre el
    /// parámetro recién asignado y lo movería — el mismo salto de valor que FR10
    /// evita durante el aprendizaje, un instante después.
    func testTheRestOfTheTurnDoesNotEditTheJustLearnedControl() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))
        input.receive(knob(MIDIController(20)!, by: 1))
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(input.track.shape.steps.count, 8)
    }

    /// **Y el silencio se levanta con el control siguiente.** Si no, el knob
    /// recién aprendido quedaría mudo para siempre, que es peor que el salto que
    /// se estaba evitando.
    func testAnotherControlEndsTheSilence() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(20)!, by: 1))
        input.receive(knob(MIDIController(20)!, by: 1))
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .pulses)!, by: 1))
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(input.track.shape.steps.count, 9)
    }

    // MARK: - Las otras dos familias (FR7)

    /// Los pads son notas, y aprender el primero mueve el bloque entero: los
    /// dieciséis van seguidos desde él, como en el preset.
    func testLearningThePadBlockTakesTheNote() {
        let input = makeInput()

        input.beginLearning(.padBlock)
        input.receive(pad(MIDINote(60)!))

        XCTAssertEqual(input.mapping.padBlock, MIDINote(60)!)
        XCTAssertEqual(input.mapping.padIndex(for: MIDINote(60)!), 0)
    }

    func testLearningThePadBlockDoesNotTouchThePool() {
        let input = makeInput()
        let before = input.pattern

        input.beginLearning(.padBlock)
        input.receive(pad(MIDINote(60)!))

        XCTAssertEqual(input.pattern, before)
    }

    func testLearningTheStepButtonBlockTakesTheController() {
        let input = makeInput()

        input.beginLearning(.stepButtonBlock)
        input.receive(knob(MIDIController(20)!, by: 127))

        XCTAssertEqual(input.mapping.stepButtonBlock, MIDIController(20)!)
    }

    /// El bloque de knobs se aprende igual, y con él se mueve el knob del Cycle,
    /// que sale del bloque más un desplazamiento.
    func testLearningTheKnobBlockMovesTheCycleKnobWithIt() {
        let input = makeInput()

        input.beginLearning(.knobBlock)
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(input.mapping.knobBlock, MIDIController(20)!)
        XCTAssertEqual(input.mapping.editingCycleController, MIDIController(32)!)
    }

    // MARK: - Un control no puede significar dos cosas

    /// **El fallo encontrado en dispositivo el 2026-09-09.** Se aprendió uno de
    /// los tres bloques con un knob, el bloque de step buttons aterrizó encima de
    /// los CC de los knobs, y desde entonces **cada giro cambiaba de Track**: el
    /// despacho mira los step buttons antes que los knobs.
    ///
    /// Se guardaba con la sesión, así que sobrevivía a relanzar la app. La única
    /// salida era el botón de fábrica.
    func testLearningAnOverlappingStepButtonBlockIsRefused() {
        let input = makeInput()
        let before = input.mapping

        input.beginLearning(.stepButtonBlock)
        let consumed = input.receive(
            knob(ControlMapping.beatStepPro.controller(for: .steps)!, by: 1))

        XCTAssertFalse(consumed)
        XCTAssertEqual(input.mapping, before)
    }

    /// **Rechazar no es cancelar**: el destino sigue esperando al control
    /// correcto. Obligar a volver a elegirlo castigaría al usuario por un gesto
    /// que la app ya sabía que no podía aceptar.
    func testARefusedLearningStaysOpen() {
        let input = makeInput()

        input.beginLearning(.stepButtonBlock)
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .steps)!, by: 1))

        XCTAssertEqual(input.learning, .stepButtonBlock)
    }

    /// Y el control que se rechazó **sigue haciendo lo suyo**: no se queda mudo
    /// por haber sido candidato.
    func testTheRefusedControlKeepsWorking() {
        let input = makeInput()

        input.beginLearning(.stepButtonBlock)
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .steps)!, by: 1))
        input.cancelLearning()
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .steps)!, by: 1))

        XCTAssertEqual(input.track.shape.steps.count, 9)
    }

    /// El bloque de knobs encima del de step buttons, por el otro lado.
    func testLearningAnOverlappingKnobBlockIsRefused() {
        let input = makeInput()
        let before = input.mapping

        input.beginLearning(.knobBlock)
        input.receive(knob(MIDIController(102)!, by: 1))

        XCTAssertEqual(input.mapping, before)
    }

    /// **Un parámetro sobre un CC de step button, también.** No hay bloque que
    /// se mueva, y el síntoma es el mismo: ese knob cambiaría de Track en vez de
    /// mover el parámetro.
    func testLearningAParameterOnAStepButtonControllerIsRefused() {
        let input = makeInput()
        let before = input.mapping

        input.beginLearning(.parameter(.steps))
        input.receive(knob(MIDIController(102)!, by: 1))

        XCTAssertEqual(input.mapping, before)
        XCTAssertEqual(input.learning, .parameter(.steps))
    }

    /// Un bloque que no choca sí se acepta: el arreglo no puede impedir aprender.
    func testANonOverlappingBlockIsStillLearned() {
        let input = makeInput()

        input.beginLearning(.stepButtonBlock)
        input.receive(knob(MIDIController(20)!, by: 127))

        XCTAssertEqual(input.mapping.stepButtonBlock, MIDIController(20)!)
        XCTAssertNil(input.learning)
    }

    // MARK: - Lo que no vale para aprender

    /// Un pad no puede aprender un knob: son familias distintas y el número no
    /// significa lo mismo. El mensaje no asigna y **el aprendizaje sigue
    /// abierto**, esperando al control correcto.
    func testANoteDoesNotAssignAKnob() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(pad(MIDINote(60)!))

        XCTAssertEqual(input.learning, .parameter(.steps))
        XCTAssertEqual(input.mapping.controller(for: .steps), MIDIController(70)!)
    }

    func testAControlChangeDoesNotAssignThePadBlock() {
        let input = makeInput()

        input.beginLearning(.padBlock)
        input.receive(knob(MIDIController(20)!, by: 1))

        XCTAssertEqual(input.learning, .padBlock)
        XCTAssertEqual(input.mapping.padBlock, ControlMapping.defaultPadBlock)
    }

    /// El reloj del controlador llega por el mismo cable. No es un control que
    /// nadie pueda querer aprender, y no puede robar la asignación.
    func testTheClockDoesNotAssignAnything() {
        let input = makeInput()

        input.beginLearning(.parameter(.steps))
        input.receive(.timingClock)

        XCTAssertEqual(input.learning, .parameter(.steps))
    }

    // MARK: -

    private func knob(_ controller: MIDIController, by delta: UInt8) -> MIDIMessage {
        .controlChange(channel: MIDIChannel(1)!, controller: controller, value: delta)
    }

    private func pad(_ note: MIDINote) -> MIDIMessage {
        .noteOn(channel: MIDIChannel(1)!, note: note, velocity: MIDIVelocity(100)!)
    }

    private func makeInput(
        publish: @escaping @Sendable (Pattern) -> Void = { _ in }
    ) -> ControlInput {
        ControlInput(
            pattern: Pattern().replacing(
                Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!)), at: 0),
            publish: publish
        )
    }
}
