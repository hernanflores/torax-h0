import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de lo que Temp silencia mientras está hundido (FR6).
///
/// **El hold acota qué controles están vivos.** Con el step 13 hundido solo
/// responden los nueve knobs de parámetro; la selección de Track, los gestos de
/// mezcla, el knob del Cycle en edición y los dieciséis pads se ignoran **en
/// silencio**, con el mismo criterio que un CC sin asignar.
///
/// **No es una restricción por gusto.** Un fill se hace con una mano en el step
/// 13 y la otra en los knobs, encima de un controlador cuyos pads y step buttons
/// están al lado: un roce cambiaría de Track o metería una nota en el pool, y no
/// hay deshacer. Lo que Temp promete es que soltar devuelve exactamente lo que
/// había, y eso solo es cierto si nada más pudo escribir mientras tanto.
final class TempTakesOverInputTests: XCTestCase {

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

        input.receive(tempModifier())
        XCTAssertFalse(input.receive(stepButton(7)))

        XCTAssertEqual(input.selectedTrackIndex, 4, "Temp hundido dejó cambiar de Track")
    }

    // MARK: - Los gestos de mezcla

    /// Los modificadores 15 y 16 no publican gesto con Temp hundido.
    func testTheMixModifiersProduceNoGesture() {
        let (input, gestures) = makeInput()

        input.receive(tempModifier())
        input.receive(stepButton(ControlInput.muteModifierIndex))
        XCTAssertFalse(input.receive(stepButton(3)))

        XCTAssertTrue(gestures.recorded.isEmpty, "Temp hundido dejó pasar un mute")
    }

    /// Y lo mismo con el de solo.
    func testTheSoloModifierProducesNoGestureEither() {
        let (input, gestures) = makeInput()

        input.receive(tempModifier())
        input.receive(stepButton(ControlInput.soloModifierIndex))
        XCTAssertFalse(input.receive(stepButton(3)))

        XCTAssertTrue(gestures.recorded.isEmpty)
    }

    // MARK: - El knob del Cycle en edición

    /// El knob 10 no mueve el Cycle en edición con Temp hundido.
    ///
    /// **Es el que más importa de los cuatro.** El overlay calcula su valor
    /// absoluto desde el Cycle en edición; moverlo a media superposición
    /// cambiaría el punto de partida con el fill ya puesto, y lo que se
    /// restaurara al soltar ya no sería lo que había.
    func testTheEditingCycleKnobDoesNotMove() {
        let (input, _) = makeInput()
        input.setActiveCycleCount(4)

        input.receive(tempModifier())
        XCTAssertFalse(input.receive(editingCycleKnob(by: 2)))

        XCTAssertEqual(
            input.pattern.track(at: 0)?.editing, 0, "Temp hundido dejó mover el Cycle en edición")
    }

    // MARK: - Los pads

    /// Ningún pad toca el pool.
    func testNoPadTouchesThePool() {
        let (input, _) = makeInput()
        let pool = input.track.pool

        input.receive(tempModifier())
        for index in 0..<16 {
            XCTAssertFalse(
                input.receive(pad(index)), "el pad \(index + 1) publicó con Temp hundido")
        }

        XCTAssertEqual(input.track.pool, pool, "Temp hundido dejó tocar el pool")
    }

    /// Ni los de octava mueven el registro.
    func testTheOctavePadsDoNotMoveTheRegister() {
        let (input, _) = makeInput()
        let shift = input.track.padOctaveShift

        input.receive(tempModifier())
        input.receive(pad(PadSurface.octaveUpIndex))
        input.receive(pad(PadSurface.octaveDownIndex))

        XCTAssertEqual(input.track.padOctaveShift, shift)
    }

    // MARK: - Se ignoran, no fallan

    /// **Ninguno de los mensajes ignorados publica.** Se ignoran como un CC sin
    /// asignar, no como un error: en una sesión real llegan mensajes de todo
    /// tipo y esto no es distinto.
    func testNoneOfTheIgnoredMessagesPublishes() {
        let published = Published()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)),
            publish: published.record,
            mix: { _ in }
        )

        input.receive(tempModifier())
        input.receive(stepButton(7))
        input.receive(editingCycleKnob(by: 2))
        input.receive(pad(0))
        input.receive(pad(PadSurface.octaveUpIndex))

        XCTAssertTrue(published.patterns.isEmpty, "un mensaje ignorado publicó")
    }

    // MARK: - Al soltar, todos vuelven

    /// **Al soltar Temp, los cuatro vuelven a responder.** Es lo que hace de
    /// esto un modificador y no un modo: no queda nada encendido.
    func testReleasingTempGivesTheFourControlsBack() {
        let (input, gestures) = makeInput()
        input.setActiveCycleCount(4)

        input.receive(tempModifier())
        input.receive(tempModifier(value: 0))

        XCTAssertTrue(input.receive(stepButton(7)), "la selección no volvió")
        XCTAssertEqual(input.selectedTrackIndex, 7)

        XCTAssertTrue(input.receive(pad(0)), "los pads no volvieron")

        input.selectTrack(0)
        XCTAssertTrue(input.receive(editingCycleKnob(by: 2)), "el knob del Cycle no volvió")

        input.receive(stepButton(ControlInput.muteModifierIndex))
        XCTAssertTrue(input.receive(stepButton(3)), "los gestos de mezcla no volvieron")
        XCTAssertEqual(gestures.recorded, [.mute(3)])
    }

    /// Los knobs de parámetro **sí** responden durante el hold: son los únicos
    /// que Temp deja vivos, y sin ellos el gesto no serviría de nada.
    func testTheParameterKnobsDoRespondDuringTheHold() {
        let (input, _) = makeInput()

        input.receive(tempModifier())

        XCTAssertTrue(input.receive(knob(.pulses, by: 2)))
    }

    // MARK: - Helpers

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }
    }

    private func makeInput() -> (ControlInput, Gestures) {
        let gestures = Gestures()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
                pool: PitchPool().inserting(Pitch(48)!)
            ),
            publish: { _ in },
            mix: gestures.record
        )
        return (input, gestures)
    }

    private func tempModifier(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
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
