import Engine
import XCTest
@testable import MIDI

/// El barrido: **nada fuera de los bloques declarados publica, y nada revienta**.
///
/// En una sesión real llegan mensajes de todo tipo —otro secuenciador en la
/// misma red, un teclado, el reloj de otro cacharro—. Que se ignoren en silencio
/// es una decisión del preset (NFR7), no un descuido, y esto la prueba entera en
/// vez de caso a caso.
final class UnassignedInputTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    /// Los 128 CC sobre un `ControlInput` recién construido: solo publican los
    /// que el preset declara.
    func testOnlyDeclaredControllersPublish() throws {
        let declared = Set(
            mapping.declaredNumbers.knobs.prefix(TrackParameter.allCases.count)
                + mapping.declaredNumbers.stepButtons)

        for number in 0...127 {
            let input = makeInput()
            let controller = try XCTUnwrap(MIDIController(number))
            let published = input.receive(
                .controlChange(channel: MIDIChannel(1)!, controller: controller, value: 1))

            if !declared.contains(number) {
                XCTAssertFalse(published, "CC \(number) publicó sin estar declarado")
                XCTAssertEqual(input.track, makeInput().track, "CC \(number) tocó el Track")
            }
        }
    }

    /// Las 128 notas: solo publican los pads con altura asignada y los dos de
    /// octava.
    func testOnlyDeclaredNotesPublish() throws {
        let pads = Set(mapping.declaredNumbers.pads)

        for number in 0...127 {
            let input = makeInput()
            let note = try XCTUnwrap(MIDINote(number))
            let published = input.receive(
                .noteOn(channel: MIDIChannel(1)!, note: note, velocity: MIDIVelocity(100)!))

            if !pads.contains(number) {
                XCTAssertFalse(published, "nota \(number) publicó sin ser un pad")
                XCTAssertTrue(input.track.pool.isEmpty, "nota \(number) tocó el pool")
            }
        }
    }

    /// Y los 128 note-off, que no alternan nunca.
    func testNoNoteOffPublishes() throws {
        for number in 0...127 {
            let input = makeInput()
            let note = try XCTUnwrap(MIDINote(number))
            XCTAssertFalse(
                input.receive(
                    .noteOff(channel: MIDIChannel(1)!, note: note, velocity: MIDIVelocity(0)!)),
                "nota \(number)")
        }
    }

    /// **El canal no se filtra, y es una decisión escrita.** El mismo mensaje en
    /// dos canales distintos hace lo mismo: el BeatStep Pro puede estar en
    /// cualquiera, y exigir uno concreto sería un modo de fallo silencioso —todo
    /// conectado, nada responde— sin ninguna ventaja.
    func testTheChannelIsNotFiltered() throws {
        for channel in 1...16 {
            let input = makeInput()
            let message = MIDIMessage.noteOn(
                channel: try XCTUnwrap(MIDIChannel(channel)),
                note: try XCTUnwrap(MIDINote(Int(mapping.padBlock.value))),
                velocity: MIDIVelocity(100)!
            )
            XCTAssertTrue(input.receive(message), "canal \(channel)")
            XCTAssertTrue(input.track.pool.contains(Pitch(48)!), "canal \(channel)")
        }
    }

    /// El mismo CC en dos canales mueve el mismo parámetro.
    func testTheSameControllerInTwoChannelsDoesTheSameThing() throws {
        let controller = try XCTUnwrap(mapping.controller(for: .pulses))

        let first = makeInput()
        first.receive(.controlChange(channel: MIDIChannel(1)!, controller: controller, value: 1))

        let second = makeInput()
        second.receive(.controlChange(channel: MIDIChannel(16)!, controller: controller, value: 1))

        XCTAssertEqual(first.track, second.track)
    }

    // MARK: - Helpers

    private func makeInput() -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: .major, root: Root(0)!),
            publish: { _ in }
        )
    }
}
