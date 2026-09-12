import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de Pitch bajo Temp y Ctrl All (`pitch-harmony_20260912`, FR16, FR17,
/// AC 12).
///
/// **Pitch entra por la vía de siempre**: tiene posición —los grados— y rango
/// —±28—, así que Temp lo iguala y Ctrl All lo desplaza como a cualquier otro
/// parámetro. Lo único propio es el freno, que depende del pool de cada Cycle.
///
/// **Y la restauración es literal.** Soltar devuelve el offset capturado tal
/// cual, sin freno: si durante el hold Harmony subió un pitch, frenar al
/// restaurar dejaría Pitch en un valor que nadie puso.
final class PitchUnderTempAndCtrlAllTests: XCTestCase {

    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int], offset: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: cMajor,
            pitchOffset: PitchOffset(offset)!)
    }

    private func track(_ cycles: [Cycle]) -> Track {
        var track = Track(cycles[0]).withActiveCount(cycles.count)
        for (index, cycle) in cycles.enumerated() { track = track.replacing(cycle, at: index) }
        return track
    }

    private func offsets(_ track: Track) -> [Int] {
        (0..<track.activeCount).compactMap { track.cycle(at: $0)?.pitchOffset.degrees }
    }

    private func pattern(repeating cycle: Cycle) -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(Track(cycle), at: index)
        }
        return pattern
    }

    // MARK: - Temp

    /// Temp iguala Pitch en los Cycles activos y devuelve cada uno al soltar.
    func testTempEqualizesPitchAndRestoresEachCycle() {
        let start = track([cycle([60, 64], offset: 0), cycle([60, 64], offset: 3)])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(2, to: .pitch, in: start)
        XCTAssertEqual(offsets(overlaid), [2, 2])
        XCTAssertEqual(offsets(overlay.restored(into: overlaid)), [0, 3])
    }

    /// Cada Cycle frena contra su propio pool: igualar no saca a nadie de MIDI.
    func testTempBrakesEachCycleAgainstItsOwnPool() {
        let start = track([cycle([60], offset: 0), cycle([124], offset: 0)])
        var overlay = ParameterOverlay()

        XCTAssertEqual(
            offsets(overlay.apply(5, to: .pitch, in: start)), [5, 2], "E9 no pasa de G9")
    }

    /// **Restaurar es literal**: si Harmony subió el pitch más agudo durante el
    /// hold, Pitch vuelve igualmente al valor capturado.
    func testTempRestoresPitchLiterallyEvenIfHarmonyMovedMeanwhile() throws {
        let start = track([cycle([60, 120], offset: 2)])  // C4 C9, +2
        var overlay = ParameterOverlay()
        var held = overlay.apply(-2, to: .pitch, in: start)
        XCTAssertEqual(offsets(held), [0])

        // Harmony subió C9 tres grados, a F9: con Pitch +2 ya no cabría.
        let cycle = try XCTUnwrap(held.cycle(at: 0))
        let moved = cycle.with(harmony: Harmony.clean.with(offset: 3, at: 1))
        XCTAssertEqual(
            moved.applying(2, to: .pitch).pitchOffset, PitchOffset(1), "el arreglo no frena")
        held = held.replacing(moved, at: 0)

        XCTAssertEqual(offsets(overlay.restored(into: held)), [2])
    }

    // MARK: - Ctrl All

    /// Ctrl All desplaza conservando la distancia entre Tracks, y devuelve.
    func testCtrlAllDisplacesPitchAndRestoresIt() {
        var pattern = Pattern()
        pattern = pattern.replacing(track([cycle([60], offset: 1)]), at: 0)
        pattern = pattern.replacing(track([cycle([60], offset: -2)]), at: 1)
        var offset = CtrlAllOffset()

        let moved = offset.apply(3, to: .pitch, in: pattern)
        XCTAssertEqual(moved.track(at: 0).map(offsets), [4])
        XCTAssertEqual(moved.track(at: 1).map(offsets), [1])

        let restored = offset.restored(into: moved)
        XCTAssertEqual(restored.track(at: 0).map(offsets), [1])
        XCTAssertEqual(restored.track(at: 1).map(offsets), [-2])
    }

    /// **El tope es el recorrido del Track con más margen**, como para todo
    /// parámetro: los once Tracks en 0 pueden subir 28. Cuarenta clics contra él
    /// y uno de vuelta mueven algo; el Track de base 27 se queda frenado en 28.
    func testCtrlAllCapsPitchAtItsRange() {
        let pattern = Pattern().replacing(track([cycle([60], offset: 27)]), at: 0)
        var offset = CtrlAllOffset()

        let saturated = offset.apply(40, to: .pitch, in: pattern)
        XCTAssertEqual(saturated.track(at: 1).map(offsets), [28])
        XCTAssertEqual(saturated.track(at: 0).map(offsets), [28])

        let back = offset.apply(-1, to: .pitch, in: pattern)
        XCTAssertEqual(back.track(at: 1).map(offsets), [27], "el clic de vuelta no movió nada")
        XCTAssertEqual(back.track(at: 0).map(offsets), [28])
    }

    /// Un giro bloqueado en todos los Cycles no consume el giro inverso.
    func testCtrlAllReversesImmediatelyAfterPitchIsBlockedEverywhere() {
        let start = pattern(repeating: cycle([124], offset: 2))  // G9 al sonar
        var offset = CtrlAllOffset()

        let blocked = offset.apply(1, to: .pitch, in: start)
        XCTAssertEqual(blocked, start)
        XCTAssertTrue(offset.isEmpty)

        let reversed = offset.apply(-1, to: .pitch, in: blocked)
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(reversed.track(at: index).map(offsets), [1], "Track \(index + 1)")
        }
    }

    /// Ctrl All también restaura literal.
    func testCtrlAllRestoresPitchLiterally() throws {
        let pattern = Pattern().replacing(track([cycle([60, 120], offset: 2)]), at: 0)
        var offset = CtrlAllOffset()
        var held = offset.apply(-2, to: .pitch, in: pattern)

        let heldTrack = try XCTUnwrap(held.track(at: 0))
        let moved = try XCTUnwrap(heldTrack.cycle(at: 0))
            .with(harmony: Harmony.clean.with(offset: 3, at: 1))
        held = held.replacing(heldTrack.replacing(moved, at: 0), at: 0)

        XCTAssertEqual(offset.restored(into: held).track(at: 0).map(offsets), [2])
    }
}
