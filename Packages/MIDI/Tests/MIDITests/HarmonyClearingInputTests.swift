import Engine
import XCTest

@testable import MIDI

/// Tests de la limpieza de Harmony vista desde la entrada
/// (`pitch-harmony_20260912`, FR13, AC 9).
///
/// La regla vive en `Engine` —`Cycle.togglingPitch(_:)` y
/// `Cycle.reframed(to:)`— y aquí se comprueba que los dos caminos que editan
/// material la usan: el pad y el cambio de marco. Los pads de octava mueven la
/// superficie y no el material, así que no limpian.
final class HarmonyClearingInputTests: XCTestCase {

    /// Un pool de tres, Pitch +1 y dos clics de Harmony.
    private func movedInput() -> ControlInput {
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: .major, root: Root(0)!),
            publish: { _ in }
        )
        for index in [0, 2, 4] { input.receive(pad(index)) }
        input.receive(knob(.pitch, by: 1))
        input.receive(knob(.harmony, by: 2))
        XCTAssertFalse(input.track.harmony.isClean, "el arreglo no movió Harmony")
        return input
    }

    func testAPadThatEditsThePoolClearsHarmonyAndKeepsPitch() {
        let input = movedInput()
        XCTAssertTrue(input.receive(pad(6)))

        XCTAssertEqual(input.track.harmony, .clean)
        XCTAssertEqual(input.track.pitchOffset, PitchOffset(1))
    }

    func testChangingTheFrameClearsHarmonyAndKeepsPitch() {
        let input = movedInput()
        input.setFrame(TonalFrame(scale: .dorian, root: Root(2)!))

        XCTAssertEqual(input.track.harmony, .clean)
        XCTAssertEqual(input.track.pitchOffset, PitchOffset(1))
    }

    /// Las octavas de los pads no son material.
    func testTheOctavePadsKeepHarmony() {
        let input = movedInput()
        let harmony = input.track.harmony

        input.receive(pad(PadSurface.octaveUpIndex))
        input.receive(pad(PadSurface.octaveDownIndex))

        XCTAssertEqual(input.track.harmony, harmony)
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
