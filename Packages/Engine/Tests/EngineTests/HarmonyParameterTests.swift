import XCTest

@testable import Engine

/// Tests de `TrackParameter.harmony`: el knob que mueve un pitch del pool por
/// clic (`pitch-harmony_20260912`, FR8, FR20).
final class HarmonyParameterTests: XCTestCase {

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

    func testHarmonyIsATonalParameterNamedHarmony() {
        XCTAssertEqual(TrackParameter.harmony.family, .tonal)
        XCTAssertEqual(TrackParameter.harmony.description, "Harmony")
        XCTAssertFalse(TrackParameter.harmony.isNoteRepeater)
    }

    /// **No tiene posición absoluta.** Es estado dependiente del camino, así que
    /// no hay extremos contra los que saturar —como Rotate— ni un número que
    /// sea «dónde está el knob».
    func testHarmonyHasNoAbsolutePosition() {
        XCTAssertNil(TrackParameter.harmony.displacementRange)
        XCTAssertEqual(cycle([60, 64, 67]).applying(2, to: .harmony).value(of: .harmony), 0)
    }

    // MARK: - Girar

    /// Girar es dar pasos: el mismo resultado que `harmonyMoved(by:)`.
    func testTurningStepsTheHarmony() {
        let start = cycle([60, 64, 67])
        let turned = start.applying(3, to: .harmony)
        XCTAssertEqual(turned.harmony, start.harmonyMoved(by: 3))
        XCTAssertEqual(turned.pool, start.pool, "el pool base no se toca")
        XCTAssertEqual(turned.pitchOffset, start.pitchOffset)
    }

    /// Un giro bloqueado devuelve el mismo Cycle, que es lo que permite a
    /// `ControlInput` no publicar (FR18).
    func testABlockedTurnReturnsAnIdenticalCycle() {
        let blocked = cycle([125, 127])
        XCTAssertEqual(blocked.applying(1, to: .harmony), blocked)
    }

    /// Pitch mantiene su freno atómico con Harmony activo.
    func testPitchKeepsItsBrakeWithHarmonyActive() {
        // Dos clics: C4 sube a D4 y después D9 (122) sube a E9 (124).
        let moved = cycle([60, 122]).applying(1, to: .harmony).applying(1, to: .harmony)
        XCTAssertEqual(moved.harmony.offset(at: 1), 1)
        // E9 sube a G9 con +2 de Pitch, y no más.
        XCTAssertEqual(moved.applying(5, to: .pitch).pitchOffset, PitchOffset(2))
    }

    // MARK: - Leer el valor

    /// El valor es lo que suena, con octava (FR20).
    func testTheValueIsTheSoundingPool() {
        let turned = cycle([60, 64, 67]).applying(3, to: .harmony)
        XCTAssertEqual(TrackParameter.harmony.value(in: turned), "D4 F4 A4")
        XCTAssertEqual(
            TrackParameter.harmony.value(in: cycle([60, 64, 67], offset: 1)), "D4 F4 A4")
    }

    /// Con el pool vacío se dice, como en el resto de la app.
    func testAnEmptyPoolReadsEmpty() {
        XCTAssertEqual(TrackParameter.harmony.value(in: cycle([])), "empty")
    }

    // MARK: - El valor transitorio

    /// Un giro de Harmony se anuncia con el pool que suena.
    func testATurnAnnouncesHarmony() {
        let start = cycle([60, 64, 67])
        let change = ParameterChange(from: start, to: start.applying(1, to: .harmony))
        XCTAssertEqual(change?.parameter, .harmony)
        XCTAssertEqual(change?.description, "Harmony D4 E4 G4")
    }

    /// **Editar el pool no es girar Harmony**, aunque lo limpie: no se anuncia.
    func testEditingThePoolIsNotAnnouncedAsHarmony() {
        let moved = cycle([60, 64, 67]).applying(1, to: .harmony)
        let edited = moved.with(pool: PitchPool().inserting(Pitch(60)!), harmony: .clean)
        XCTAssertNil(ParameterChange(from: moved, to: edited))
    }
}
