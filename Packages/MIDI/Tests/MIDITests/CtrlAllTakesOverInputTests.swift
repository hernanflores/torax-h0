import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de lo que Ctrl All silencia mientras está hundido (FR10).
///
/// **El hold acota qué controles están vivos.** Con el step 14 hundido solo
/// responden los nueve knobs de parámetro; la selección de Track, los gestos de
/// mezcla, el knob del Cycle en edición y los dieciséis pads se ignoran **en
/// silencio**, con el mismo criterio que un CC sin asignar.
///
/// **Es el mismo corte que el de Temp y por la misma razón**, con una diferencia
/// de escala: lo que un roce estropearía aquí no es un fill sobre un Track sino
/// un desplazamiento sobre los doce, y sigue sin haber deshacer. Lo que Ctrl All
/// promete es que soltar devuelve exactamente lo que había, y eso solo es cierto
/// si nada más pudo escribir mientras tanto.
final class CtrlAllTakesOverInputTests: XCTestCase {

    private final class Gestures: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var recorded: [MixGesture] = []

        func record(_ gesture: MixGesture) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(gesture)
        }
    }

    // MARK: - La selección de Track

    /// Un step button 1–12 no cambia el Track seleccionado.
    func testAStepButtonDoesNotMoveTheSelection() {
        let (input, _) = makeInput()
        input.receive(stepButton(4))
        XCTAssertEqual(input.selectedTrackIndex, 4)

        input.receive(ctrlAll())
        XCTAssertFalse(input.receive(stepButton(7)))

        XCTAssertEqual(input.selectedTrackIndex, 4, "Ctrl All hundido dejó cambiar de Track")
    }

    // MARK: - Los gestos de mezcla

    /// Los modificadores de mute y solo no publican gesto con Ctrl All hundido.
    func testTheMixModifiersDoNotFireAGesture() {
        let (input, gestures) = makeInput()

        input.receive(ctrlAll())
        input.receive(stepButton(ControlInput.muteModifierIndex))
        XCTAssertFalse(input.receive(stepButton(3)))
        input.receive(stepButton(ControlInput.soloModifierIndex))
        XCTAssertFalse(input.receive(stepButton(5)))

        XCTAssertTrue(gestures.recorded.isEmpty, "salió un gesto de mezcla con Ctrl All hundido")
    }

    /// Y tampoco quedan hundidos por dentro: soltar Ctrl All no deja un mute
    /// armado que dispare al siguiente step button.
    func testTheMixModifiersAreNotLatchedByTheIgnoredPresses() {
        let (input, gestures) = makeInput()

        input.receive(ctrlAll())
        input.receive(stepButton(ControlInput.muteModifierIndex))
        input.receive(ctrlAll(value: 0))

        input.receive(stepButton(3))

        XCTAssertTrue(
            gestures.recorded.isEmpty,
            "el modificador de mute quedó armado desde dentro del hold")
        XCTAssertEqual(input.selectedTrackIndex, 3, "el step button no volvió a seleccionar")
    }

    // MARK: - El knob del Cycle en edición

    /// El knob del Cycle no mueve el cursor de edición.
    ///
    /// **Y aquí la razón es más fuerte que en Temp.** Allí movía el punto de
    /// partida del valor absoluto; aquí movería el Cycle sobre el que la pantalla
    /// enseña el desplazamiento, con el gesto puesto en los doce Tracks.
    func testTheEditingCycleKnobDoesNotMove() {
        let (input, _) = makeInput()
        input.setActiveCycleCount(4)
        let editing = input.pattern.track(at: 0)!.editing

        input.receive(ctrlAll())
        XCTAssertFalse(input.receive(editingCycleKnob(by: 1)))

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, editing)
    }

    // MARK: - Los pads

    /// Los dieciséis pads no tocan el pool.
    func testThePadsDoNotTouchThePool() {
        let (input, _) = makeInput()
        let pool = input.track.pool

        input.receive(ctrlAll())
        for index in 0..<ControlMapping.controlsPerFamily {
            XCTAssertFalse(input.receive(pad(index)), "el pad \(index + 1) publicó")
        }

        XCTAssertEqual(input.track.pool, pool, "un pad tocó el pool con Ctrl All hundido")
    }

    // MARK: - Lo que sí responde

    /// **Los knobs de parámetro responden, y son los únicos.** Un corte que
    /// silenciara también los knobs dejaría el gesto sin gesto.
    func testTheParameterKnobsAreTheOnlyThingAlive() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())

        for parameter in TrackParameter.allCases {
            XCTAssertTrue(
                input.receive(knob(parameter, by: 1)), "\(parameter) no respondió")
        }
    }

    // MARK: - Fuera del hold todo vuelve

    /// Soltar el 14 devuelve la entrada a la normalidad: el corte dura lo que
    /// dura el hold y no deja nada apagado.
    func testEverythingWorksAgainAfterReleasing() {
        let (input, gestures) = makeInput()

        input.receive(ctrlAll())
        input.receive(ctrlAll(value: 0))

        XCTAssertTrue(input.receive(stepButton(7)))
        XCTAssertEqual(input.selectedTrackIndex, 7)

        input.receive(stepButton(ControlInput.muteModifierIndex))
        XCTAssertTrue(input.receive(stepButton(3)))
        XCTAssertEqual(gestures.recorded.count, 1)
        input.receive(stepButton(ControlInput.muteModifierIndex, value: 0))

        XCTAssertTrue(input.receive(pad(0)))
    }

    // MARK: - Helpers

    /// **El Cycle de prueba tiene los nueve parámetros en el interior de su
    /// rango**, y no es un detalle cosmético: por defecto Steps está en 16,
    /// Probability en 100 y Timing en 50, que son sus extremos. Contra un extremo
    /// un giro no cambia nada y no publica, así que
    /// `testTheParameterKnobsAreTheOnlyThingAlive` habría leído «el knob está
    /// silenciado» donde en realidad decía «este valor ya no puede subir».
    private func makeInput() -> (ControlInput, Gestures) {
        let gestures = Gestures()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48)!),
                groove: Groove(
                    velocity: Velocity(64)!,
                    sustain: Sustain(percent: 100)!,
                    probability: Probability(percent: 50)!,
                    timing: Timing(percent: 60)!,
                    delay: Delay(percent: 0)!
                )
            ),
            publish: { _ in },
            mix: gestures.record
        )
        return (input, gestures)
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.ctrlAllModifierIndex, value: value)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }

    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.beatStepPro.padBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }

    private func editingCycleKnob(by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.editingCycleController!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }
}
