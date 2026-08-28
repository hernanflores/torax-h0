import Engine
import XCTest
@testable import MIDI

/// Tests del cambio de marco tonal con el pool ya poblado.
///
/// `product-guidelines.md`, regla de destructividad: «el pool tonal sobrevive a
/// un cambio de Scale reencuadrándose, no vaciándose».
final class FrameChangeTests: XCTestCase {

    func testChangingTheScaleReframesThePoolInsteadOfClearingIt() {
        let input = makeInput(scale: .major, root: 0)
        for note in [60, 62, 64] { input.receive(pad(note)) }
        XCTAssertEqual(input.track.pool.count, 3)

        input.setFrame(TonalFrame(scale: .minor, root: Root(0)!))

        XCTAssertFalse(input.track.pool.isEmpty, "el pool se vació")
        for index in 0..<input.track.pool.count {
            XCTAssertTrue(input.frame.allows(input.track.pool.pitch(at: index)!))
        }
    }

    func testChangingTheRootReframesToo() {
        let input = makeInput(scale: .major, root: 0)
        for note in [60, 64, 67] { input.receive(pad(note)) }

        input.setFrame(TonalFrame(scale: .major, root: Root(6)!))

        for index in 0..<input.track.pool.count {
            XCTAssertTrue(input.frame.allows(input.track.pool.pitch(at: index)!))
        }
    }

    /// Cambiar el marco no toca el Shape: son capas distintas del motor.
    func testChangingTheFrameKeepsTheShape() {
        let input = makeInput(scale: .major, root: 0)
        input.receive(pad(61 + 1))
        let before = input.track.shape

        input.setFrame(TonalFrame(scale: .phrygian, root: Root(3)!))
        XCTAssertEqual(input.track.shape, before)
    }

    /// Si el pool ya cabía en el marco nuevo no se publica nada: mandar un
    /// snapshot idéntico es trabajo y ruido para nada.
    func testAFrameThatChangesNothingDoesNotPublish() {
        let input = makeInput(scale: .major, root: 0)
        input.receive(pad(60))  // Do está en Do mayor y en Do menor
        XCTAssertFalse(input.setFrame(TonalFrame(scale: .minor, root: Root(0)!)))
    }

    /// Tras cambiar el marco, los pads admiten las notas nuevas y rechazan las
    /// que se salieron.
    func testThePadsFollowTheNewFrame() {
        let input = makeInput(scale: .major, root: 0)
        XCTAssertFalse(input.receive(pad(61)), "Do# no está en Do mayor")

        input.setFrame(TonalFrame(scale: .phrygian, root: Root(0)!))
        XCTAssertTrue(input.receive(pad(61)), "Do# sí está en Do frigio")
    }

    // MARK: - Helpers

    private func makeInput(scale: Scale, root: Int) -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: scale, root: Root(root)!),
            publish: { _ in }
        )
    }

    private func pad(_ note: Int) -> MIDIMessage {
        .noteOn(channel: MIDIChannel(1)!, note: MIDINote(note)!, velocity: MIDIVelocity(100)!)
    }
}
