import Engine
import XCTest
@testable import MIDI

/// Tests del scheduler look-ahead.
///
/// El scheduler decide *qué* Steps entran en la ventana futura que se entrega
/// a CoreMIDI. Los dos fallos que arruinarían el track son duplicar un Step
/// (nota repetida) y omitirlo (nota perdida) en el solape entre ventanas
/// sucesivas, así que ambos tienen test propio.
final class LookAheadSchedulerTests: XCTestCase {

    /// 120 BPM, 1/16 → un Step cada 125 ms.
    private func makeScheduler(startingAtStep step: Int = 0) -> LookAheadScheduler {
        LookAheadScheduler(
            timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth),
            startingAtStep: step
        )
    }

    private let stepNanoseconds: Int64 = 125_000_000

    // MARK: - Ventana simple

    func testHorizonAtOriginYieldsNoSteps() {
        var scheduler = makeScheduler()
        XCTAssertTrue(scheduler.advance(toHorizon: 0).isEmpty)
    }

    /// Un horizonte de exactamente un Step incluye el Step 0 pero no el 1:
    /// el limite superior es exclusivo, para que el Step 1 no se emita dos
    /// veces cuando la siguiente ventana empiece justo ahi.
    func testHorizonOfExactlyOneStepYieldsOnlyStepZero() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: stepNanoseconds), 0..<1)
    }

    func testHorizonCoveringFourStepsYieldsFourSteps() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: 4 * stepNanoseconds), 0..<4)
    }

    func testHorizonInsideAStepIncludesThatStep() {
        var scheduler = makeScheduler()
        // 1.5 Steps: incluye el 0 y el 1, no el 2.
        XCTAssertEqual(scheduler.advance(toHorizon: stepNanoseconds * 3 / 2), 0..<2)
    }

    // MARK: - Solape entre ventanas

    /// Volver a llamar con el mismo horizonte no puede reemitir nada.
    func testRepeatedHorizonYieldsNothingTheSecondTime() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: 4 * stepNanoseconds), 0..<4)
        XCTAssertTrue(scheduler.advance(toHorizon: 4 * stepNanoseconds).isEmpty)
    }

    /// Un horizonte que retrocede tampoco emite nada: el scheduler nunca
    /// vuelve atrás.
    func testHorizonGoingBackwardsYieldsNothing() {
        var scheduler = makeScheduler()
        _ = scheduler.advance(toHorizon: 4 * stepNanoseconds)
        XCTAssertTrue(scheduler.advance(toHorizon: stepNanoseconds).isEmpty)
    }

    /// El test central: ventanas sucesivas de tamaño irregular deben cubrir
    /// todos los Steps exactamente una vez, sin huecos ni repeticiones.
    func testSuccessiveWindowsCoverEveryStepExactlyOnce() {
        var scheduler = makeScheduler()
        var emitted: [Int] = []

        // Horizontes que avanzan de forma irregular, incluyendo saltos que
        // caen dentro de un Step y saltos de varios Steps de golpe.
        var horizon: Int64 = 0
        let increments: [Int64] = [37_000_000, 125_000_000, 9_000_000, 400_000_000, 1_000_000]
        for round in 0..<200 {
            horizon += increments[round % increments.count]
            emitted.append(contentsOf: scheduler.advance(toHorizon: horizon))
        }

        XCTAssertFalse(emitted.isEmpty)
        XCTAssertEqual(emitted, Array(0..<emitted.count),
                       "Los Steps emitidos deben ser 0,1,2,... sin huecos ni duplicados")
    }

    /// El limite superior de una ventana es el limite inferior de la siguiente.
    func testWindowsAreContiguous() {
        var scheduler = makeScheduler()
        var previousUpperBound = 0

        for round in 1...50 {
            let range = scheduler.advance(toHorizon: Int64(round) * 90_000_000)
            if !range.isEmpty {
                XCTAssertEqual(range.lowerBound, previousUpperBound,
                               "Hueco o solape en la ronda \(round)")
                previousUpperBound = range.upperBound
            }
        }
        XCTAssertGreaterThan(previousUpperBound, 0)
    }

    // MARK: - Arranque desplazado

    func testSchedulerCanStartAtANonZeroStep() {
        var scheduler = makeScheduler(startingAtStep: 10)
        XCTAssertEqual(scheduler.advance(toHorizon: 12 * stepNanoseconds), 10..<12)
    }

    // MARK: - Saltos grandes

    /// Un horizonte muy lejano no puede perder Steps: el scheduler debe
    /// devolver el rango completo aunque sea grande.
    func testLargeHorizonJumpYieldsAllStepsAtOnce() {
        var scheduler = makeScheduler()
        let range = scheduler.advance(toHorizon: 1_000 * stepNanoseconds)
        XCTAssertEqual(range, 0..<1_000)
    }

    // MARK: - Tempo de periodo inexacto

    /// A 174 BPM la duración de Step no es entera en nanosegundos. El conteo
    /// de Steps emitidos no puede desviarse del esperado.
    ///
    /// El oráculo cuenta iterando sobre `nanosecondOffset(forStep:)`, no con una
    /// división en aritmética real. Los dos difieren en un Step justo en los
    /// límites exactos —a 174 BPM el Step 116 cae en 9,999999999997 s, que
    /// redondea a 10 s clavados— y el contrato del scheduler está definido sobre
    /// los offsets redondeados, que son los que acaban en el timestamp de
    /// CoreMIDI.
    func testStepCountIsCorrectAtAwkwardTempo() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 174)!, division: .sixteenth)
        var scheduler = LookAheadScheduler(timeline: timeline, startingAtStep: 0)

        let horizon: Int64 = 10_000_000_000  // diez segundos
        let range = scheduler.advance(toHorizon: horizon)

        var expectedCount = 0
        while timeline.nanosecondOffset(forStep: expectedCount) < horizon {
            expectedCount += 1
        }
        XCTAssertEqual(range.count, expectedCount)
    }
}
