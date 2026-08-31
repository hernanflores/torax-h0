import Engine
import XCTest
@testable import MIDI

/// Tests de los step buttons seleccionando Track.
///
/// **Se implementa la semántica final —step button N selecciona el Track N— con
/// un solo Track detrás.** Es lo que evita que el preset haya que reescribirlo
/// en v2: los números del controlador ya significan lo correcto, y lo único que
/// falta después es que haya Tracks.
final class StepButtonInputTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    // MARK: - Seleccionar

    /// **La semántica final: el step button N selecciona el Track N.** En v1 no
    /// hay Tracks detrás, así que se comprueba con un `ControlInput` que declara
    /// varios — el mismo camino que usará v2 cuando los haya.
    func testStepButtonNSelectsTrackN() {
        let input = makeInput(trackCount: 4)
        XCTAssertEqual(input.selectedTrackIndex, 0)

        XCTAssertTrue(input.receive(stepButton(2)))
        XCTAssertEqual(input.selectedTrackIndex, 2)

        XCTAssertTrue(input.receive(stepButton(1)))
        XCTAssertEqual(input.selectedTrackIndex, 1)
    }

    /// Volver a seleccionar el Track vigente no publica: nada cambió.
    func testSelectingTheCurrentTrackAgainPublishesNothing() {
        let input = makeInput(trackCount: 4)
        input.receive(stepButton(3))
        XCTAssertFalse(input.receive(stepButton(3)))
        XCTAssertEqual(input.selectedTrackIndex, 3)
    }

    /// Un step button sin Track detrás no mueve la selección.
    func testAStepButtonWithNoTrackBehindItLeavesTheSelectionAlone() {
        let input = makeInput(trackCount: 4)
        input.receive(stepButton(2))

        XCTAssertFalse(input.receive(stepButton(9)))
        XCTAssertEqual(input.selectedTrackIndex, 2)
    }

    /// **Seleccionar el único Track que hay es una operación sin efecto, no un
    /// reinicio.** El Track vigente —Shape, pool y Groove— sobrevive intacto.
    func testTheFirstStepButtonDoesNotDestroyTheCurrentTrack() {
        let input = makeInput()
        XCTAssertEqual(input.selectedTrackIndex, 0)
        input.receive(pad(0))
        input.receive(pad(2))
        let before = input.track

        XCTAssertFalse(input.receive(stepButton(0)), "seleccionar el Track vigente no publica")
        XCTAssertEqual(input.track, before)
    }

    /// **En v1 solo el primero corresponde a un Track existente.** Los otros
    /// quince no publican nada y no rompen el estado: la semántica está, los
    /// Tracks no.
    func testTheOtherFifteenPublishNothingAndBreakNothing() {
        let input = makeInput()
        input.receive(pad(0))
        let before = input.track

        for index in 1..<16 {
            XCTAssertFalse(input.receive(stepButton(index)), "step button \(index + 1)")
            XCTAssertEqual(input.track, before, "step button \(index + 1) tocó el Track")
            XCTAssertEqual(input.selectedTrackIndex, 0, "step button \(index + 1)")
        }
    }

    /// La soltada no hace nada — mismo criterio que el note-off de un pad.
    func testTheReleaseDoesNothing() {
        let input = makeInput()
        let before = input.track
        XCTAssertFalse(input.receive(stepButton(0, value: 0)))
        XCTAssertEqual(input.track, before)
    }

    /// Un step button no se confunde con un knob: no mueve ningún parámetro.
    func testAStepButtonMovesNoParameter() {
        let input = makeInput()
        let before = input.track
        for index in 0..<16 { input.receive(stepButton(index)) }
        XCTAssertEqual(input.track, before, "un step button movió un parámetro")
    }

    /// Ni toca la superficie de pads.
    func testAStepButtonLeavesTheSurfaceAlone() {
        let input = makeInput()
        input.receive(pad(15))
        let surface = input.surface

        for index in 0..<16 { input.receive(stepButton(index)) }
        XCTAssertEqual(input.surface, surface)
    }

    // MARK: - Helpers

    private func makeInput(trackCount: Int = 1) -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: .major, root: Root(0)!),
            publish: { _ in },
            trackCount: trackCount
        )
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
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }
}
