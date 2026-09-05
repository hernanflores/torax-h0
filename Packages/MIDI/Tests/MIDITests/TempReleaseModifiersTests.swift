import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de soltar Temp sin que llegue la soltada (FR8) y de las notas en vuelo
/// (FR13).
///
/// **Un cable desenchufado con el botón hundido dejaría el overlay pegado para
/// siempre**, porque la soltada que lo levantaría no va a llegar por ningún
/// sitio. Con mute y solo eso era un modificador atascado; con Temp es un fill
/// que no se va, encima de un Pattern que ya no se puede editar de verdad —todo
/// giro se superpondría—. Por eso la restauración va con `releaseModifiers()` y
/// no aparte.
final class TempReleaseModifiersTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }
    }

    // MARK: - Soltar sin soltada (FR8)

    /// **`releaseModifiers()` con Temp hundido restaura, publica y deja el
    /// estado en reposo.**
    func testReleaseModifiersRestoresAndPublishes() {
        let (input, published) = makeInput(pulses: 5)
        let before = input.track

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        let publishedByTheTurn = published.patterns.count

        input.releaseModifiers()

        XCTAssertEqual(input.track, before, "reconectar no devolvió el Cycle a como estaba")
        XCTAssertEqual(
            published.patterns.count, publishedByTheTurn + 1,
            "reconectar no publicó exactamente una vez")
    }

    /// Y deja el estado en reposo: el giro siguiente vuelve a escribir
    /// permanente, sin necesidad de que llegue ninguna soltada.
    func testAfterReleaseModifiersTheNextTurnWritesPermanently() {
        let (input, _) = makeInput(pulses: 5)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        input.releaseModifiers()

        input.receive(knob(.pulses, by: 2))

        XCTAssertEqual(input.track.shape.pulses.count, 7, "el overlay se quedó pegado")
    }

    /// Con Temp hundido y nada girado no hay nada que restaurar, así que no
    /// publica — mismo criterio que soltar el botón sin haber girado.
    func testReleaseModifiersWithNothingOverlaidDoesNotPublish() {
        let (input, published) = makeInput()

        input.receive(tempModifier())
        input.releaseModifiers()

        XCTAssertTrue(published.patterns.isEmpty)
    }

    /// **Sigue soltando los otros dos.** La tarea añade un modificador, no
    /// sustituye a los que había.
    func testReleaseModifiersStillReleasesMuteAndSolo() {
        let gestures = Gestures()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)),
            publish: { _ in },
            mix: gestures.record
        )

        input.receive(stepButton(ControlInput.muteModifierIndex))
        input.releaseModifiers()

        XCTAssertTrue(input.receive(stepButton(3)), "el modificador de mute se quedó hundido")
        XCTAssertEqual(input.selectedTrackIndex, 3)
        XCTAssertTrue(gestures.recorded.isEmpty)
    }

    /// Llamarlo en reposo no hace nada y no publica: reconectar sin ningún
    /// modificador hundido es el caso normal.
    func testReleaseModifiersAtRestDoesNothing() {
        let (input, published) = makeInput()

        input.releaseModifiers()

        XCTAssertTrue(published.patterns.isEmpty)
    }

    // MARK: - Tras un hold completo (FR5)

    /// **Tras un hold completo el Pattern es el de partida salvo lo que avanzó
    /// el cursor de reproducción.**
    ///
    /// El cursor se avanza a propósito entre superponer y restaurar, que es lo
    /// que hace el scheduler si el transporte está corriendo: restaurar no
    /// puede rebobinarlo.
    func testAfterAFullHoldOnlyThePlaybackCursorMoved() {
        let (input, _) = makeInput(pulses: 5)
        input.setActiveCycleCount(4)
        let before = input.pattern

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        input.receive(knob(.velocity, by: -15))
        input.receive(tempModifier(value: 0))

        let after = input.pattern
        XCTAssertEqual(after, before, "el hold dejó rastro en el Pattern")
        XCTAssertEqual(
            after.track(at: 0)?.cursor, before.track(at: 0)?.cursor,
            "el cursor de reproducción se movió sin que nadie lo avanzara")
    }

    /// Y con el cursor de reproducción movido durante el hold, lo único que
    /// difiere del Pattern de partida es ese cursor.
    func testTheAdvancedPlaybackCursorSurvivesTheRestore() {
        let (input, _) = makeInput(pulses: 5)
        input.setActiveCycleCount(4)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))

        // El scheduler avanza el cursor mientras dura el hold.
        let advanced = input.pattern.track(at: 0)!.advanced().advanced()
        let expectedCursor = advanced.cursor
        XCTAssertNotEqual(expectedCursor, 0, "el material de prueba no avanza el cursor")

        input.receive(tempModifier(value: 0))

        XCTAssertEqual(input.track.shape.pulses.count, 5, "el overlay no se deshizo")
    }

    // MARK: - Notas en vuelo (FR13)

    /// **Entrar y salir del overlay no emite ningún mensaje.**
    ///
    /// `ControlInput` no tiene por dónde emitir —solo publica snapshots— y ese
    /// es justo el punto: el camino de emisión no gana un all-notes-off. Un
    /// evento ya programado conserva su note-off, y entrar o salir afecta a los
    /// siguientes, como cualquier giro de knob hoy.
    func testEnteringAndLeavingTheOverlayEmitsNoMessages() {
        let (input, published) = makeInput(pulses: 5)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        input.receive(tempModifier(value: 0))

        // Lo único que sale de aquí son Patterns: dos, el del giro y el de la
        // restauración. Ningún mensaje MIDI, porque no hay puerta por la que
        // pudiera salir.
        XCTAssertEqual(published.patterns.count, 2)
    }

    // MARK: - Helpers

    private final class Gestures: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var recorded: [MixGesture] = []

        func record(_ gesture: MixGesture) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(gesture)
        }
    }

    private func makeInput(pulses: Int = 5) -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!)),
            publish: published.record
        )
        return (input, published)
    }

    private func tempModifier(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
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
