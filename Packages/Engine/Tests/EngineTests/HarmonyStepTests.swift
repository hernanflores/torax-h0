import XCTest

@testable import Engine

/// Tests del paso de Harmony: qué pitch se mueve con cada clic
/// (`pitch-harmony_20260912`, FR8–FR12, NFR2).
///
/// **Round robin con histéresis.** El cursor dice cuál se intenta primero; si no
/// puede moverse un grado sin chocar, cruzar o salir de MIDI, se prueba el
/// siguiente. El que se mueve deja el cursor en el de después. Invertir el
/// sentido no deshace nada: es otro paso, sobre el cursor que haya.
final class HarmonyStepTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(16)!)
    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int], offset: Int = 0, frame: TonalFrame? = nil) -> Cycle {
        Cycle(
            shape: shape,
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: frame ?? cMajor,
            pitchOffset: PitchOffset(offset)!)
    }

    private func step(_ cycle: Cycle, _ delta: Int) -> Cycle {
        cycle.with(harmony: cycle.harmonyMoved(by: delta))
    }

    private func sounding(_ cycle: Cycle) -> [Int] {
        (0..<cycle.soundingPool.count).compactMap { cycle.soundingPool.pitch(at: $0)?.value }
    }

    // MARK: - Los ejemplos del PRD

    /// Desde C4 E4 G4: tres clics horarios y uno antihorario (AC 4).
    func testTheRoundRobinExampleOfThePRD() {
        var current = cycle([60, 64, 67])

        current = step(current, 1)
        XCTAssertEqual(sounding(current), [62, 64, 67], "D4 E4 G4")
        XCTAssertEqual(current.harmony.cursor, 1)

        current = step(current, 1)
        XCTAssertEqual(sounding(current), [62, 65, 67], "D4 F4 G4")
        XCTAssertEqual(current.harmony.cursor, 2)

        current = step(current, 1)
        XCTAssertEqual(sounding(current), [62, 65, 69], "D4 F4 A4")
        XCTAssertEqual(current.harmony.cursor, 0)

        current = step(current, -1)
        XCTAssertEqual(sounding(current), [60, 65, 69], "C4 F4 A4, no D4 F4 G4")
        XCTAssertEqual(current.harmony.cursor, 1)
    }

    /// Combinado con Pitch (AC 5): Pitch +1, tres clics y uno inverso dan D4 G4
    /// B4; Pitch a 0 da C4 F4 A4.
    func testTheCombinedExampleOfThePRD() {
        var current = cycle([60, 64, 67], offset: 1)
        for delta in [1, 1, 1, -1] { current = step(current, delta) }

        XCTAssertEqual(sounding(current), [62, 67, 71], "D4 G4 B4")
        XCTAssertEqual(sounding(current.with(pitchOffset: .zero)), [60, 65, 69], "C4 F4 A4")
    }

    // MARK: - Movimientos que no valen

    /// **Un choque se salta**: C4 no puede subir a D4 porque D4 ya está; se mueve
    /// D4, y el cursor queda detrás de él.
    func testACollisionIsSkippedAndTheNextPitchMoves() {
        let moved = step(cycle([60, 62]), 1)
        XCTAssertEqual(sounding(moved), [60, 64])
        XCTAssertEqual(moved.harmony.cursor, 0)
    }

    /// **Un cruce tampoco vale**: cada pitch queda estrictamente entre sus
    /// vecinos, así que el orden del pool no cambia nunca.
    func testNoPitchCrossesItsNeighbour() {
        var current = cycle([60, 62, 64])
        for _ in 0..<12 {
            current = step(current, 1)
            let pitches = sounding(current)
            XCTAssertEqual(pitches, pitches.sorted())
            XCTAssertEqual(Set(pitches).count, 3)
        }
    }

    /// El borde de MIDI se mide con Pitch aplicado.
    func testTheMIDIEdgeCountsPitch() {
        // E9 +2 de Pitch es G9: ya no puede subir, así que se mueve C4.
        let moved = step(cycle([60, 124], offset: 2), 1)
        XCTAssertEqual(moved.harmony.offset(at: 1), 0)
        XCTAssertEqual(moved.harmony.offset(at: 0), 1)
    }

    /// **Todo bloqueado deja el Cycle idéntico** (AC 8): F9 choca con G9 y G9 no
    /// tiene A9. Y abajo, C-1 no tiene nada debajo y D-1 choca con C-1.
    func testWhenEveryMoveIsBlockedNothingChanges() {
        let top = cycle([125, 127])
        XCTAssertEqual(step(top, 1), top)

        let bottom = cycle([0, 2])
        XCTAssertEqual(step(bottom, -1), bottom)
    }

    // MARK: - Pools pequeños, deltas grandes

    /// Con 0 o 1 pitches no hay nada que mover y el cursor no avanza (FR12).
    func testFewerThanTwoPitchesIsANoOp() {
        XCTAssertEqual(step(cycle([]), 3), cycle([]))
        XCTAssertEqual(step(cycle([60]), 3), cycle([60]))
        XCTAssertEqual(step(cycle([60]), -3), cycle([60]))
    }

    /// Un delta de *n* son *n* pasos de uno (FR8).
    func testADeltaOfNIsNStepsOfOne() {
        let start = cycle([48, 55, 60, 64])
        var oneByOne = start
        for _ in 0..<5 { oneByOne = step(oneByOne, 1) }
        XCTAssertEqual(step(start, 5), oneByOne)

        var down = oneByOne
        for _ in 0..<7 { down = step(down, -1) }
        XCTAssertEqual(step(oneByOne, -7), down)
    }

    /// Un cursor que apunta más allá del pool —un pool que encogió— envuelve.
    func testACursorBeyondThePoolWraps() {
        let shrunk = cycle([60, 64, 67]).with(harmony: Harmony.clean.with(cursor: 5))
        let moved = step(shrunk, 1)
        XCTAssertEqual(sounding(moved), [60, 64, 69], "5 módulo 3 es el tercero")
        XCTAssertEqual(moved.harmony.cursor, 0)
    }

    // MARK: - Propiedades

    /// Sobre muchas secuencias de clics, en todas las escalas: un paso cambia
    /// como mucho un pitch que suena (AC 3); todo lo que suena está en el marco
    /// y en 0–127 (AC 6); el pool no encoge ni se desordena; y repetir la misma
    /// secuencia da lo mismo (NFR2).
    func testStepPropertiesOverRandomSequences() {
        var random = SeededRandom(seed: 0x5EED)
        for scale in Scale.allCases {
            for root in [0, 5, 11] {
                let frame = TonalFrame(scale: scale, root: Root(root)!)
                let base = [36, 50, 60, 70, 84].map { frame.nearest(to: Pitch($0)!).value }
                let start = cycle(base, offset: Int(random.next() % 9) - 4, frame: frame)

                var deltas: [Int] = []
                var current = start
                for _ in 0..<200 {
                    let delta = random.next() % 2 == 0 ? 1 : -1
                    deltas.append(delta)
                    let next = step(current, delta)

                    let before = sounding(current)
                    let after = sounding(next)
                    XCTAssertEqual(after.count, before.count, "\(scale)·\(root)")
                    XCTAssertLessThanOrEqual(
                        zip(before, after).filter { $0 != $1 }.count, 1, "\(scale)·\(root)")
                    XCTAssertEqual(after, after.sorted())
                    for value in after {
                        XCTAssertTrue(Pitch.validRange.contains(value))
                        XCTAssertTrue(frame.allows(Pitch(value)!), "\(scale)·\(root)·\(value)")
                    }
                    current = next
                }

                let replayed = deltas.reduce(start) { step($0, $1) }
                XCTAssertEqual(replayed, current, "\(scale)·\(root) no es determinista")
            }
        }
    }
}
