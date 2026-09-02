import Engine
import XCTest
@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de la edición sobre el Track seleccionado.
///
/// **Seleccionar no es un modo, es elegir a quién escuchan los controles.** Lo
/// que estos tests fijan es la mitad que se olvida: no que el seleccionado
/// cambie, sino que **los otros once no**.
final class SelectedTrackEditingTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    private func input(_ pattern: Pattern = Pattern.initial) -> ControlInput {
        ControlInput(
            pattern: pattern,
            frame: TonalFrame(scale: .major, root: Root(0)!),
            publish: { _ in }
        )
    }

    private func knob(_ parameter: TrackParameter, delta: Int = 1) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: mapping.controller(for: parameter)!,
            value: UInt8(delta > 0 ? delta : 128 + delta)
        )
    }

    private func stepButton(_ index: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(mapping.stepButtonBlock.number + index)!,
            value: 127
        )
    }

    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }

    // MARK: - Los step buttons seleccionan, hasta donde hay Tracks

    func testEveryStepButtonWithATrackSelectsIt() {
        let input = input()

        // El primero ya está seleccionado: seleccionarlo no publica, porque no
        // cambia nada. No es un caso especial del step button 1, es la regla.
        XCTAssertFalse(input.receive(stepButton(0)))
        XCTAssertEqual(input.selectedTrackIndex, 0)

        for index in 1..<Pattern.trackCount {
            XCTAssertTrue(input.receive(stepButton(index)), "step button \(index + 1)")
            XCTAssertEqual(input.selectedTrackIndex, index)
        }
    }

    /// **Los step buttons sin Track no seleccionan** (FR3).
    ///
    /// El BeatStep Pro tiene dieciséis y la app tiene doce Tracks, así que del 13
    /// al 16 sobran. No publican y no rompen: es el mismo criterio que un CC sin
    /// asignar o un pad fuera de la superficie, y por eso la acotación vive en
    /// quien selecciona y no en `ControlMapping`, que describe el hardware y
    /// sigue declarando los dieciséis.
    func testStepButtonsBeyondTheLastTrackSelectNothing() {
        let input = input()
        input.receive(stepButton(Pattern.trackCount - 1))
        let before = input.pattern

        for index in Pattern.trackCount..<ControlMapping.controlsPerFamily {
            XCTAssertFalse(input.receive(stepButton(index)), "step button \(index + 1)")
            XCTAssertEqual(
                input.selectedTrackIndex, Pattern.trackCount - 1,
                "el step button \(index + 1) movió la selección")
            XCTAssertEqual(input.pattern, before, "el step button \(index + 1) tocó el material")
        }
    }

    // MARK: - Girar un knob mueve el seleccionado y solo ése

    func testTurningAKnobMovesOnlyTheSelectedTrack() {
        // **El Track de prueba está lejos de los extremos a propósito.** Con los
        // valores por defecto, Steps y Probability ya están en su tope y girar
        // hacia arriba no mueve nada: el test pasaba por la razón equivocada
        // —el giro «cambiaba» el Track porque le perdía el canal, que es el
        // defecto del 2026-08-31—.
        let midRange = Cycle(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
            pool: PitchPool().inserting(Pitch(60)!),
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!
            ),
            channel: Channel(8)!
        )

        for parameter in TrackParameter.allCases {
            let input = input(Pattern.initial.replacing(midRange, at: 7))
            input.receive(stepButton(7))
            let before = input.pattern

            XCTAssertTrue(input.receive(knob(parameter)), "\(parameter)")

            XCTAssertNotEqual(
                input.pattern.cycle(at: 7), before.cycle(at: 7), "\(parameter) no movió el Track 8")
            XCTAssertEqual(
                input.pattern.cycle(at: 7)?.channel, Channel(8)!,
                "\(parameter) perdió el canal del Track 8")
            for other in 0..<Pattern.trackCount where other != 7 {
                XCTAssertEqual(
                    input.pattern.cycle(at: other), before.cycle(at: other),
                    "\(parameter) tocó el Track \(other + 1)")
            }
        }
    }

    // MARK: - Un pad edita el pool del seleccionado

    func testAPadEditsThePoolOfTheSelectedTrack() {
        let input = input()
        input.receive(stepButton(3))
        let before = input.pattern

        XCTAssertTrue(input.receive(pad(0)))
        XCTAssertTrue(input.pattern.cycle(at: 3)!.pool.contains(Pitch(48)!))
        for other in 0..<Pattern.trackCount where other != 3 {
            XCTAssertEqual(
                input.pattern.cycle(at: other), before.cycle(at: other),
                "el pad tocó el Track \(other + 1)")
        }
    }

    // MARK: - Volver deja el Track como estaba

    /// **Seleccionar otro Track no cambia nada del que se deja.** Es la promesa
    /// que hace usable el conjunto: se edita uno, se pasa a otro, y al volver
    /// está como se dejó.
    func testComingBackFindsTheTrackAsItWasLeft() {
        let input = input()

        // Se edita el Track 1: dos parámetros y una nota.
        input.receive(knob(.pulses))
        input.receive(knob(.velocity))
        input.receive(pad(2))
        let edited = input.pattern.cycle(at: 0)

        // Se pasa por otros tres Tracks, editando de paso.
        for index in [5, 9, 11] {
            input.receive(stepButton(index))
            input.receive(knob(.steps))
            input.receive(pad(1))
        }

        input.receive(stepButton(0))
        XCTAssertEqual(input.pattern.cycle(at: 0), edited, "el Track 1 cambió mientras no miraba")
        XCTAssertEqual(input.track, edited, "seleccionar no devolvió el Track editado")
    }

    /// Y lo editado en los otros tampoco se pierde.
    func testEveryEditedTrackKeepsItsOwn() {
        let input = input()

        for index in 0..<Pattern.trackCount {
            input.receive(stepButton(index))
            for _ in 0...index { input.receive(knob(.pulses)) }
        }

        for index in 0..<Pattern.trackCount {
            let initial = Pattern.initial.cycle(at: index)!.shape
            // Pulses se frena en Steps: girar más allá del extremo no envuelve.
            let expected = min(initial.pulses.count + index + 1, initial.steps.count)
            XCTAssertEqual(
                input.pattern.cycle(at: index)?.shape.pulses.count, expected, "Track \(index + 1)")
        }
    }

    // MARK: - El marco tonal es del Track

    /// **Dos Tracks en tonalidades distintas conviven.** Es lo que hacía
    /// imposible el marco global de la v1: un bajo en menor bajo un arpegio en
    /// mayor.
    func testTwoTracksCanBeInDifferentKeys() {
        let input = input()

        input.setFrame(TonalFrame(scale: .major, root: Root(0)!))
        input.receive(stepButton(1))
        input.setFrame(TonalFrame(scale: .phrygian, root: Root(7)!))

        XCTAssertEqual(input.pattern.cycle(at: 0)?.frame.scale, .major)
        XCTAssertEqual(input.pattern.cycle(at: 1)?.frame.scale, .phrygian)
        XCTAssertEqual(input.pattern.cycle(at: 1)?.frame.root, Root(7)!)
    }

    /// Cambiar la Scale de uno no reencuadra el pool del otro.
    func testChangingOneKeyDoesNotReframeAnotherTrackPool() {
        let input = input()

        input.setFrame(TonalFrame(scale: .major, root: Root(0)!))
        input.receive(pad(1))  // el grado 2 de Do mayor: Re
        let untouched = input.pattern.cycle(at: 0)

        input.receive(stepButton(6))
        input.setFrame(TonalFrame(scale: .phrygian, root: Root(1)!))

        XCTAssertEqual(input.pattern.cycle(at: 0), untouched, "reencuadró el pool del vecino")
    }

    /// **Al seleccionar, la superficie se recalcula con el marco y el registro
    /// de ese Track.** Volver a uno y encontrarlo dos octavas más abajo sería
    /// perder trabajo.
    func testTheSurfaceFollowsTheSelectedTrack() {
        let input = input()

        input.setFrame(TonalFrame(scale: .major, root: Root(0)!))
        input.receive(padOctaveUp())
        input.receive(padOctaveUp())
        let raised = input.surface

        input.receive(stepButton(2))
        input.setFrame(TonalFrame(scale: .pentatonic, root: Root(2)!))
        XCTAssertEqual(input.surface.frame.scale, .pentatonic)
        XCTAssertEqual(input.surface.octaveShift, 0, "heredó el registro del Track anterior")

        input.receive(stepButton(0))
        XCTAssertEqual(input.surface, raised, "no devolvió la superficie del Track 1")
    }

    private func padOctaveUp() -> MIDIMessage { pad(PadSurface.octaveUpIndex) }

    // MARK: - El canal se edita, y no con un knob

    /// **Ningún CC mueve el canal.** Es configuración, no material generativo, y
    /// `product-guidelines.md` pone esa frontera del lado táctil, donde ya están
    /// Scale y Root.
    func testNoControllerChangesTheChannel() throws {
        let input = input()
        let before = (0..<Pattern.trackCount).map { input.pattern.cycle(at: $0)!.channel }

        for number in 0...127 {
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!,
                    controller: try XCTUnwrap(MIDIController(number)),
                    value: 1
                ))
        }

        XCTAssertEqual((0..<Pattern.trackCount).map { input.pattern.cycle(at: $0)!.channel }, before)
    }

    /// Cambiar el canal publica: el scheduler lo usa en el evento siguiente.
    func testChangingTheChannelPublishes() {
        let handoff = PatternHandoff(Pattern.initial)
        let input = ControlInput(pattern: Pattern.initial, publishingTo: handoff)
        input.receive(stepButton(2))

        XCTAssertTrue(input.setChannel(Channel(12)!))
        XCTAssertEqual(handoff.load()?.cycle(at: 2)?.channel, Channel(12)!)
    }

    /// Y fijar el canal que ya tenía no publica: no cambia nada.
    func testSettingTheSameChannelDoesNotPublish() {
        let input = input()
        XCTAssertFalse(input.setChannel(input.track.channel))
    }

    /// Cambiar el canal de uno no toca el de los otros once.
    func testChangingTheChannelLeavesTheOthersAlone() {
        let input = input()
        input.receive(stepButton(9))
        let before = input.pattern

        XCTAssertTrue(input.setChannel(Channel(3)!))
        for other in 0..<Pattern.trackCount where other != 9 {
            XCTAssertEqual(
                input.pattern.cycle(at: other), before.cycle(at: other), "Track \(other + 1)")
        }
    }

    // MARK: - El canal de cualquier Track, no solo del elegido

    /// **La pantalla MIDI edita los doce, no el seleccionado** (FR6).
    ///
    /// Es la diferencia con `setChannel(_:)`: aquel edita el Track elegido,
    /// porque vivía pegado a la fila de selección. La pantalla MIDI enseña el
    /// ruteo entero, así que tiene que poder tocar cualquier fila sin cambiar
    /// antes de Track — cambiar la selección para ajustar un canal movería
    /// también a dónde apuntan los knobs, que es un efecto que nadie pidió.
    func testTheChannelOfAnyTrackCanBeSet() {
        let input = input()

        // **El 16 a propósito.** Con doce Tracks ninguno lo trae de fábrica, así
        // que los doce cambian de verdad; con un canal del 1 al 12, el Track que
        // ya lo tuviera devolvería `false` por no cambiar nada y el test estaría
        // midiendo esa coincidencia en vez de la función.
        let unused = Channel(16)!

        for index in 0..<Pattern.trackCount {
            XCTAssertTrue(input.setChannel(unused, forTrack: index), "Track \(index + 1)")
            XCTAssertEqual(
                input.pattern.cycle(at: index)?.channel, unused, "Track \(index + 1)")
        }
    }

    /// Y no mueve la selección: los knobs siguen apuntando a donde apuntaban.
    func testSettingAnotherTracksChannelDoesNotChangeTheSelection() {
        let input = input()
        input.receive(stepButton(2))

        XCTAssertTrue(input.setChannel(Channel(7)!, forTrack: 9))
        XCTAssertEqual(input.selectedTrackIndex, 2)
        XCTAssertEqual(input.pattern.cycle(at: 9)?.channel, Channel(7)!)
    }

    /// Cambiar el de uno no toca a los demás, ni su canal ni su material.
    func testSettingOneChannelLeavesEveryOtherTrackAlone() {
        let input = input()
        let before = input.pattern

        XCTAssertTrue(input.setChannel(Channel(16)!, forTrack: 5))
        for other in 0..<Pattern.trackCount where other != 5 {
            XCTAssertEqual(
                input.pattern.cycle(at: other), before.cycle(at: other), "Track \(other + 1)")
        }
    }

    /// Fijar el que ya tenía no publica: no cambia nada.
    func testSettingTheChannelATrackAlreadyHasDoesNotPublish() {
        let input = input()
        XCTAssertFalse(input.setChannel(Channel(4)!, forTrack: 3), "el Track 4 ya emite por el 4")
    }

    /// Un índice fuera de los doce no publica y no rompe — mismo criterio que un
    /// CC sin asignar o un step button sin Track.
    func testSettingTheChannelOfATrackThatDoesNotExistChangesNothing() {
        let input = input()
        let before = input.pattern

        for index in [-1, Pattern.trackCount, Pattern.trackCount + 3, Int.max] {
            XCTAssertFalse(input.setChannel(Channel(9)!, forTrack: index), "\(index)")
            XCTAssertEqual(input.pattern, before, "\(index)")
        }
    }

    /// **Dos Tracks pueden compartir canal.** Dos capas rítmicas sobre el mismo
    /// sinte es un caso real, y la pantalla MIDI existe en parte para verlo — no
    /// para impedirlo.
    func testTwoTracksCanShareAChannelFromTheMidiScreen() {
        let input = input()

        XCTAssertTrue(input.setChannel(Channel(1)!, forTrack: 4))
        XCTAssertEqual(input.pattern.cycle(at: 0)?.channel, Channel(1)!)
        XCTAssertEqual(input.pattern.cycle(at: 4)?.channel, Channel(1)!)
    }

    /// Y lo que se publica sigue siendo el Pattern entero.
    func testSettingAnotherTracksChannelPublishesThePattern() {
        let handoff = PatternHandoff(Pattern.initial)
        let input = ControlInput(pattern: Pattern.initial, publishingTo: handoff)

        XCTAssertTrue(input.setChannel(Channel(11)!, forTrack: 8))
        XCTAssertEqual(handoff.load()?.cycle(at: 8)?.channel, Channel(11)!)
    }

    // MARK: - Publicar

    /// Lo que se publica son los doce, no el editado suelto: el scheduler
    /// necesita el conjunto.
    func testWhatGetsPublishedIsTheWholePattern() {
        let handoff = PatternHandoff(Pattern.initial)
        let input = ControlInput(pattern: Pattern.initial, publishingTo: handoff)

        input.receive(stepButton(4))
        XCTAssertTrue(input.receive(knob(.pulses)))

        let published = handoff.load()
        XCTAssertEqual(published?.cycle(at: 4), input.pattern.cycle(at: 4))
        XCTAssertEqual(published?.cycle(at: 0), Pattern.initial.cycle(at: 0), "perdió el Track 1")
    }
}
