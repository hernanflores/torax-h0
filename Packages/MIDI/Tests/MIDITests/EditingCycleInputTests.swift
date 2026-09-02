import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del knob que mueve el Cycle en edición.
///
/// **Dos cursores conviviendo.** El que suena lo mueve el scheduler en el límite
/// de vuelta; el que se edita lo mueve el knob 10, y no se tocan. Es la
/// separación que permite construir el Cycle B mientras suena el A (FR7), y es
/// también donde alguien se va a confundir: por eso lo que se fija aquí es que
/// mover uno no mueve al otro.
final class EditingCycleInputTests: XCTestCase {

    /// CC del knob 10 del preset: el bloque empieza en el 70 y los dieciséis van
    /// seguidos.
    private let cycleKnob = MIDIController(79)!

    private func cycle(pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Un input con los dieciséis Tracks, cada uno con `activeCount` Cycles.
    private func input(activeCycles: Int = 4) -> ControlInput {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Track(cycle()).withActiveCount(activeCycles), at: index)
        }
        return ControlInput(pattern: pattern, publish: { _ in })
    }

    private func turn(_ input: ControlInput, _ controller: MIDIController, by value: UInt8) {
        input.receive(
            .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value))
    }

    /// Un giro a la derecha en `Relative #2`.
    private let clockwise: UInt8 = 0x01
    private let counterClockwise: UInt8 = 0x7F

    // MARK: - El knob mueve el Cycle en edición

    /// El knob 10 mueve el Cycle en edición del **Track seleccionado**.
    func testTheTenthKnobMovesTheEditingCycleOfTheSelectedTrack() {
        let input = input()

        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
    }

    /// Y se frena en los extremos del rango **activo**, no en los dieciséis: no
    /// se edita un Cycle que no se recorre.
    func testItStopsAtBothEndsOfTheActiveRange() {
        let input = input(activeCycles: 3)

        for _ in 0..<10 { turn(input, cycleKnob, by: clockwise) }
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2, "pasó del último activo")

        for _ in 0..<10 { turn(input, cycleKnob, by: counterClockwise) }
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0, "pasó del primero")
    }

    /// Girar contra un extremo no publica: mandar un snapshot idéntico es
    /// trabajo y ruido para nada, igual que con Steps y Division.
    func testTurningAgainstAnEndDoesNotPublish() {
        let input = input(activeCycles: 2)

        XCTAssertTrue(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)))
        XCTAssertFalse(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)),
            "publicó sin cambiar nada")
    }

    /// Con un solo Cycle activo el knob no hace nada, que es lo coherente: no
    /// hay a dónde ir.
    func testWithASingleActiveCycleTheKnobDoesNothing() {
        let input = input(activeCycles: 1)

        XCTAssertFalse(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)))
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0)
    }

    // MARK: - Los dos cursores no se tocan

    /// **FR7 — mover el Cycle en edición no altera el cursor de reproducción.**
    func testMovingTheEditingCycleLeavesThePlaybackCursorAlone() {
        var pattern = Pattern()
        pattern = pattern.replacing(
            Track(cycle()).withActiveCount(4).withCursor(2), at: 0)
        let input = ControlInput(pattern: pattern, publish: { _ in })

        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 0)?.cursor, 2, "movió el cursor que suena")
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
    }

    /// Ni el material: mover el cursor de edición no toca ni un Cycle.
    func testMovingTheEditingCycleChangesNoMaterial() {
        let input = input()
        let before = input.pattern

        turn(input, cycleKnob, by: clockwise)

        for track in 0..<Pattern.trackCount {
            for slot in 0..<Track.cycleCount {
                XCTAssertEqual(
                    input.pattern.track(at: track)?.cycle(at: slot),
                    before.track(at: track)?.cycle(at: slot),
                    "Track \(track + 1), Cycle \(slot + 1)")
            }
        }
    }

    // MARK: - Cada Track recuerda el suyo

    /// **Cambiar de Track deja a cada uno con su Cycle en edición donde
    /// estaba.** Vive en el Track y no en la vista por esto: volver a uno y
    /// encontrarlo editando otro Cycle sería perder el sitio.
    func testEachTrackKeepsItsOwnEditingCycleAcrossSelection() {
        let input = input()
        let stepButton = { (index: Int) in MIDIController(102 + index)! }

        // El Track 1 se deja editando el Cycle 3.
        turn(input, cycleKnob, by: clockwise)
        turn(input, cycleKnob, by: clockwise)
        // Se pasa al Track 5 y se deja editando el 2.
        turn(input, stepButton(4), by: 127)
        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 4)?.editing, 1)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2, "el Track 1 perdió el sitio")

        // Y al volver, sigue donde estaba.
        turn(input, stepButton(0), by: 127)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2)
    }

    /// El knob mueve **solo** el del Track seleccionado, no el de los otros
    /// quince.
    func testTheKnobMovesOnlyTheSelectedTracksEditingCycle() {
        let input = input()

        turn(input, cycleKnob, by: clockwise)

        for index in 1..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.track(at: index)?.editing, 0, "movió el Track \(index + 1)")
        }
    }
}
