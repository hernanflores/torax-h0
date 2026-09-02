import Engine
import XCTest
@testable import MIDI

/// Tests de los pads editando el pool.
///
/// La Pre Spec: «Una nota activada entra al pool; una desactivada se excluye».
/// Lo que cambió en la rebanada 7 es **de dónde sale la nota**: el pad es un
/// índice y la altura la pone la superficie, así que aquí se pulsa el pad 1, no
/// la nota 60. El comportamiento del pool —alternar, capacidad 8, qué no
/// alterna— es el mismo y estos tests son los de antes adaptados, no otros.
final class PadPoolInputTests: XCTestCase {

    private let frame = TonalFrame(scale: .major, root: Root(0)!)

    // MARK: - Alternar

    func testAPadPutsThePitchIntoThePool() {
        let input = makeInput()
        XCTAssertTrue(input.receive(pad(0)))
        XCTAssertTrue(input.track.pool.contains(Pitch(48)!), "el pad 1 es el grado 1 en C2")
    }

    /// El mismo pad la mete y la saca: es un interruptor, no un acumulador.
    func testTheSamePadTakesThePitchBackOut() {
        let input = makeInput()
        input.receive(pad(0))
        XCTAssertTrue(input.receive(pad(0)))
        XCTAssertFalse(input.track.pool.contains(Pitch(48)!))
    }

    func testSeveralPadsBuildAPool() {
        let input = makeInput()
        for index in [0, 2, 4] { input.receive(pad(index)) }
        XCTAssertEqual(input.track.pool.count, 3)
    }

    // MARK: - Lo que se ignora

    /// **El caso que desapareció.** Ya no existe «una altura fuera del marco
    /// tonal»: toda altura de la superficie sale de la escala, así que no queda
    /// nada que filtrar. Lo que se comprueba en su lugar es que eso sea cierto —
    /// sobre las cinco escalas y los doce Roots.
    func testEveryPitchAPadCanAddIsAllowedByTheFrame() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                // Los pads de octava mueven la superficie y no meten nada:
                // aquí se miran los catorce que sí pueden. Uno por input, que
                // el pool solo tiene ocho sitios.
                for index in 0..<16
                where index != PadSurface.octaveDownIndex && index != PadSurface.octaveUpIndex {
                    let input = makeInput(frame: frame)
                    guard let expected = input.surface.pitch(at: index) else {
                        XCTAssertFalse(input.receive(pad(index)), "\(scale)·\(rootValue)·\(index)")
                        continue
                    }
                    XCTAssertTrue(input.receive(pad(index)), "\(scale)·\(rootValue)·\(index)")
                    XCTAssertTrue(
                        input.track.pool.contains(expected), "\(scale)·\(rootValue)·\(index)")
                    XCTAssertTrue(frame.allows(expected), "\(scale)·\(rootValue)·\(index)")
                }
            }
        }
    }

    /// **Un pad sin altura asignada no publica nada.** Con `pentatonic` los
    /// pads 6, 7, 14 y 15 no tienen grado; los 8 y 16 no tienen altura por
    /// definición. Mismo criterio que un CC sin asignar: no es un error.
    func testAPadWithNoPitchPublishesNothing() {
        let input = makeInput(frame: TonalFrame(scale: .pentatonic, root: Root(0)!))
        for index in [5, 6, 13, 14] {
            XCTAssertFalse(input.receive(pad(index)), "pad \(index + 1) con pentatónica")
        }
        XCTAssertTrue(input.track.pool.isEmpty)
    }

    /// Una nota fuera del bloque de pads no es un pad: no publica nada.
    func testANoteOutsideThePadBlockPublishesNothing() {
        let input = makeInput()
        for number in [0, 35, 52, 127] {
            XCTAssertFalse(input.receive(note(number)), "nota \(number)")
        }
        XCTAssertTrue(input.track.pool.isEmpty)
    }

    /// **Los note-off no alternan.** Alternar en la pulsación y en la soltada
    /// sería no alternar: cada pad volvería a dejar el pool como estaba.
    func testNoteOffDoesNotToggle() {
        let input = makeInput()
        input.receive(pad(0))
        XCTAssertFalse(input.receive(release(0)))
        XCTAssertTrue(input.track.pool.contains(Pitch(48)!), "la soltada sacó la nota")
    }

    /// Un note-on con velocity cero es la convención de apagado de muchos
    /// controladores. Tampoco alterna.
    func testNoteOnWithZeroVelocityIsARelease() {
        let input = makeInput()
        input.receive(pad(0))
        XCTAssertFalse(input.receive(pad(0, velocity: 0)))
        XCTAssertTrue(input.track.pool.contains(Pitch(48)!))
    }

    /// Un pool lleno rechaza el noveno pad sin publicar ni destruir nada.
    func testAFullPoolIgnoresTheNinthPad() {
        let input = makeInput()
        // Los siete grados de la octava base y el primero de la de encima.
        for index in [0, 1, 2, 3, 4, 5, 6, 8] { input.receive(pad(index)) }
        XCTAssertEqual(input.track.pool.count, 8)

        XCTAssertFalse(input.receive(pad(9)))
        XCTAssertEqual(input.track.pool.count, 8)
    }

    // MARK: - El pool y el Shape conviven

    /// **Girar un knob no puede borrar el pool.** Son dos partes del mismo
    /// Track y se editan por el mismo camino; perder una al tocar la otra sería
    /// destruir material.
    func testTurningAKnobKeepsThePool() {
        let input = makeInput()
        input.receive(pad(0))
        input.receive(pad(2))

        // CC 71 es Pulses en el mapeo provisional.
        input.receive(
            .controlChange(channel: MIDIChannel(1)!, controller: MIDIController(71)!, value: 1))

        XCTAssertEqual(input.track.pool.count, 2, "el pool se perdió al girar")
        XCTAssertTrue(input.track.pool.contains(Pitch(48)!))
    }

    /// Y al revés: editar el pool no puede tocar el Shape.
    func testEditingThePoolKeepsTheShape() {
        let input = makeInput()
        let before = input.track.shape
        input.receive(pad(4))
        XCTAssertEqual(input.track.shape, before)
    }

    // MARK: - Publicación

    func testEveryAcceptedPadPublishesTheTrack() {
        let handoff = PatternHandoff(Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)))
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame,
            publishingTo: handoff
        )

        XCTAssertTrue(input.receive(pad(0)))
        XCTAssertFalse(input.receive(note(35)), "fuera del bloque: no publica")
        XCTAssertTrue(input.receive(pad(2)))

        XCTAssertEqual(handoff.load()?.track(at: 0)?.pool.count, 2)
    }

    // MARK: - Helpers

    private func makeInput(frame: TonalFrame? = nil) -> ControlInput {
        ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame ?? self.frame,
            publish: { _ in }
        )
    }

    /// El pad `index` —0 es el primero—, no la nota `index`.
    private func pad(_ index: Int, velocity: Int = 100) -> MIDIMessage {
        note(Int(ControlMapping.defaultPadBlock.value) + index, velocity: velocity)
    }

    private func note(_ number: Int, velocity: Int = 100) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(number)!,
            velocity: MIDIVelocity(velocity)!
        )
    }

    private func release(_ index: Int) -> MIDIMessage {
        .noteOff(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(0)!
        )
    }
}
