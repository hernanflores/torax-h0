import Engine
import Foundation
import XCTest

@testable import MIDI

/// `Pattern` colisiona con el de ApplicationServices, como en el resto de la
/// suite.
private typealias Pattern = Engine.Pattern

/// Tests de que el mapeo deja de ser fijo.
///
/// **Es la costura que MIDI Learn necesita** (`spec.md`, FR2): hasta ahora
/// `ControlMapping` llegaba en el `init` y se quedaba ahí, así que reasignar un
/// control exigía construir otro `ControlInput` — y con él perder el Pattern que
/// estaba editando. Es el mismo error de forma que la adopción de Patterns ya
/// arregló para el material.
///
/// **Un mapeo no es material** (FR3). Cambiarlo cambia cómo se llega a las
/// notas, no las notas: ni un Cycle, ni el Track seleccionado, ni una
/// publicación.
final class MappingAdoptionTests: XCTestCase {

    /// Lo publicado, con el mismo candado que el resto de la suite: el cierre de
    /// publicación es `@Sendable`.
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

    // MARK: - A qué controlador responde cada destino (FR2)

    /// El caso que da nombre al track: **el mismo destino, otro knob**.
    func testAfterAdoptingAMappingTheNewControllerMovesTheParameter() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [.steps: 20]))

        XCTAssertTrue(input.receive(knob(MIDIController(20)!, by: 1)))
        XCTAssertEqual(input.track.shape.steps.count, 9)
    }

    /// Y la otra mitad, que es la que de verdad prueba que el mapeo se
    /// sustituyó: **el knob de antes deja de mover nada**.
    func testTheOldControllerStopsMovingTheParameter() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [.steps: 20]))

        XCTAssertFalse(input.receive(knob(MIDIController(70)!, by: 1)))
        XCTAssertEqual(input.track.shape.steps.count, 8)
    }

    /// Los pads y los step buttons viajan en el mismo mapeo, así que se mueven
    /// con él. Sin esto, aprender un knob dejaría las otras dos familias
    /// apuntando al preset viejo.
    func testThePadBlockMovesWithTheMapping() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [:], padBlock: MIDINote(60)!))

        XCTAssertNil(input.mapping.padIndex(for: MIDINote(36)!))
        XCTAssertEqual(input.mapping.padIndex(for: MIDINote(60)!), 0)
    }

    func testTheStepButtonBlockMovesWithTheMapping() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [:], stepButtonBlock: MIDIController(20)!))

        XCTAssertNil(input.mapping.stepButtonIndex(for: MIDIController(102)!))
        XCTAssertEqual(input.mapping.stepButtonIndex(for: MIDIController(20)!), 0)
    }

    // MARK: - Un mapeo no es material (FR3)

    func testAdoptingAMappingDoesNotTouchTheMaterial() {
        let input = makeInput()
        input.receive(knob(MIDIController(70)!, by: 3))
        let before = input.pattern

        input.adopt(mapping: .init(assignments: [.steps: 20]))

        XCTAssertEqual(input.pattern, before)
    }

    func testAdoptingAMappingKeepsTheSelectedTrack() {
        let input = makeInput()
        input.selectTrack(5)

        input.adopt(mapping: .init(assignments: [.steps: 20]))

        XCTAssertEqual(input.selectedTrackIndex, 5)
    }

    /// **No publica**, por la misma razón que adoptar un Pattern no publica: no
    /// ha cambiado nada de lo que el scheduler lee.
    func testAdoptingAMappingDoesNotPublish() {
        let published = Published()
        let input = makeInput(publish: { published.record($0) })

        input.adopt(mapping: .init(assignments: [.steps: 20]))

        XCTAssertEqual(published.count, 0)
    }

    // MARK: - Lo no asignado sigue siendo válido (FR5)

    /// Un mapeo que no asigna nada deja la app muda, y **eso no es un error**:
    /// es lo que `ControlMapping` ya declara para los controles sin asignar.
    func testAMappingThatAssignsNothingIsNotAnError() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [:]))

        XCTAssertFalse(input.receive(knob(MIDIController(70)!, by: 1)))
        XCTAssertEqual(input.track.shape.steps.count, 8)
    }

    /// La vuelta al preset de fábrica es adoptar el de fábrica: no hace falta un
    /// camino aparte (FR18 se apoya en esto).
    func testAdoptingTheFactoryPresetRestoresIt() {
        let input = makeInput()
        input.adopt(mapping: .init(assignments: [.steps: 20]))

        input.adopt(mapping: .beatStepPro)

        // **El knob se pregunta al preset.** Estaba escrito como el CC 70, que
        // era Steps hasta el 2026-09-12 y ahora es Velocity: el test habría
        // pasado a comprobar otro parámetro sin avisar.
        let stepsKnob = ControlMapping.beatStepPro.controller(for: .steps)!
        XCTAssertTrue(input.receive(knob(stepsKnob, by: 1)))
        XCTAssertEqual(input.track.shape.steps.count, 9)
    }

    /// **Y volver al de fábrica tampoco toca el material** (FR18). Es la mitad
    /// que importa de la vuelta atrás: deshacer lo aprendido no puede deshacer
    /// lo tocado.
    func testRestoringTheFactoryPresetDoesNotTouchTheMaterial() {
        let input = makeInput()
        input.receive(knob(MIDIController(70)!, by: 3))
        input.adopt(mapping: .init(assignments: [.steps: 20]))
        let before = input.pattern

        input.adopt(mapping: .beatStepPro)

        XCTAssertEqual(input.pattern, before)
        XCTAssertEqual(input.mapping, ControlMapping.beatStepPro)
    }

    // MARK: - El knob del Cycle sigue el bloque (FR2)

    /// El knob del Cycle no está en `assignments` —no es un `TrackParameter`—,
    /// sale del bloque de knobs más un desplazamiento. Así que mover el bloque
    /// lo mueve, y este test impide que alguien lo deje clavado en el 85.
    func testTheCycleKnobFollowsTheKnobBlock() {
        let input = makeInput()

        input.adopt(mapping: .init(assignments: [:], knobBlock: MIDIController(20)!))

        XCTAssertEqual(input.mapping.editingCycleController, MIDIController(27)!)
    }

    // MARK: -

    private func knob(_ controller: MIDIController, by delta: UInt8) -> MIDIMessage {
        .controlChange(channel: MIDIChannel(1)!, controller: controller, value: delta)
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
