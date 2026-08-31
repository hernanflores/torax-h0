import Engine
import XCTest
@testable import MIDI

/// Tests de los pads 8 y 16 desplazando el registro desde el controlador.
///
/// **Mueven la superficie, no el pool.** `product-guidelines.md` dice que
/// cambiar un parámetro nunca destruye material, y transponer bajo los pies del
/// usuario lo que ya metió en el pool es exactamente eso.
final class PadOctaveShiftInputTests: XCTestCase {

    private let frame = TonalFrame(scale: .major, root: Root(0)!)

    // MARK: - Mueven el registro

    func testTheOctavePadsMoveTheSurface() {
        let input = makeInput()

        XCTAssertTrue(input.receive(pad(15)), "el pad 16 sube")
        XCTAssertEqual(input.surface.pitch(at: 0)?.value, 60)

        XCTAssertTrue(input.receive(pad(7)), "el pad 8 baja")
        XCTAssertEqual(input.surface.pitch(at: 0)?.value, 48)

        input.receive(pad(7))
        XCTAssertEqual(input.surface.pitch(at: 0)?.value, 36)
    }

    // MARK: - No tocan el pool

    /// **Con notas dentro, desplazar deja el pool idéntico.** Es la decisión 4
    /// del spec y la regla de destructividad de `product-guidelines.md`.
    func testShiftingTheOctaveLeavesThePoolUntouched() {
        let input = makeInput()
        for index in [0, 2, 4] { input.receive(pad(index)) }
        let before = input.track.pool

        input.receive(pad(15))
        input.receive(pad(15))
        input.receive(pad(7))

        XCTAssertEqual(input.track.pool, before, "el desplazamiento movió el pool")
    }

    /// **El caso de uso que justifica la superficie móvil:** bajar, meter dos
    /// graves, subir y meter dos agudas deja las cuatro en el pool.
    func testTheSurfaceIsAMovableRegisterAndThePoolAccumulates() {
        let input = makeInput()

        input.receive(pad(7))
        input.receive(pad(0))  // 36
        input.receive(pad(1))  // 38

        input.receive(pad(15))
        input.receive(pad(15))
        input.receive(pad(0))  // 60
        input.receive(pad(1))  // 62

        XCTAssertEqual(input.track.pool.count, 4)
        for value in [36, 38, 60, 62] {
            XCTAssertTrue(input.track.pool.contains(Pitch(value)!), "falta \(value)")
        }
    }

    // MARK: - El tope

    /// En el tope el pad no publica nada y no cambia el estado: ni la superficie
    /// ni el pool.
    func testAtTheLimitTheOctavePadDoesNothing() {
        let input = makeInput()
        input.receive(pad(0))

        for _ in 0..<32 where input.surface.canShiftUp { input.receive(pad(15)) }
        let surface = input.surface
        let pool = input.track.pool

        XCTAssertFalse(input.receive(pad(15)), "en el tope no publica")
        XCTAssertEqual(input.surface, surface)
        XCTAssertEqual(input.track.pool, pool)

        for _ in 0..<32 where input.surface.canShiftDown { input.receive(pad(7)) }
        XCTAssertFalse(input.receive(pad(7)), "en el tope grave no publica")
    }

    // MARK: - Publicación

    /// Desplazar publica un snapshot solo si algo cambió. El Track no lleva la
    /// octava dentro, pero la superficie decide qué altura mete el pad
    /// siguiente, y la pantalla tiene que enterarse.
    func testShiftingPublishesOnlyWhenSomethingChanged() {
        let recorder = Recorder()
        let input = ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame,
            publish: { _ in recorder.record() }
        )

        XCTAssertTrue(input.receive(pad(15)))
        XCTAssertEqual(recorder.count, 1)

        for _ in 0..<32 where input.surface.canShiftUp { input.receive(pad(15)) }
        let atTheTop = recorder.count

        XCTAssertFalse(input.receive(pad(15)))
        XCTAssertEqual(recorder.count, atTheTop, "publicó sin cambiar nada")
    }

    /// La soltada de un pad de octava no hace nada, igual que la de cualquier
    /// otro pad.
    func testReleasingAnOctavePadDoesNothing() {
        let input = makeInput()
        input.receive(pad(15))
        let surface = input.surface

        XCTAssertFalse(
            input.receive(
                .noteOff(
                    channel: MIDIChannel(1)!,
                    note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + 15)!,
                    velocity: MIDIVelocity(0)!
                )))
        XCTAssertEqual(input.surface, surface)
    }

    // MARK: - Helpers

    private func makeInput() -> ControlInput {
        ControlInput(
            track: Track(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            frame: frame,
            publish: { _ in }
        )
    }

    private final class Recorder: @unchecked Sendable {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }
}
