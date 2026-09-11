import XCTest

@testable import Engine

/// Ver la nota de `PatternTests`: `Pattern` a secas es ambiguo en un target de
/// test.
private typealias Pattern = Engine.Pattern

/// Tests del playhead contra el ancla — Fase 5 de `division-hot-grid_20260911`,
/// FR9 y FR11.
///
/// **Lo que se ve y lo que suena no pueden discrepar**, y `Playhead.swift` lo
/// tiene escrito como invariante. Mientras la rejilla no cambiaba, medir desde
/// el origen de Play era correcto. En cuanto un Track reancla, el sonido mide
/// desde su corte y el dibujo tiene que medir desde el mismo sitio: si no, el
/// playhead marca el Step que sonaría con la Division nueva desde Play, que no
/// es ninguno de los que suenan.
///
/// Los números son a 120 BPM. La rejilla reanclada va en 1/16 hasta el Step 4,
/// a los 500 ms, y en 1/8 desde ahí: el Step 6 cae a los 1000 ms.
final class AnchoredPlayheadTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let sixteen = Steps(16)!

    private var playGrid: MusicalTimeline { MusicalTimeline(tempo: tempo, division: .sixteenth) }

    /// 1/16 hasta el Step 4 y 1/8 desde ahí.
    private var rebased: MusicalTimeline { playGrid.rebased(to: .eighth, atStep: 4) }

    // MARK: - El Step que suena (FR9, criterio 10)

    /// **Un Track reanclado marca el Step que suena.** A los 1000 ms suena el
    /// Step 6. Medir 1/8 desde Play daría el 4, y medir 1/16 daría el 8.
    func testARebasedTrackMarksTheStepThatSounds() {
        let playhead = Playhead(elapsedNanoseconds: 1_000_000_000, timeline: rebased, steps: sixteen)

        XCTAssertEqual(playhead.step, 6)
    }

    /// La fracción de vuelta también se mide desde el ancla: medio Step de 1/8
    /// después del Step 6 es el 6,5 de 16.
    func testTheTurnFractionIsMeasuredFromTheAnchor() {
        let playhead = Playhead(elapsedNanoseconds: 1_125_000_000, timeline: rebased, steps: sixteen)

        XCTAssertEqual(playhead.turn, 6.5 / 16, accuracy: 1e-9)
    }

    /// Y el anillo se cierra donde lo cierra el scheduler: el Step 20 —el 4 de
    /// la vuelta siguiente— cae a 500 + 16 × 250 ms.
    func testTheRingWrapsOnTheRebasedGrid() {
        let playhead = Playhead(elapsedNanoseconds: 4_500_000_000, timeline: rebased, steps: sixteen)

        XCTAssertEqual(playhead.step, 4)
    }

    /// **Un instante anterior al ancla** —la rejilla extendida hacia atrás—
    /// sigue cayendo dentro del anillo, sin posiciones negativas. Ancla en el
    /// Step 100 a los 12,5 s con fusas de 62,5 ms: a 1 s la cuenta da el
    /// Step −84, que en un anillo de 16 es el 12.
    func testAnInstantBeforeTheAnchorStillLandsOnTheRing() {
        let late = playGrid.rebased(to: .thirtySecond, atStep: 100)
        let playhead = Playhead(elapsedNanoseconds: 1_000_000_000, timeline: late, steps: sixteen)

        XCTAssertEqual(playhead.step, 12)
        XCTAssertEqual(playhead.turn, 0.75, accuracy: 1e-9)
    }

    // MARK: - Sin reanclar, lo de siempre (FR11)

    /// **La rejilla de Play da exactamente lo de antes.** Los tests de
    /// `PlayheadTests` lo fijan sin tocarlos; este lo dice en una línea contra
    /// el cálculo directo desde el origen.
    func testThePlayGridGivesExactlyWhatItAlwaysGave() {
        for elapsed in stride(from: Int64(0), to: 8_000_000_000, by: 37_000_001) {
            let playhead = Playhead(elapsedNanoseconds: elapsed, timeline: playGrid, steps: sixteen)
            let ring = 125_000_000.0 * 16
            let expected = Double(elapsed).truncatingRemainder(dividingBy: ring) / ring

            XCTAssertEqual(playhead.turn, expected, "a \(elapsed) ns")
        }
    }

    // MARK: - El ancla todavía no suena

    /// **Antes del ancla manda la rejilla anterior.** El scheduler reancla por
    /// delante de lo que suena, así que durante esa ventana lo que se oye sigue
    /// midiéndose con la de antes.
    func testBeforeTheAnchorThePreviousGridRules() {
        let grid = PlaybackGrid(current: rebased, previous: playGrid)

        XCTAssertEqual(grid.timeline(atNanoseconds: 499_999_999), playGrid)
        XCTAssertEqual(grid.timeline(atNanoseconds: 500_000_000), rebased)
        XCTAssertEqual(grid.timeline(atNanoseconds: 2_000_000_000), rebased)
    }

    // MARK: - Los dieciséis

    /// Con rejillas publicadas, cada Track se dibuja contra la suya; sin ella,
    /// como siempre. El Track 0 reanclado marca el 6, y el 1 sin publicar marca
    /// lo mismo que sin rejillas.
    func testEachTrackIsDrawnAgainstItsOwnPublishedGrid() {
        var grids: [PlaybackGrid?] = Array(repeating: nil, count: Pattern.trackCount)
        grids[0] = PlaybackGrid(current: rebased, previous: playGrid)

        let anchored = Playhead.forEachTrack(
            in: .initial, tempo: tempo, elapsedNanoseconds: 1_000_000_000, grids: grids)
        let plain = Playhead.forEachTrack(
            in: .initial, tempo: tempo, elapsedNanoseconds: 1_000_000_000)

        XCTAssertEqual(anchored[0].step, 6)
        XCTAssertEqual(Array(anchored.dropFirst()), Array(plain.dropFirst()))
    }

    // MARK: - El Cycle en curso mide con el mismo ancla

    /// **El Cycle en curso se deduce con la misma rejilla.** Cycle 1 en 1/16 y
    /// Cycle 2 en 1/8: la segunda vuelta empieza a los 2 s y dura 4. A los 5 s
    /// sigue sonando el Cycle 2, en el Step 28, a tres cuartos de su vuelta.
    /// Medido con el Step del Cycle 1, como hasta ahora, serían 40 Steps y ya
    /// habría vuelto al Cycle 1.
    func testTheCycleInCourseIsDeducedWithTheSameGrid() {
        let first = Cycle(shape: Shape(steps: sixteen, pulses: Pulses(1)!, division: .sixteenth))
        let second = Cycle(shape: Shape(steps: sixteen, pulses: Pulses(1)!, division: .eighth))
        let track = Track(first).withActiveCount(2).replacing(second, at: 1)
        let phase = CyclePosition.Phase(cycle: 1, previousCycle: 0, turnStartStep: 16)
        let grid = PlaybackGrid(current: playGrid.rebased(to: .eighth, atStep: 16), previous: playGrid)

        let position = CyclePosition(
            elapsedNanoseconds: 5_000_000_000, track: track, tempo: tempo, phase: phase, grid: grid)

        XCTAssertEqual(position.cycle, 1)
        XCTAssertEqual(position.turn, 0.75, accuracy: 1e-9)
    }
}
