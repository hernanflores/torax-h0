import XCTest

@testable import Engine

/// Tests del hueco entre repeticiones: lo que Time mide y lo que Pace estira o
/// encoge.
///
/// **El hueco sale de la duración del Step, no del tempo.** `hueco =
/// duraciónDelStep × (Time / Division)`, que es lo que hace que Time sea un
/// valor de nota absoluto: un Track en 1/4 y otro en 1/16 con el mismo Time
/// repiten al mismo ritmo.
///
/// Los números de abajo son a 120 BPM: un Step de 1/16 dura 125 ms y uno de 1/4,
/// 500 ms.
final class RepeatGapTests: XCTestCase {

    private let sixteenthStep: Int64 = 125_000_000
    private let quarterStep: Int64 = 500_000_000

    // MARK: - Time

    /// Con Time 1/32 sobre un Step de 1/16, el hueco es medio Step.
    func testTheGapIsTheStepScaledByTimeOverDivision() {
        let gap = RepeatTime.default.gapNanoseconds(
            forStep: sixteenthStep, division: Division.sixteenth)
        XCTAssertEqual(gap, 62_500_000)
    }

    /// **Time es absoluto y no relativo al Step.** Dos Tracks con distinta
    /// Division y el mismo Time repiten al mismo ritmo.
    func testTheSameTimeRepeatsAtTheSameRateOnAnyDivision() {
        let fromSixteenth = RepeatTime.default.gapNanoseconds(
            forStep: sixteenthStep, division: Division.sixteenth)
        let fromQuarter = RepeatTime.default.gapNanoseconds(
            forStep: quarterStep, division: Division.quarter)
        XCTAssertEqual(fromSixteenth, fromQuarter)
    }

    /// La lista entera, contra el mismo Step: cada fracción más rápida acorta el
    /// hueco, y los tresillos caen donde deben —1/12 es dos tercios de 1/8—.
    func testEveryTimeInTheListShortensTheGap() {
        let gaps = RepeatTime.ordered.map {
            $0.gapNanoseconds(forStep: sixteenthStep, division: Division.sixteenth)
        }
        XCTAssertEqual(
            gaps,
            [
                250_000_000, 166_666_666, 125_000_000, 83_333_333, 62_500_000,
                41_666_666, 31_250_000, 20_833_333, 15_625_000,
            ])
    }

    // MARK: - Pace

    /// Con Pace 0 los huecos son todos iguales y valen Time: la tirada es recta.
    func testWithoutPaceEveryGapIsTheTimeGap() {
        let base: Int64 = 62_500_000
        for i in 1...4 {
            XCTAssertEqual(
                Pace.default.gapNanoseconds(forRepetition: i, of: 4, base: base),
                base,
                "hueco \(i)"
            )
        }
    }

    /// **Con +100 el último dura el doble que el primero**, y los intermedios
    /// interpolan linealmente.
    func testFullPositivePaceDoublesTheLastGap() {
        let base: Int64 = 60_000_000
        let pace = Pace(percent: 100)!
        let gaps = (1...4).map { pace.gapNanoseconds(forRepetition: $0, of: 4, base: base) }
        XCTAssertEqual(gaps, [60_000_000, 80_000_000, 100_000_000, 120_000_000])
    }

    /// **Con −100 el último dura la mitad que el primero.**
    func testFullNegativePaceHalvesTheLastGap() {
        let base: Int64 = 60_000_000
        let pace = Pace(percent: -100)!
        let gaps = (1...4).map { pace.gapNanoseconds(forRepetition: $0, of: 4, base: base) }
        XCTAssertEqual(gaps.last, 30_000_000)
        XCTAssertEqual(gaps.first, base)
        XCTAssertTrue(zip(gaps, gaps.dropFirst()).allSatisfy { $0 > $1 })
    }

    /// **`r` es exactamente recíproco entre `+p` y `−p`:** +50 da ×1,5 y −50 da
    /// ÷1,5. Es lo que hace que girar el knob a un lado y al otro la misma
    /// cantidad sean el mismo gesto.
    func testThePaceFactorIsExactlyReciprocal() {
        let base: Int64 = 90_000_000
        let up = Pace(percent: 50)!.gapNanoseconds(forRepetition: 4, of: 4, base: base)
        let down = Pace(percent: -50)!.gapNanoseconds(forRepetition: 4, of: 4, base: base)
        XCTAssertEqual(up, 135_000_000)
        XCTAssertEqual(down, 60_000_000)
    }

    /// **Con `n = 1` el único hueco vale Time, sea cual sea Pace**: la
    /// interpolación divide por `n − 1` y no hay tirada que recorrer.
    func testASingleRepetitionKeepsTheTimeGap() {
        let base: Int64 = 62_500_000
        for percent in [-100, -50, 0, 50, 100] {
            XCTAssertEqual(
                Pace(percent: percent)!.gapNanoseconds(forRepetition: 1, of: 1, base: base),
                base,
                "pace \(percent)"
            )
        }
    }

    /// El primer hueco vale Time con cualquier Pace: la curva arranca donde Time
    /// dice y se separa después.
    func testTheFirstGapIsAlwaysTheTimeGap() {
        let base: Int64 = 62_500_000
        for percent in [-100, -30, 0, 30, 100] {
            XCTAssertEqual(
                Pace(percent: percent)!.gapNanoseconds(forRepetition: 1, of: 8, base: base),
                base,
                "pace \(percent)"
            )
        }
    }

    /// Ningún hueco es cero ni negativo, en ninguna combinación del rango: un
    /// hueco de cero apilaría dos repeticiones en el mismo instante.
    func testNoGapEverCollapses() {
        for percent in Pace.validRange {
            let pace = Pace(percent: percent)!
            for n in 1...8 {
                for i in 1...n {
                    let gap = pace.gapNanoseconds(forRepetition: i, of: n, base: 1_000_000)
                    XCTAssertGreaterThan(gap, 0, "pace \(percent), \(i) de \(n)")
                }
            }
        }
    }
}
