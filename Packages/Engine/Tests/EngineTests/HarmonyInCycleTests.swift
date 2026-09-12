import XCTest

@testable import Engine

/// Tests del estado de Harmony dentro del `Cycle` (`pitch-harmony_20260912`,
/// FR1, FR2, NFR1).
///
/// **Un offset en grados por hueco del pool, y un cursor.** El índice del pool es
/// la identidad de cada pitch: el pool está ordenado y Harmony no deja cruzar,
/// así que el pitch *i* sigue siendo el *i*-ésimo. Lo que aquí se prueba es el
/// estado y cómo entra en lo que suena; el paso que lo cambia tiene sus tests.
final class HarmonyInCycleTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(16)!)
    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int], harmony: Harmony = .clean, offset: Int = 0) -> Cycle {
        Cycle(
            shape: shape,
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: cMajor,
            pitchOffset: PitchOffset(offset)!,
            harmony: harmony)
    }

    private func values(_ pool: PitchPool) -> [Int] {
        (0..<pool.count).compactMap { pool.pitch(at: $0)?.value }
    }

    // MARK: - El tipo

    /// Limpio: todos los offsets a 0 y el cursor en el primero.
    func testCleanHasNoOffsetsAndTheCursorAtTheFirst() {
        for index in 0..<PitchPool.capacity {
            XCTAssertEqual(Harmony.clean.offset(at: index), 0)
        }
        XCTAssertEqual(Harmony.clean.cursor, 0)
        XCTAssertTrue(Harmony.clean.isClean)
    }

    /// Cada hueco guarda su offset con signo, sin pisar a los vecinos.
    func testEachSlotKeepsItsOwnSignedOffset() {
        let harmony = Harmony.clean
            .with(offset: -3, at: 0)
            .with(offset: 5, at: 1)
            .with(offset: -127, at: 7)
            .with(cursor: 6)

        XCTAssertEqual(
            (0..<PitchPool.capacity).map { harmony.offset(at: $0) }, [-3, 5, 0, 0, 0, 0, 0, -127])
        XCTAssertEqual(harmony.cursor, 6)
        XCTAssertFalse(harmony.isClean)
    }

    /// Fuera del pool no hay offset.
    func testOutsideTheCapacityTheOffsetIsZero() {
        XCTAssertEqual(Harmony.clean.with(offset: 2, at: 0).offset(at: 8), 0)
        XCTAssertEqual(Harmony.clean.with(offset: 2, at: 0).offset(at: -1), 0)
    }

    /// **Nueve bytes por Cycle**: ocho offsets en un entero y el cursor.
    func testTheStateCostsNineBytes() {
        XCTAssertEqual(MemoryLayout<Harmony>.size, 9)
        XCTAssertTrue(_isPOD(Harmony.self))
    }

    // MARK: - En el Cycle

    func testAFreshCycleHasCleanHarmony() {
        XCTAssertEqual(Cycle(shape: shape).harmony, .clean)
    }

    /// Con Harmony limpio y Pitch 0 lo que suena es el pool (AC 11).
    func testCleanHarmonySoundsThePool() {
        let plain = cycle([60, 64, 67])
        XCTAssertEqual(plain.soundingPool, plain.pool)
    }

    /// El pool que suena suma el offset de cada pitch.
    func testTheSoundingPoolAddsEachOffset() {
        let moved = cycle([60, 64, 67], harmony: Harmony.clean.with(offset: 1, at: 0))
        XCTAssertEqual(values(moved.soundingPool), [62, 64, 67])
    }

    /// Y Pitch se suma encima: la forma la da Harmony, el registro Pitch.
    func testPitchIsAddedOnTopOfHarmony() {
        let harmony = Harmony.clean.with(offset: 1, at: 1).with(offset: 1, at: 2)
        XCTAssertEqual(
            values(cycle([60, 64, 67], harmony: harmony, offset: 1).soundingPool), [62, 67, 71])
        XCTAssertEqual(values(cycle([60, 64, 67], harmony: harmony).soundingPool), [60, 65, 69])
    }

    /// **El freno de Pitch cuenta con Harmony**: E9 movido dos grados ya es G9, y
    /// Pitch no puede subir más (FR6).
    func testThePitchBrakeCountsHarmony() {
        let top = cycle([60, 124], harmony: Harmony.clean.with(offset: 2, at: 1))
        XCTAssertEqual(top.applying(1, to: .pitch), top)
    }

    /// `with(...)` conserva Harmony, y `with(harmony:)` no toca nada más.
    func testEditsKeepHarmonyAndHarmonyKeepsTheRest() {
        let harmony = Harmony.clean.with(offset: 1, at: 0).with(cursor: 1)
        let base = cycle([60, 64, 67], offset: 2)
        let edited = base.with(harmony: harmony)

        XCTAssertEqual(edited.pitchOffset, base.pitchOffset)
        XCTAssertEqual(edited.pool, base.pool)
        XCTAssertEqual(edited.frame, base.frame)
        XCTAssertEqual(edited.with(channel: Channel(4)!).harmony, harmony)
        XCTAssertEqual(edited.with(pitchOffset: .zero).harmony, harmony)
        for parameter in TrackParameter.allCases {
            XCTAssertEqual(edited.applying(1, to: parameter).harmony, harmony, "\(parameter)")
        }
    }

    func testTheCycleIsStillTriviallyCopyable() {
        XCTAssertTrue(_isPOD(Cycle.self))
        XCTAssertTrue(_isPOD(Track.self))
        XCTAssertTrue(_isPOD(Engine.Pattern.self))
    }
}
