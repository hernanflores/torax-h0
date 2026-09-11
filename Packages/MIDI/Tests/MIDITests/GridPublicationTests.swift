import Dispatch
import Engine
import XCTest

@testable import MIDI

/// Tests de la publicación del ancla hacia la interfaz — Fase 5 de
/// `division-hot-grid_20260911`, FR10 y FR11.
///
/// **El anillo tiene que medir con la misma rejilla que el sonido.** Desde que
/// la rejilla se reancla mientras suena, `Playhead` ya no puede suponer que se
/// mide desde el origen de Play: tiene que saber dónde ancló cada Track. Lo
/// publica el hilo del scheduler, que es quien reancla, con la forma de
/// `CyclePlaybackClock`: palabras atómicas, sin locks, y solo al reanclar.
///
/// **Se publican dos rejillas por Track, la vigente y la anterior**, por la
/// misma razón por la que `CyclePlaybackClock` guarda tres cursores: el
/// scheduler trabaja por adelantado, así que el ancla publicada puede estar
/// todavía en el futuro. Hasta que llegue, lo que suena es la anterior.
///
/// **Lo que cruza son enteros** (NFR5b): índice de Step, instante y Division.
/// Se reconstruye la `MusicalTimeline` en el lado de la interfaz con el tempo
/// que ella ya tiene, y por eso aquí se compara por igualdad exacta: si algo se
/// perdiera al empaquetar, el ancla leída no sería la del scheduler.
final class GridPublicationTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step de 1/16 dura 125 ms a 120 BPM.
    private let step: Int64 = 125_000_000

    private func cycle(division: Division, delay: Int = 0) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: .default, sustain: .default, probability: .default,
                timing: .default, delay: Delay(percent: delay)!)
        )
    }

    private func playGrid(_ division: Division = .sixteenth) -> MusicalTimeline {
        MusicalTimeline(tempo: tempo, division: division)
    }

    /// Un scheduler que ya publica en `clock`, como lo deja Play.
    private func scheduler(
        _ track: Track, reportingTo clock: CyclePlaybackClock, as index: Int = 0
    ) -> TrackScheduler {
        var scheduler = TrackScheduler(
            timeline: playGrid(track.cycle(at: 0)!.shape.division),
            material: .cycle(track.cycle(at: 0)!))
        scheduler.reportPlayback(to: clock, track: index)
        scheduler.refresh(with: track)
        return scheduler
    }

    private func advance(_ scheduler: inout TrackScheduler, toHorizon horizon: Int64) {
        scheduler.advance(toHorizon: horizon, refreshingFrom: nil) { _, _, _, _, _ in }
    }

    // MARK: - Sin reanclar, la rejilla de Play (FR11)

    /// **Un Track que no ha reanclado publica la rejilla de Play**, anclada en
    /// el Step 0 al instante 0: la vigente y la anterior son la misma. Es lo
    /// que hace que se dibuje exactamente como antes de este track.
    func testATrackThatHasNotRebasedPublishesThePlayGrid() {
        let clock = CyclePlaybackClock()
        var scheduler = scheduler(Track(cycle(division: .sixteenth)), reportingTo: clock)
        advance(&scheduler, toHorizon: 8 * step)

        let grid = clock.grids(tempo: tempo)[0]
        XCTAssertEqual(grid, PlaybackGrid(current: playGrid(), previous: playGrid()))
    }

    /// Un Track del que nadie ha publicado nada no tiene rejilla: la interfaz
    /// lo dibuja como siempre, sin inventar una.
    func testANeverPublishedTrackHasNoGrid() {
        let clock = CyclePlaybackClock()

        XCTAssertEqual(clock.grids(tempo: tempo).count, Pattern.trackCount)
        XCTAssertTrue(clock.grids(tempo: tempo).allSatisfy { $0 == nil })
    }

    // MARK: - Al reanclar, la rejilla nueva y la de antes (FR10)

    /// **El knob publica el ancla nueva**: el Step aún no entregado —el 4— con
    /// el instante que tenía, 500 ms, y la corchea. La anterior es la de Play.
    func testRebasingByTheKnobPublishesTheNewAnchor() {
        let clock = CyclePlaybackClock()
        var scheduler = scheduler(Track(cycle(division: .sixteenth)), reportingTo: clock)
        advance(&scheduler, toHorizon: 4 * step)

        scheduler.refresh(with: Track(cycle(division: .eighth)))

        let grid = clock.grids(tempo: tempo)[0]
        XCTAssertEqual(
            grid?.current,
            MusicalTimeline(
                tempo: tempo, division: .eighth, anchorStep: 4, anchorNanoseconds: 4 * step))
        XCTAssertEqual(grid?.previous, playGrid())
    }

    /// **El avance de Cycle también publica**: con el Cycle 2 en 1/8, el ancla
    /// cae en el Step 16 a los 2 s. Es la otra puerta por la que la rejilla
    /// cambia, y la interfaz no puede distinguirlas.
    func testTheCycleAdvancePublishesTheNewAnchor() {
        let clock = CyclePlaybackClock()
        let track = Track(cycle(division: .sixteenth))
            .withActiveCount(2)
            .replacing(cycle(division: .eighth), at: 1)
        var scheduler = scheduler(track, reportingTo: clock)
        advance(&scheduler, toHorizon: 17 * step)

        let grid = clock.grids(tempo: tempo)[0]
        XCTAssertEqual(
            grid?.current,
            MusicalTimeline(
                tempo: tempo, division: .eighth, anchorStep: 16, anchorNanoseconds: 16 * step))
        XCTAssertEqual(grid?.previous, playGrid())
    }

    /// Dos reanclajes seguidos: la anterior es la del primero, no la de Play.
    func testASecondRebaseKeepsTheFirstAsThePrevious() {
        let clock = CyclePlaybackClock()
        var scheduler = scheduler(Track(cycle(division: .sixteenth)), reportingTo: clock)
        advance(&scheduler, toHorizon: 4 * step)
        scheduler.refresh(with: Track(cycle(division: .eighth)))
        advance(&scheduler, toHorizon: 4 * step + 4 * 250_000_000)

        scheduler.refresh(with: Track(cycle(division: .thirtySecond)))

        let grid = clock.grids(tempo: tempo)[0]
        XCTAssertEqual(grid?.current.division, .thirtySecond)
        XCTAssertEqual(grid?.previous.division, .eighth)
        XCTAssertEqual(grid?.previous.anchorStep, 4)
    }

    /// **Con Delay negativo se publica el ancla ya retrasada** (enmienda de
    /// FR17): el anillo tiene que medir contra la rejilla que de verdad usa el
    /// scheduler, no contra la que tendría sin el retraso.
    func testTheDelayedAnchorIsTheOnePublished() {
        let clock = CyclePlaybackClock()
        var scheduler = scheduler(
            Track(cycle(division: .sixteenth, delay: -100)), reportingTo: clock)
        advance(&scheduler, toHorizon: 4 * step)

        scheduler.refresh(with: Track(cycle(division: .eighth, delay: -100)))

        let current = clock.grids(tempo: tempo)[0]?.current
        XCTAssertEqual(current?.anchorStep, 5)
        // El Step 5 estaba a 625 ms; el presupuesto crece de 125 a 250 ms.
        XCTAssertEqual(current?.anchorNanoseconds, 5 * step + 125_000_000)
    }

    // MARK: - Aislamiento

    /// Cada Track publica en su sitio: reanclar el Track 3 no toca la rejilla
    /// del 0.
    func testEachTrackPublishesInItsOwnSlot() {
        let clock = CyclePlaybackClock()
        var first = scheduler(Track(cycle(division: .sixteenth)), reportingTo: clock, as: 0)
        var fourth = scheduler(Track(cycle(division: .sixteenth)), reportingTo: clock, as: 3)
        advance(&first, toHorizon: 4 * step)
        advance(&fourth, toHorizon: 4 * step)

        fourth.refresh(with: Track(cycle(division: .eighth)))

        let grids = clock.grids(tempo: tempo)
        XCTAssertEqual(grids[0]?.current, playGrid())
        XCTAssertEqual(grids[3]?.current.division, .eighth)
    }

    // MARK: - Sin locks y sin lecturas partidas

    /// **La interfaz nunca lee una rejilla a medias.** El scheduler publica dos
    /// rejillas alternas tan deprisa como puede mientras otro hilo lee: cada
    /// lectura tiene que ser exactamente una de las dos, nunca el índice de una
    /// con el instante de la otra.
    func testAReaderNeverSeesATornGrid() {
        let clock = CyclePlaybackClock()
        let one = MusicalTimeline(
            tempo: tempo, division: .eighth, anchorStep: 7, anchorNanoseconds: 111_000_000)
        let other = MusicalTimeline(
            tempo: tempo, division: .thirtySecond, anchorStep: 9_000,
            anchorNanoseconds: 999_000_000_000)
        let valid = [
            PlaybackGrid(current: one, previous: other),
            PlaybackGrid(current: other, previous: one),
        ]
        clock.publishGrid(track: 0, current: one, previous: other)

        let running = AtomicFlag(true)
        let writerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var flip = false
            while running.value {
                clock.publishGrid(
                    track: 0, current: flip ? one : other, previous: flip ? other : one)
                flip.toggle()
            }
            writerDone.signal()
        }

        for _ in 0..<20_000 {
            guard let grid = clock.grids(tempo: tempo)[0] else { continue }
            XCTAssertTrue(valid.contains(grid), "lectura partida: \(grid)")
        }
        running.value = false
        writerDone.wait()
    }
}
