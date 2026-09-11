import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Aislamiento entre Tracks al cambiar una Division — Fase 2 de
/// `division-hot-grid_20260911`.
///
/// **Dieciséis rejillas, no una.** `PatternScheduler` construye una
/// `MusicalTimeline` por Track porque cada uno lleva su propia Division, y
/// ahora esas rejillas además cambian solas. El riesgo que estos tests cierran
/// es que reanclar una toque a las demás: girar el knob de un Track no puede
/// mover ni un instante de los otros quince (criterio 6).
final class DivisionIsolationTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step de 1/16 dura 125 ms a 120 BPM.
    private let stepNanoseconds: Int64 = 125_000_000

    private func cycle(division: Division, pitch: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    private func pattern(_ cycles: [Int: Cycle]) -> Pattern {
        cycles.reduce(into: Pattern()) { $0 = $0.replacing($1.value, at: $1.key) }
    }

    /// Avanza una ventana y devuelve los offsets emitidos por Track.
    private func emit(
        _ scheduler: inout PatternScheduler,
        toHorizon horizon: Int64,
        from handoff: PatternHandoff?
    ) -> [Int: [Int64]] {
        var offsets: [Int: [Int64]] = [:]
        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) {
            track, _, _, _, _, offset in
            offsets[track, default: []].append(offset)
        }
        return offsets
    }

    // MARK: - Criterio 6

    /// **Cambiar la Division del Track 0 no mueve ni un offset de los demás.**
    /// Se comparan dos reproducciones idénticas salvo por el giro de knob en uno
    /// solo de los Tracks, y los otros dos tienen que emitir exactamente lo
    /// mismo en las dos.
    func testChangingOneTracksDivisionLeavesTheOthersUntouched() {
        let start = pattern([
            0: cycle(division: .sixteenth, pitch: 60),
            1: cycle(division: .sixteenth, pitch: 62),
            2: cycle(division: .eighth, pitch: 64),
        ])
        let turned = pattern([
            0: cycle(division: .quarter, pitch: 60),
            1: cycle(division: .sixteenth, pitch: 62),
            2: cycle(division: .eighth, pitch: 64),
        ])

        var withTurn = PatternScheduler(tempo: tempo, pattern: start)
        var withoutTurn = PatternScheduler(tempo: tempo, pattern: start)
        let turnedHandoff = PatternHandoff(start)
        let steadyHandoff = PatternHandoff(start)

        var turnedOffsets: [Int: [Int64]] = [:]
        var steadyOffsets: [Int: [Int64]] = [:]
        var horizon: Int64 = 0

        for window in 0..<40 {
            horizon += 20_000_000
            // El giro entra por el handoff, que es por donde entra de verdad.
            if window == 6 { turnedHandoff.publish(turned) }

            for (track, offsets) in emit(&withTurn, toHorizon: horizon, from: turnedHandoff) {
                turnedOffsets[track, default: []].append(contentsOf: offsets)
            }
            for (track, offsets) in emit(&withoutTurn, toHorizon: horizon, from: steadyHandoff) {
                steadyOffsets[track, default: []].append(contentsOf: offsets)
            }
        }

        XCTAssertNotEqual(
            turnedOffsets[0], steadyOffsets[0],
            "El Track que giró el knob tendría que haber cambiado de rejilla")
        XCTAssertEqual(turnedOffsets[1], steadyOffsets[1])
        XCTAssertEqual(turnedOffsets[2], steadyOffsets[2])
        XCTAssertFalse(steadyOffsets[1]?.isEmpty ?? true)
        XCTAssertFalse(steadyOffsets[2]?.isEmpty ?? true)
    }

    /// Y dos Tracks que giran **a la vez** llegan cada uno a su propia rejilla,
    /// sin contagiarse la del otro: es el caso que Ctrl All va a producir.
    func testTwoTracksCanEndUpOnDifferentGrids() {
        let start = pattern([
            0: cycle(division: .sixteenth, pitch: 60),
            1: cycle(division: .sixteenth, pitch: 62),
        ])
        let turned = pattern([
            0: cycle(division: .eighth, pitch: 60),
            1: cycle(division: .thirtySecond, pitch: 62),
        ])

        var scheduler = PatternScheduler(tempo: tempo, pattern: start)
        let handoff = PatternHandoff(start)
        _ = emit(&scheduler, toHorizon: 4 * stepNanoseconds, from: handoff)

        handoff.publish(turned)
        let offsets = emit(&scheduler, toHorizon: 20 * stepNanoseconds, from: handoff)

        XCTAssertEqual(spacing(of: offsets[0]), 250_000_000)
        XCTAssertEqual(spacing(of: offsets[1]), 62_500_000)
    }

    /// La separación entre offsets consecutivos, exigiendo que sea constante.
    private func spacing(of offsets: [Int64]?) -> Int64? {
        guard let offsets, offsets.count > 2 else { return nil }
        let deltas = zip(offsets.dropFirst(), offsets).map(-)
        return Set(deltas).count == 1 ? deltas.first : nil
    }
}
