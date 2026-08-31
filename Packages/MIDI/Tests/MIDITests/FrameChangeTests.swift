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
        for index in [0, 1, 2] { input.receive(pad(index)) }
        XCTAssertEqual(input.track.pool.count, 3)

        input.setFrame(TonalFrame(scale: .minor, root: Root(0)!))

        XCTAssertFalse(input.track.pool.isEmpty, "el pool se vació")
        for index in 0..<input.track.pool.count {
            XCTAssertTrue(input.frame.allows(input.track.pool.pitch(at: index)!))
        }
    }

    func testChangingTheRootReframesToo() {
        let input = makeInput(scale: .major, root: 0)
        for index in [0, 2, 4] { input.receive(pad(index)) }

        input.setFrame(TonalFrame(scale: .major, root: Root(6)!))

        for index in 0..<input.track.pool.count {
            XCTAssertTrue(input.frame.allows(input.track.pool.pitch(at: index)!))
        }
    }

    /// Cambiar el marco no toca el Shape: son capas distintas del motor.
    func testChangingTheFrameKeepsTheShape() {
        let input = makeInput(scale: .major, root: 0)
        input.receive(pad(1))
        let before = input.track.shape

        input.setFrame(TonalFrame(scale: .phrygian, root: Root(3)!))
        XCTAssertEqual(input.track.shape, before)
    }

    /// Si el pool ya cabía en el marco nuevo no se publica nada: mandar un
    /// snapshot idéntico es trabajo y ruido para nada.
    func testAFrameThatChangesNothingDoesNotPublish() {
        let input = makeInput(scale: .major, root: 0)
        input.receive(pad(0))  // el pad 1 da Do, que está en Do mayor y en Do menor
        XCTAssertFalse(input.setFrame(TonalFrame(scale: .minor, root: Root(0)!)))
    }

    /// **Tras cambiar el marco, el mismo pad da otra nota.** Ya no hay pads que
    /// se acepten o se rechacen según la escala: el pad 2 es el grado 2, y el
    /// grado 2 de Do mayor es Re y el de Do frigio es Do#.
    func testThePadsFollowTheNewFrame() {
        let input = makeInput(scale: .major, root: 0)
        XCTAssertTrue(input.receive(pad(1)))
        XCTAssertTrue(input.track.pool.contains(Pitch(50)!), "grado 2 de Do mayor")

        input.setFrame(TonalFrame(scale: .phrygian, root: Root(0)!))
        XCTAssertEqual(input.surface.pitch(at: 1)?.value, 49, "grado 2 de Do frigio")

        // Sobre un input limpio, para no alternar la nota que el reencuadre ya
        // movió: pulsar el pad 2 mete el grado 2 del marco nuevo.
        let fresh = makeInput(scale: .phrygian, root: 0)
        XCTAssertTrue(fresh.receive(pad(1)))
        XCTAssertTrue(fresh.track.pool.contains(Pitch(49)!))
    }

    // MARK: - Helpers

    private func makeInput(scale: Scale, root: Int) -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: TonalFrame(scale: scale, root: Root(root)!),
            publish: { _ in }
        )
    }

    /// El pad `index` —0 es el primero—, no la nota `index`.
    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }
}
