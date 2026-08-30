import XCTest
@testable import Engine

/// Tests del modelo de tiempo musical.
///
/// El criterio de éxito del track es timing estable, así que estos tests son
/// la primera línea de defensa: si la aritmética del reloj deriva, ninguna
/// arquitectura de scheduling posterior lo puede arreglar.
final class MusicalTimeTests: XCTestCase {

    // MARK: - Division

    func testSixteenthIsOneSixteenthOfAWholeNote() {
        XCTAssertEqual(Division.sixteenth.numerator, 1)
        XCTAssertEqual(Division.sixteenth.denominator, 16)
    }

    func testQuarterLastsFourTimesASixteenth() {
        let tempo = Tempo(beatsPerMinute: 120)!
        let sixteenth = MusicalTimeline(tempo: tempo, division: .sixteenth)
        let quarter = MusicalTimeline(tempo: tempo, division: .quarter)

        XCTAssertEqual(
            quarter.stepDurationNanoseconds,
            sixteenth.stepDurationNanoseconds * 4,
            accuracy: 1)
    }

    // MARK: - Step duration

    /// A 120 BPM la negra dura 500 ms, así que la semicorchea dura 125 ms.
    func testStepDurationAt120BPM() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
        XCTAssertEqual(timeline.stepDurationNanoseconds, 125_000_000, accuracy: 1)
    }

    /// A 60 BPM la negra dura 1 s, así que la semicorchea dura 250 ms.
    func testStepDurationAt60BPM() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 60)!, division: .sixteenth)
        XCTAssertEqual(timeline.stepDurationNanoseconds, 250_000_000, accuracy: 1)
    }

    /// 174 BPM es un tempo con periodo no exacto en nanosegundos: es el caso
    /// que revela errores de redondeo acumulativo.
    func testStepDurationAt174BPM() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 174)!, division: .sixteenth)
        let expected = 60.0 / 174.0 * 4.0 / 16.0 * 1_000_000_000.0
        XCTAssertEqual(timeline.stepDurationNanoseconds, expected, accuracy: 1)
    }

    // MARK: - Origen y progresión

    func testStepZeroIsTheOrigin() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 0), 0)
    }

    func testStepOffsetsAdvanceByOneStepDuration() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 1), 125_000_000)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 4), 500_000_000)
    }

    // MARK: - Ausencia de deriva

    /// El test central: sobre 1000 steps a un tempo de periodo inexacto, el
    /// offset calculado no puede separarse del valor exacto más de 1 ns.
    ///
    /// Un reloj que acumula (`t += paso`) falla aquí; uno que multiplica por el
    /// índice, no. Esa es la razón de diseñarlo así.
    func testNoDriftOverAThousandStepsAt174BPM() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 174)!, division: .sixteenth)
        let exactStep = 60.0 / 174.0 * 4.0 / 16.0 * 1_000_000_000.0

        for step in stride(from: 0, through: 1000, by: 1) {
            let expected = exactStep * Double(step)
            let actual = Double(timeline.nanosecondOffset(forStep: step))
            XCTAssertEqual(
                actual, expected, accuracy: 1,
                "Deriva detectada en el step \(step)")
        }
    }

    /// El intervalo entre steps consecutivos se mantiene estable: ningún par
    /// de steps puede separarse del nominal más de 1 ns.
    func testConsecutiveStepIntervalsStayStable() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 174)!, division: .sixteenth)
        let nominal = timeline.stepDurationNanoseconds

        for step in 1...1000 {
            let delta =
                Double(timeline.nanosecondOffset(forStep: step))
                - Double(timeline.nanosecondOffset(forStep: step - 1))
            XCTAssertEqual(
                delta, nominal, accuracy: 1,
                "Intervalo irregular entre los steps \(step - 1) y \(step)")
        }
    }

    // MARK: - Validación de Tempo

    func testTempoRejectsValuesOutsideMusicalRange() {
        XCTAssertNil(Tempo(beatsPerMinute: 0))
        XCTAssertNil(Tempo(beatsPerMinute: -120))
        XCTAssertNil(Tempo(beatsPerMinute: 19))
        XCTAssertNil(Tempo(beatsPerMinute: 301))
    }

    func testTempoAcceptsMusicalRangeIncludingBounds() {
        XCTAssertNotNil(Tempo(beatsPerMinute: 20))
        XCTAssertNotNil(Tempo(beatsPerMinute: 174))
        XCTAssertNotNil(Tempo(beatsPerMinute: 300))
    }
}

extension MusicalTimeTests {

    func testDivisionRejectsNonPositiveComponents() {
        XCTAssertNil(Division(numerator: 0, denominator: 16))
        XCTAssertNil(Division(numerator: 1, denominator: 0))
        XCTAssertNil(Division(numerator: -1, denominator: 4))
        XCTAssertNil(Division(numerator: 1, denominator: -16))
    }

    /// Los tresillos son numeradores distintos de 1: el tipo debe admitirlos.
    func testDivisionAcceptsTupletRatios() {
        let triplet = Division(numerator: 1, denominator: 12)
        XCTAssertNotNil(triplet)
        XCTAssertEqual(triplet?.denominator, 12)

        let dotted = Division(numerator: 3, denominator: 16)
        XCTAssertNotNil(dotted)
        XCTAssertEqual(dotted?.numerator, 3)
    }
}
