import XCTest

@testable import Engine

/// Tests de dónde cae el playhead de cada Track sobre su propio anillo.
///
/// **Con un Track el playhead era uno; con dieciséis son dieciséis, y no van en
/// fase.** Cada Track tiene su Division y sus Steps, así que su vuelta dura otra
/// cosa: a la misma marca de tiempo, dos Tracks pueden estar en puntos muy
/// distintos de sus respectivas vueltas. Un playhead compartido sería correcto
/// para uno y mentiría sobre los otros quince.
///
/// Es lo calculable de FR2, y por eso está aquí y no en `App`.
final class PatternPlayheadTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    // MARK: - Uno por Track

    func testThereIsOnePlayheadPerTrack() {
        let playheads = Playhead.forEachTrack(
            in: .initial, tempo: tempo, elapsedNanoseconds: 1_000_000)

        XCTAssertEqual(playheads.count, Pattern.trackCount)
    }

    /// **Los dieciséis existen aunque quince estén vacíos.** El anillo de un
    /// Track sin material se dibuja igual —si no, los demás se moverían de
    /// sitio— y su rejilla avanza igual: lo que no hace es emitir.
    func testEveryTrackHasAPlayheadEvenWithoutMaterial() {
        let playheads = Playhead.forEachTrack(
            in: Pattern(), tempo: tempo, elapsedNanoseconds: 500_000_000)

        XCTAssertEqual(playheads.count, Pattern.trackCount)
    }

    // MARK: - Cada uno sobre su propia rejilla

    /// **Dos Divisions distintas dan dos posiciones distintas**, que es la razón
    /// de que este tipo exista.
    ///
    /// A 120 BPM un Step de 1/16 dura 125 ms y uno de 1/8 dura 250 ms. Pasados
    /// 500 ms sobre anillos de 16 Steps: el de 1/16 lleva un cuarto de vuelta
    /// —4 de 16 Steps— y el de 1/8 lleva un octavo —2 de 16—.
    func testTwoDivisionsPutThePlayheadInDifferentPlaces() {
        let pattern = Pattern()
            .replacing(track(steps: 16, division: .sixteenth), at: 0)
            .replacing(track(steps: 16, division: .eighth), at: 1)

        let playheads = Playhead.forEachTrack(
            in: pattern, tempo: tempo, elapsedNanoseconds: 500_000_000)

        XCTAssertEqual(playheads[0].step, 4)
        XCTAssertEqual(playheads[1].step, 2)
        XCTAssertEqual(playheads[0].turn, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(playheads[1].turn, 0.125, accuracy: 0.000_001)
    }

    /// **Y dos longitudes de anillo también.** Con la misma Division, el que
    /// tiene menos Steps cierra su vuelta antes.
    func testTwoRingLengthsWrapAtDifferentTimes() {
        let pattern = Pattern()
            .replacing(track(steps: 16, division: .sixteenth), at: 0)
            .replacing(track(steps: 8, division: .sixteenth), at: 1)

        // 16 Steps de 125 ms son 2 s de vuelta; 8 Steps son 1 s. A 1,5 s el
        // primero va por la mitad y el segundo ya dio una vuelta y va por la
        // mitad de la segunda.
        let playheads = Playhead.forEachTrack(
            in: pattern, tempo: tempo, elapsedNanoseconds: 1_500_000_000)

        XCTAssertEqual(playheads[0].turn, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(playheads[1].turn, 0.5, accuracy: 0.000_001)
    }

    /// **En el origen los dieciséis están en fase**, sea cual sea su Division.
    /// Es lo que hace que arrancar el transporte se vea como un solo gesto y no
    /// como dieciséis cosas sueltas.
    func testAtTheOriginEveryTrackIsAtTheStart() {
        let pattern = Pattern()
            .replacing(track(steps: 16, division: .sixteenth), at: 0)
            .replacing(track(steps: 12, division: .quarter), at: 1)
            .replacing(track(steps: 7, division: .eighth), at: 2)

        for playhead in Playhead.forEachTrack(in: pattern, tempo: tempo, elapsedNanoseconds: 0) {
            XCTAssertEqual(playhead.step, 0)
            XCTAssertEqual(playhead.turn, 0)
        }
    }

    /// Cada playhead es exactamente el que `Playhead` calcula para ese Track:
    /// aquí no hay una segunda aritmética que pueda discrepar.
    func testEachPlayheadMatchesTheOneComputedForItsOwnTrack() {
        let one = track(steps: 12, division: .eighth)
        let pattern = Pattern().replacing(one, at: 9)
        let elapsed: Int64 = 777_000_000

        let expected = Playhead(
            elapsedNanoseconds: elapsed,
            timeline: MusicalTimeline(tempo: tempo, division: one.shape.division),
            steps: one.shape.steps
        )

        XCTAssertEqual(
            Playhead.forEachTrack(in: pattern, tempo: tempo, elapsedNanoseconds: elapsed)[9],
            expected)
    }

    // MARK: -

    private func track(steps: Int, division: Division) -> Cycle {
        Cycle(
            shape: Shape(
                steps: Steps(steps)!, pulses: Pulses(1)!, division: division))
    }
}
