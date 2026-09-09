import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de la vía táctil que fija el Cycle en edición (FR1–FR4).
///
/// **El defecto que cierra esta vía**: el cursor de edición se quedaba siempre
/// en el Cycle 1 porque la única forma de moverlo era el knob 13. Sin
/// controlador, todo giro caía en el mismo Cycle y los otros quince parecían
/// copias que no guardan nada.
///
/// La vía va junto a `setActiveCycleCount` y `setChannel`, que son las otras
/// entradas táctiles, y se apoya en `Track.withEditing(_:)` para el acotado al
/// rango activo: no se decide dos veces (FR2, NFR1).
final class EditingCycleTouchPathTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var count = 0

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    /// CC del knob del Cycle en edición, **leído del mapeo y no escrito** — ver
    /// la nota de `EditingCycleInputTests`.
    private let cycleKnob = ControlMapping.beatStepPro.editingCycleController!

    private let clockwise: UInt8 = 0x01

    private func cycle(pulses: Int = 5, pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    private func makeInput(activeCycles: Int = 4) -> (ControlInput, Published) {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Track(cycle()).withActiveCount(activeCycles), at: index)
        }
        let published = Published()
        return (ControlInput(pattern: pattern, publish: published.record), published)
    }

    private func turn(_ input: ControlInput, _ controller: MIDIController, by value: UInt8) {
        input.receive(
            .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value))
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(
                ControlMapping.beatStepPro.stepButtonBlock.number
                    + ControlInput.ctrlAllModifierIndex)!,
            value: UInt8(value)
        )
    }

    // MARK: - Fija el cursor y publica

    /// **FR1, FR3 — fijar el Cycle 4 con cuatro activos mueve `editing` y
    /// publica.** Publica por el mismo camino que `setActiveCycleCount`: el
    /// snapshot que cruza al scheduler lleva el Track entero.
    func testItSetsTheEditingCycleAndPublishes() {
        let (input, published) = makeInput()

        XCTAssertTrue(input.setEditingCycle(3))

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 3)
        XCTAssertEqual(published.count, 1)
    }

    /// **El fallo reportado, escrito como test.** Fijado el Cycle 3, el giro
    /// siguiente edita **ese** y deja los otros quince intactos.
    func testTheNextKnobTurnEditsThatCycleAndLeavesTheOthersAlone() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.setEditingCycle(2)
        // CC 71 es Pulses.
        turn(input, MIDIController(71)!, by: clockwise)

        XCTAssertNotEqual(
            input.pattern.track(at: 0)?.cycle(at: 2), before.track(at: 0)?.cycle(at: 2),
            "no editó el Cycle que se acababa de elegir")
        for slot in 0..<Track.cycleCount where slot != 2 {
            XCTAssertEqual(
                input.pattern.track(at: 0)?.cycle(at: slot), before.track(at: 0)?.cycle(at: slot),
                "tocó el Cycle \(slot + 1)")
        }
    }

    /// **Dos Cycles con valores distintos**, que es el desarrollo que el defecto
    /// impedía: elegir el 3, girar, volver al 1 y girar deja los dos movidos y
    /// diferentes entre sí.
    func testTwoCyclesCanHoldDifferentValues() {
        let (input, _) = makeInput()

        input.setEditingCycle(2)
        turn(input, MIDIController(71)!, by: clockwise)
        input.setEditingCycle(0)
        turn(input, MIDIController(71)!, by: clockwise)
        turn(input, MIDIController(71)!, by: clockwise)

        XCTAssertNotEqual(
            input.pattern.track(at: 0)?.cycle(at: 0), input.pattern.track(at: 0)?.cycle(at: 2),
            "los dos Cycles acabaron iguales")
    }

    /// Toca **solo** al Track seleccionado.
    func testItTouchesOnlyTheSelectedTrack() {
        let (input, _) = makeInput()

        input.selectTrack(6)
        input.setEditingCycle(2)

        XCTAssertEqual(input.pattern.track(at: 6)?.editing, 2)
        for index in 0..<Pattern.trackCount where index != 6 {
            XCTAssertEqual(
                input.pattern.track(at: index)?.editing, 0, "movió el Track \(index + 1)")
        }
    }

    // MARK: - Se acota al rango activo (FR2)

    /// Un índice fuera del rango activo se acota, no revienta y no inventa un
    /// Cycle: el acotado vive en `Track.withEditing(_:)` y no se duplica aquí.
    func testItClampsToTheActiveRange() {
        let (input, _) = makeInput(activeCycles: 4)

        input.setEditingCycle(9)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 3, "pasó del último activo")

        input.setEditingCycle(-3)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0, "pasó del primero")
    }

    /// Y el acotado no activa Cycles ni cambia cuántos se recorren.
    func testClampingDoesNotChangeTheActiveCount() {
        let (input, _) = makeInput(activeCycles: 2)

        input.setEditingCycle(15)

        XCTAssertEqual(input.pattern.track(at: 0)?.activeCount, 2)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
    }

    // MARK: - Fijar el mismo no publica (FR4)

    /// Por la misma razón que girar contra un tope no publica: mandar un
    /// snapshot idéntico es trabajo y ruido para nada.
    func testSettingTheSameIndexDoesNotPublish() {
        let (input, published) = makeInput()

        XCTAssertTrue(input.setEditingCycle(2))
        XCTAssertFalse(input.setEditingCycle(2), "publicó sin cambiar nada")
        XCTAssertEqual(published.count, 1)
    }

    /// Y un índice que se acota al que ya estaba tampoco publica.
    func testAnIndexThatClampsOntoTheCurrentOneDoesNotPublish() {
        let (input, published) = makeInput(activeCycles: 3)

        XCTAssertTrue(input.setEditingCycle(2))
        XCTAssertFalse(input.setEditingCycle(11))
        XCTAssertEqual(published.count, 1)
    }

    // MARK: - No toca material ni el cursor que suena (FR3)

    /// **El cursor de reproducción no se mueve**: es del scheduler y del límite
    /// de vuelta.
    func testItLeavesThePlaybackCursorAlone() {
        var pattern = Pattern()
        pattern = pattern.replacing(
            Track(cycle()).withActiveCount(4).withCursor(2), at: 0)
        let input = ControlInput(pattern: pattern, publish: { _ in })

        input.setEditingCycle(3)

        XCTAssertEqual(input.pattern.track(at: 0)?.cursor, 2, "movió el cursor que suena")
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 3)
    }

    /// Ni una sola nota de material cambia.
    func testItChangesNoMaterial() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.setEditingCycle(3)

        for track in 0..<Pattern.trackCount {
            for slot in 0..<Track.cycleCount {
                XCTAssertEqual(
                    input.pattern.track(at: track)?.cycle(at: slot),
                    before.track(at: track)?.cycle(at: slot),
                    "Track \(track + 1), Cycle \(slot + 1)")
            }
        }
    }

    // MARK: - Calla con el toque congelado

    /// Con Ctrl All hundido no hace nada, como `setActiveCycleCount`: devuelve
    /// `false` y no publica, que es el criterio de `CtrlAllTouchPathTests`.
    func testItIsIgnoredWhileTouchIsFrozen() {
        let (input, published) = makeInput()
        input.receive(ctrlAll())

        XCTAssertFalse(input.setEditingCycle(3))

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0)
        XCTAssertEqual(published.count, 0)
    }
}
