import XCTest

@testable import Engine

/// Tests de cuándo se limpia Harmony (`pitch-harmony_20260912`, FR13, AC 9).
///
/// **Se limpia cuando cambia el material del que parte**: el pool base, o la
/// escala que da sentido a sus grados. No hay otro gesto de reset. Pitch se
/// conserva en los dos casos, porque sus grados siguen significando lo mismo.
///
/// **Son operaciones de dominio y no `with(...)`.** `with(...)` copia literal
/// —lo necesitan la persistencia, las copias y la restauración de Temp y Ctrl
/// All— y limpiar ahí borraría Harmony al cargar un proyecto.
final class HarmonyClearingTests: XCTestCase {

    private let cMajor = TonalFrame(scale: .major, root: .c)

    /// C4 E4 G4 con Pitch +2 y dos clics de Harmony.
    private var moved: Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().inserting(Pitch(60)!).inserting(Pitch(64)!).inserting(Pitch(67)!),
            frame: cMajor,
            pitchOffset: PitchOffset(2)!
        ).applying(2, to: .harmony)
    }

    // MARK: - El pool

    func testInsertingAPitchClearsHarmonyAndKeepsPitch() {
        let edited = moved.togglingPitch(Pitch(72)!)
        XCTAssertEqual(edited.pool.count, 4)
        XCTAssertEqual(edited.harmony, .clean)
        XCTAssertEqual(edited.pitchOffset, PitchOffset(2))
    }

    func testRemovingAPitchClearsHarmonyToo() {
        let edited = moved.togglingPitch(Pitch(64)!)
        XCTAssertEqual(edited.pool.count, 2)
        XCTAssertEqual(edited.harmony, .clean)
        XCTAssertEqual(edited.pitchOffset, PitchOffset(2))
    }

    /// **Un pad que no cambia el pool no limpia nada**: el pool lleno rechaza la
    /// novena, y eso no es editar material.
    func testAToggleThatChangesNothingKeepsHarmony() {
        var full = PitchPool()
        for value in [48, 50, 52, 53, 55, 57, 59, 60] { full = full.inserting(Pitch(value)!) }
        let start = moved.with(pool: full, harmony: Harmony.clean.with(offset: 1, at: 7))

        XCTAssertEqual(start.togglingPitch(Pitch(72)!), start)
    }

    // MARK: - El marco

    func testChangingTheScaleClearsHarmonyAndKeepsPitch() {
        let edited = moved.reframed(to: TonalFrame(scale: .dorian, root: .c))
        XCTAssertEqual(edited.harmony, .clean)
        XCTAssertEqual(edited.pitchOffset, PitchOffset(2))
        XCTAssertEqual(edited.frame.scale, .dorian)
    }

    func testChangingTheRootClearsHarmonyToo() {
        let edited = moved.reframed(to: TonalFrame(scale: .major, root: Root(7)!))
        XCTAssertEqual(edited.harmony, .clean)
        XCTAssertEqual(edited.pitchOffset, PitchOffset(2))
    }

    /// Reencuadrar también reubica el pool, como hacía `ControlInput`.
    func testReframingMovesThePoolIntoTheNewFrame() {
        let aMinor = TonalFrame(scale: .minor, root: Root(9)!)
        let edited = moved.reframed(to: aMinor)
        XCTAssertEqual(edited.pool, moved.pool.reframed(to: aMinor))
    }

    /// El mismo marco no es un cambio: nada se limpia.
    func testReframingToTheSameFrameChangesNothing() {
        XCTAssertEqual(moved.reframed(to: cMajor), moved)
    }

    // MARK: - Lo que no limpia

    /// **Mover el registro de los pads no toca el material**, y tampoco Harmony.
    func testMovingThePadRegisterKeepsHarmony() {
        XCTAssertEqual(moved.with(padOctaveShift: 1).harmony, moved.harmony)
    }

    /// `with(...)` copia literal: es lo que usan la persistencia y las copias.
    func testWithKeepsHarmonyEvenWhenThePoolChanges() {
        let literal = moved.with(pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!))
        XCTAssertEqual(literal.harmony, moved.harmony)
    }
}
