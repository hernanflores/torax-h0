import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de `releaseModifiers()` con Ctrl All (FR15).
///
/// **Lo llama quien reconecta la entrada.** Un cable desenchufado con el step 14
/// hundido dejaría el desplazamiento puesto sobre los doce Tracks para siempre,
/// porque la soltada que lo levantaría ya no va a llegar por ningún sitio.
///
/// **Y es peor que un modificador atascado de mute o solo.** Aquellos dejan un
/// gesto que no responde; éste deja un Pattern desplazado que además ya no se
/// puede editar de verdad, porque todo giro seguiría desplazándose y toda vía
/// táctil seguiría congelada. Por eso la restauración va dentro de
/// `releaseModifiers()` y no en un método aparte: el sitio donde habría que
/// acordarse de llamarla es precisamente el de la reconexión, que nadie prueba a
/// mano.
final class CtrlAllReleaseModifiersTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var count = 0

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    /// **Restaura y publica una vez.**
    func testItRestoresAndPublishesOnce() {
        let (input, published) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 3))
        let afterTurn = published.count

        input.releaseModifiers()

        XCTAssertEqual(input.pattern, before, "el desplazamiento quedó pegado")
        XCTAssertEqual(published.count, afterTurn + 1, "publicó más de una vez")
    }

    /// Y deja el modificador suelto: el gesto no sigue puesto por dentro.
    func testItLeavesTheModifierReleased() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 3))
        input.releaseModifiers()

        XCTAssertFalse(input.isCtrlAllActive)

        // Un giro después escribe normal, en un solo Track.
        input.receive(knob(.pulses, by: 1))
        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 5)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 1,
            "el gesto seguía puesto tras releaseModifiers()")
    }

    /// Y devuelve la pantalla: las vías táctiles dejan de estar congeladas.
    func testItUnfreezesTheTouchPath() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.releaseModifiers()

        XCTAssertTrue(input.selectTrack(7), "la pantalla siguió congelada")
    }

    /// **Con Temp y Ctrl All hundidos a la vez**, deja el Pattern base y publica
    /// sin duplicar la restauración.
    func testWithBothHeldItRestoresWithoutDuplicating() {
        let (input, published) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(knob(.pulses, by: 2))
        let afterTurn = published.count

        input.releaseModifiers()

        XCTAssertEqual(input.pattern, before)
        XCTAssertEqual(
            published.count, afterTurn + 1,
            "los dos snapshots publicaron por separado")
        XCTAssertFalse(input.isTempActive)
        XCTAssertFalse(input.isCtrlAllActive)
    }

    /// **Sin nada desplazado no publica**: reconectar sin modificadores hundidos
    /// es el caso normal y un snapshot idéntico sería ruido.
    func testItDoesNotPublishWithNothingHeld() {
        let (input, published) = makeInput()

        input.releaseModifiers()

        XCTAssertEqual(published.count, 0)
    }

    /// Ni tras un hold en el que no se llegó a girar nada.
    func testItDoesNotPublishAfterAHoldWithNoTurn() {
        let (input, published) = makeInput()

        input.receive(ctrlAll())
        input.releaseModifiers()

        XCTAssertEqual(published.count, 0)
    }

    // MARK: - Helpers

    private func makeInput() -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48)!)
            ),
            publish: published.record
        )
        return (input, published)
    }

    private func temp(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.ctrlAllModifierIndex, value: value)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }
}
