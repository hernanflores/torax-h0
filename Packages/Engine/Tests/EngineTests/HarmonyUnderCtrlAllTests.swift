import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de Harmony bajo Ctrl All (`pitch-harmony_20260912`, FR16, AC 12).
///
/// **Base + neto, como el resto de Ctrl All.** Cada Cycle de cada Track se
/// recalcula a cada clic como su estado de Harmony capturado más tantos pasos
/// como el neto acumulado, en su sentido. Es la mecánica que hace exacta la
/// vuelta de Ctrl All, y tiene un precio aceptado: **bajo Ctrl All Harmony no
/// depende del camino**. Un clic arriba y uno abajo vuelven a la base.
///
/// **La base no es un número**, así que se captura el estado entero —offsets y
/// cursor— de cada Cycle.
final class HarmonyUnderCtrlAllTests: XCTestCase {

    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int], harmony: Harmony = .clean) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: cMajor,
            harmony: harmony)
    }

    private var triad: Cycle { cycle([60, 64, 67]) }

    /// Dos Tracks con la misma tríada, uno de ellos ya movido.
    private var pattern: Pattern {
        let moved = triad.with(harmony: triad.harmonyMoved(by: 1))
        return Pattern()
            .replacing(Track(triad), at: 0)
            .replacing(Track(moved), at: 1)
    }

    private func harmony(_ pattern: Pattern, track: Int) -> Harmony? {
        pattern.track(at: track)?.cycle(at: 0)?.harmony
    }

    // MARK: - Desplazar

    /// Cada Track da los pasos desde su propia base.
    func testEachTrackStepsFromItsOwnBase() {
        var offset = CtrlAllOffset()
        let start = pattern

        let once = offset.apply(1, to: .harmony, in: start)
        let moved = offset.apply(1, to: .harmony, in: once)

        XCTAssertEqual(harmony(moved, track: 0), triad.harmonyMoved(by: 2))
        let base = triad.with(harmony: triad.harmonyMoved(by: 1))
        XCTAssertEqual(harmony(moved, track: 1), base.harmonyMoved(by: 2))
    }

    /// **Sin histéresis, y es la decisión**: tres arriba y uno abajo es la base
    /// más dos pasos arriba, no el ejemplo antihorario del PRD.
    func testUnderCtrlAllHarmonyIsNotPathDependent() {
        var offset = CtrlAllOffset()
        let start = pattern

        // Como en la entrada: cada clic recibe el Pattern que dejó el anterior.
        let up = offset.apply(3, to: .harmony, in: start)
        let back = offset.apply(-1, to: .harmony, in: up)

        XCTAssertEqual(harmony(back, track: 0), triad.harmonyMoved(by: 2))
        XCTAssertNotEqual(
            harmony(back, track: 0), triad.harmonyMoved(by: 3).offsetsMoved(by: -1, from: triad),
            "se comportó con histéresis")
    }

    /// Un clic arriba y uno abajo vuelven a la base exacta.
    func testUpAndDownReturnsToTheBase() {
        var offset = CtrlAllOffset()
        let start = pattern

        let up = offset.apply(1, to: .harmony, in: start)
        let back = offset.apply(-1, to: .harmony, in: up)

        XCTAssertEqual(back, start)
    }

    /// Harmony no tiene extremos contra los que saturar: el neto crece libre,
    /// como Rotate.
    func testTheNetGrowsFreely() {
        var offset = CtrlAllOffset()
        _ = offset.apply(40, to: .harmony, in: pattern)
        XCTAssertEqual(offset.amount(of: .harmony), 40)
    }

    // MARK: - Soltar

    /// Soltar devuelve el estado capturado de cada Cycle, cursor incluido.
    func testReleasingRestoresTheCapturedState() {
        var offset = CtrlAllOffset()
        let start = pattern

        let moved = offset.apply(5, to: .harmony, in: start)
        let restored = offset.restored(into: moved)

        XCTAssertEqual(harmony(restored, track: 0), harmony(start, track: 0))
        XCTAssertEqual(harmony(restored, track: 1), harmony(start, track: 1))
    }
}

extension Harmony {

    /// El paso siguiente de un Cycle con este estado, para comparar contra el
    /// comportamiento con histéresis.
    fileprivate func offsetsMoved(by delta: Int, from cycle: Cycle) -> Harmony {
        cycle.with(harmony: self).harmonyMoved(by: delta)
    }
}
