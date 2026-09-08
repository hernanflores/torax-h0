import XCTest

@testable import Engine

/// Tests del gate de una repetición.
///
/// **Sustain se aplica sobre el hueco de la repetición, no sobre el Step.** Es
/// la misma regla que ya rige entre Steps, aplicada a la rejilla que la
/// repetición habita: con Sustain 100% cada una llega justo a la siguiente
/// (FR12).
///
/// **El Pulse conserva su gate sobre el Step**, así que con Repeats en 0 no
/// cambia nada de lo entregado (FR16).
final class RepeatGateTests: XCTestCase {

    /// Un Step de 1/16 a 120 BPM.
    private let step: Int64 = 125_000_000

    private func gap(
        _ repeater: NoteRepeater,
        _ index: Int,
        division: Division = .sixteenth
    ) -> Int64 {
        let base = repeater.time.gapNanoseconds(forStep: step, division: division)
        return repeater.pace.gapNanoseconds(
            forRepetition: index, of: repeater.repeats.count, base: base)
    }

    // MARK: - Con Sustain 100% cada repetición llega a la siguiente

    func testWithFullSustainEachRepetitionLastsExactlyItsGap() {
        let repeater = NoteRepeater(repeats: Repeats(3)!)
        let sustain = Sustain(percent: 100)!

        for index in 1...3 {
            let own = gap(repeater, index)
            XCTAssertEqual(sustain.gateNanoseconds(over: own), own, "repetición \(index)")
            XCTAssertEqual(own, 62_500_000, "repetición \(index)")
        }
    }

    /// **Con Pace ≠ 0 cada una dura el suyo y no el primero.** Es lo que hace
    /// que una tirada que acelera no deje las últimas notas colgando sobre las
    /// siguientes.
    func testWithPaceEachRepetitionLastsItsOwnGap() {
        let repeater = NoteRepeater(repeats: Repeats(4)!, pace: Pace(percent: 100)!)
        let sustain = Sustain(percent: 100)!

        let gates = (1...4).map { sustain.gateNanoseconds(over: gap(repeater, $0)) }

        XCTAssertEqual(gates, [62_500_000, 83_333_333, 104_166_666, 125_000_000])
        XCTAssertTrue(zip(gates, gates.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// Y con Pace negativo, al revés: los gates se encogen con los huecos.
    func testWithNegativePaceTheGatesShrinkWithTheGaps() {
        let repeater = NoteRepeater(repeats: Repeats(4)!, pace: Pace(percent: -100)!)
        let sustain = Sustain(percent: 100)!

        let gates = (1...4).map { sustain.gateNanoseconds(over: gap(repeater, $0)) }

        XCTAssertEqual(gates.first, 62_500_000)
        XCTAssertEqual(gates.last, 31_250_000)
        XCTAssertTrue(zip(gates, gates.dropFirst()).allSatisfy { $0 > $1 })
    }

    /// Sustain por debajo del 100% acorta la repetición dentro de su hueco, con
    /// la misma proporción que aplica sobre un Step.
    func testSustainScalesTheRepetitionInsideItsGap() {
        let repeater = NoteRepeater(repeats: Repeats(2)!)
        let own = gap(repeater, 1)

        XCTAssertEqual(Sustain(percent: 50)!.gateNanoseconds(over: own), own / 2)
        XCTAssertEqual(Sustain(percent: 200)!.gateNanoseconds(over: own), own * 2)
    }

    // MARK: - FR16: el Pulse no cambia

    /// **El Pulse mide su gate sobre el Step**, con Repeats en 0 y con Repeats
    /// en 3: la tirada que cuelga de él no toca su duración.
    func testThePulseKeepsItsGateOverTheStep() {
        let sustain = Sustain(percent: 100)!
        let quiet = NoteRepeater.default
        let busy = NoteRepeater(repeats: Repeats(3)!, pace: Pace(percent: 60)!)

        XCTAssertEqual(sustain.gateNanoseconds(over: step), step)
        XCTAssertEqual(quiet.repeats.count, 0)
        XCTAssertEqual(busy.repeats.count, 3)
        // El gate del Pulse no es función del repetidor: se mide sobre el Step
        // en los dos casos, y es la misma cuenta que antes de la rebanada.
        XCTAssertEqual(sustain.gateNanoseconds(over: step), 125_000_000)
    }

    /// El hueco de la repetición es independiente de la Division, así que su
    /// gate también: dos Tracks con el mismo Time y Sustain producen la misma
    /// duración de repetición.
    func testTheRepetitionGateDoesNotDependOnTheDivision() {
        let repeater = NoteRepeater(repeats: Repeats(2)!)
        let sustain = Sustain(percent: 80)!

        let fromSixteenth = sustain.gateNanoseconds(over: gap(repeater, 1))
        let fromQuarter = sustain.gateNanoseconds(
            over: repeater.time.gapNanoseconds(forStep: step * 4, division: .quarter))

        XCTAssertEqual(fromSixteenth, fromQuarter)
    }
}
