import Engine
import XCTest

@testable import MIDI

/// Tests de que los pads editan y muestran el pool base, no el que suena
/// (`pitch-harmony_20260912`, FR21).
///
/// **Un pad es un grado de la escala en un registro**, y lo que ilumina es si
/// esa altura está en el pool. Si iluminara lo que suena, con Pitch +2 un pad
/// encendido no quitaría la nota que se ve: pulsarlo quitaría otra.
final class PadsEditTheBasePoolTests: XCTestCase {

    private func input() -> ControlInput {
        ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: .major, root: Root(0)!),
            publish: { _ in }
        )
    }

    /// Con Pitch +2, el pad 1 sigue siendo C3 del pool base: está encendido y
    /// pulsarlo lo quita, aunque lo que suena sea E3.
    func testWithPitchActiveAPadTogglesTheBasePitch() throws {
        let input = input()
        input.receive(pad(0))
        input.receive(pad(2))
        input.receive(knob(.pitch, by: 2))

        let c3 = try XCTUnwrap(input.surface.pitch(at: 0))
        XCTAssertTrue(input.track.pool.contains(c3), "el pad 1 no está encendido")
        XCTAssertFalse(input.track.soundingPool.contains(c3), "el arreglo no transpone")

        XCTAssertTrue(input.receive(pad(0)))
        XCTAssertFalse(input.track.pool.contains(c3), "el pad no quitó su altura base")
        XCTAssertEqual(input.track.pool.count, 1)
    }

    /// Y lo que suena sigue la transposición del pool que queda.
    func testTheSoundingPoolFollowsTheEditedBase() throws {
        let input = input()
        input.receive(pad(0))
        input.receive(knob(.pitch, by: 2))
        input.receive(pad(2))

        let e3 = try XCTUnwrap(input.surface.pitch(at: 2))
        let g3 = try XCTUnwrap(input.surface.pitch(at: 4))
        XCTAssertTrue(input.track.pool.contains(e3))
        XCTAssertTrue(input.track.soundingPool.contains(g3), "E3 +2 grados es G3")
    }

    // MARK: - Helpers

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }

    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }
}
