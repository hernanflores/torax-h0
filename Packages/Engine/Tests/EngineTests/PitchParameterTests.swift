import XCTest

@testable import Engine

/// Tests de `TrackParameter.pitch`: el knob que transpone el pool en grados
/// (`pitch-harmony_20260912`, FR4, FR5, FR6, FR19).
final class PitchParameterTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(16)!)
    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int], offset: Int = 0) -> Cycle {
        Cycle(
            shape: shape,
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: cMajor,
            pitchOffset: PitchOffset(offset)!)
    }

    // MARK: - Qué es

    /// **El primer parámetro de knob de la familia Tonal.**
    func testPitchIsATonalParameterNamedPitch() {
        XCTAssertEqual(TrackParameter.pitch.family, .tonal)
        XCTAssertEqual(TrackParameter.pitch.description, "Pitch")
        XCTAssertFalse(TrackParameter.pitch.isNoteRepeater)
        XCTAssertEqual(TrackParameter.pitch.displacementRange, -28...28)
    }

    // MARK: - Girar

    /// Un clic, un grado.
    func testOneClickIsOneDegree() {
        let turned = cycle([60, 64, 67]).applying(1, to: .pitch)
        XCTAssertEqual(turned.pitchOffset, PitchOffset(1))
        XCTAssertEqual(turned.pool, cycle([60, 64, 67]).pool, "el pool base no se toca")
    }

    /// Se frena en ±28, y girar contra el extremo devuelve el mismo Cycle.
    func testItStopsAtTheEndsOfItsRange() {
        XCTAssertEqual(cycle([60], offset: 27).applying(5, to: .pitch).pitchOffset, PitchOffset(28))
        XCTAssertEqual(
            cycle([60], offset: -27).applying(-5, to: .pitch).pitchOffset, PitchOffset(-28))
        XCTAssertEqual(cycle([60], offset: 28).applying(1, to: .pitch), cycle([60], offset: 28))
    }

    /// **Freno atómico** (FR6): E9 en Do mayor sube hasta G9 (+2) y ahí se para,
    /// porque A9 no existe. El giro no se aplica a medias ni apila notas.
    func testItStopsAtomicallyWhenAPitchWouldLeaveMIDI() {
        let high = cycle([60, 124])  // C4 E9
        XCTAssertEqual(high.applying(5, to: .pitch).pitchOffset, PitchOffset(2))
        XCTAssertEqual(high.applying(5, to: .pitch).soundingPool.count, 2)

        let low = cycle([2, 60])  // D-1 C4
        XCTAssertEqual(low.applying(-5, to: .pitch).pitchOffset, PitchOffset(-1))
    }

    /// **Desde fuera de los límites solo se puede volver.** Un cambio de Scale
    /// puede dejar el offset donde ya no cabe; el knob no empuja más allá, pero
    /// sí deja bajar hacia donde cabe.
    func testFromBeyondTheLimitOnlyTurningBackMoves() {
        let stuck = cycle([124], offset: 10)
        XCTAssertEqual(stuck.applying(1, to: .pitch), stuck)
        XCTAssertEqual(stuck.applying(-1, to: .pitch).pitchOffset, PitchOffset(2))
    }

    /// Con el pool vacío no hay nada que frenar: se mueve libre dentro de ±28.
    func testAnEmptyPoolMovesFreelyWithinTheRange() {
        XCTAssertEqual(cycle([]).applying(40, to: .pitch).pitchOffset, PitchOffset(28))
        XCTAssertEqual(cycle([]).applying(-3, to: .pitch).pitchOffset, PitchOffset(-3))
    }

    // MARK: - Leer y escribir el valor

    /// Con signo explícito, y sin signo en el cero (FR19).
    func testTheValueIsWrittenWithItsSign() {
        XCTAssertEqual(TrackParameter.pitch.value(in: cycle([60], offset: 2)), "+2")
        XCTAssertEqual(TrackParameter.pitch.value(in: cycle([60], offset: 0)), "0")
        XCTAssertEqual(TrackParameter.pitch.value(in: cycle([60], offset: -1)), "-1")
    }

    /// La posición del knob son los grados, y `setting` la escribe con el mismo
    /// freno que el giro: es lo que usan Temp y Ctrl All.
    func testTheKnobPositionIsTheOffset() {
        XCTAssertEqual(cycle([60], offset: -4).value(of: .pitch), -4)
        XCTAssertEqual(cycle([60]).setting(.pitch, to: 3).pitchOffset, PitchOffset(3))
        XCTAssertEqual(cycle([60, 124]).setting(.pitch, to: 9).pitchOffset, PitchOffset(2))
    }
}
