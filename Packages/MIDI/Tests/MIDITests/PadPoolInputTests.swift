import Engine
import XCTest
@testable import MIDI

/// Tests de los pads editando el pool.
///
/// La Pre Spec: al pulsar PITCH, los 16 Value Buttons se comportan como teclado
/// cromático, «pero sólo están disponibles las notas permitidas por la Scale
/// actual. Una nota activada entra al pool; una desactivada se excluye».
final class PadPoolInputTests: XCTestCase {

    private let frame = TonalFrame(scale: .major, root: Root(0)!)

    // MARK: - Alternar

    func testAPadPutsThePitchIntoThePool() {
        let input = makeInput()
        XCTAssertTrue(input.receive(pad(60)))
        XCTAssertTrue(input.track.pool.contains(Pitch(60)!))
    }

    /// El mismo pad la mete y la saca: es un interruptor, no un acumulador.
    func testTheSamePadTakesThePitchBackOut() {
        let input = makeInput()
        input.receive(pad(60))
        XCTAssertTrue(input.receive(pad(60)))
        XCTAssertFalse(input.track.pool.contains(Pitch(60)!))
    }

    func testSeveralPadsBuildAPool() {
        let input = makeInput()
        for note in [60, 64, 67] { input.receive(pad(note)) }
        XCTAssertEqual(input.track.pool.count, 3)
    }

    // MARK: - Lo que se ignora

    /// **Una altura fuera del marco tonal se ignora en silencio.** Es el mismo
    /// criterio que un CC sin mapear: llegan mensajes de todo tipo en una sesión
    /// real, y no es asunto de la entrada quejarse de ellos.
    func testAPitchOutsideTheFrameIsIgnored() {
        let input = makeInput()
        XCTAssertFalse(input.receive(pad(61)), "Do# no está en Do mayor")
        XCTAssertTrue(input.track.pool.isEmpty)
    }

    /// **Los note-off no alternan.** Alternar en la pulsación y en la soltada
    /// sería no alternar: cada pad volvería a dejar el pool como estaba.
    func testNoteOffDoesNotToggle() {
        let input = makeInput()
        input.receive(pad(60))
        XCTAssertFalse(input.receive(release(60)))
        XCTAssertTrue(input.track.pool.contains(Pitch(60)!), "la soltada sacó la nota")
    }

    /// Un note-on con velocity cero es la convención de apagado de muchos
    /// controladores. Tampoco alterna.
    func testNoteOnWithZeroVelocityIsARelease() {
        let input = makeInput()
        input.receive(pad(60))
        XCTAssertFalse(input.receive(pad(60, velocity: 0)))
        XCTAssertTrue(input.track.pool.contains(Pitch(60)!))
    }

    /// Un pool lleno rechaza el noveno pad sin publicar ni destruir nada.
    func testAFullPoolIgnoresTheNinthPad() {
        let input = makeInput()
        // Ocho notas de Do mayor.
        for note in [60, 62, 64, 65, 67, 69, 71, 72] { input.receive(pad(note)) }
        XCTAssertEqual(input.track.pool.count, 8)

        XCTAssertFalse(input.receive(pad(74)))
        XCTAssertEqual(input.track.pool.count, 8)
    }

    // MARK: - El pool y el Shape conviven

    /// **Girar un knob no puede borrar el pool.** Son dos partes del mismo
    /// Track y se editan por el mismo camino; perder una al tocar la otra sería
    /// destruir material.
    func testTurningAKnobKeepsThePool() {
        let input = makeInput()
        input.receive(pad(60))
        input.receive(pad(64))

        // CC 71 es Pulses en el mapeo provisional.
        input.receive(
            .controlChange(channel: MIDIChannel(1)!, controller: MIDIController(71)!, value: 1))

        XCTAssertEqual(input.track.pool.count, 2, "el pool se perdió al girar")
        XCTAssertTrue(input.track.pool.contains(Pitch(60)!))
    }

    /// Y al revés: editar el pool no puede tocar el Shape.
    func testEditingThePoolKeepsTheShape() {
        let input = makeInput()
        let before = input.track.shape
        input.receive(pad(67))
        XCTAssertEqual(input.track.shape, before)
    }

    // MARK: - Publicación

    func testEveryAcceptedPadPublishesTheTrack() {
        let handoff = TrackHandoff(Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)))
        let input = ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame,
            publishingTo: handoff
        )

        XCTAssertTrue(input.receive(pad(60)))
        XCTAssertFalse(input.receive(pad(61)), "fuera de marco: no publica")
        XCTAssertTrue(input.receive(pad(64)))

        XCTAssertEqual(handoff.load()?.pool.count, 2)
    }

    // MARK: - Helpers

    private func makeInput() -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame,
            publish: { _ in }
        )
    }

    private func pad(_ note: Int, velocity: Int = 100) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(note)!,
            velocity: MIDIVelocity(velocity)!
        )
    }

    private func release(_ note: Int) -> MIDIMessage {
        .noteOff(channel: MIDIChannel(1)!, note: MIDINote(note)!, velocity: MIDIVelocity(0)!)
    }
}
