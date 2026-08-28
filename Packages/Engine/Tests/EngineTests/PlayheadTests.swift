import XCTest
@testable import Engine

/// Tests de la posición del playhead.
///
/// `product-guidelines.md` pide que el playhead recorra el anillo y vuelva, y
/// que **el movimiento derive del reloj**: no de un temporizador de la interfaz.
/// Este tipo es esa derivación, y es aritmética pura — lo único que necesita es
/// cuánto tiempo lleva sonando.
///
/// **Se mide contra el tiempo transcurrido, no contra el Step programado.** El
/// scheduler entrega los Steps por adelantado —hasta una ventana de look-ahead
/// antes de que suenen—, así que mostrar el último Step entregado pondría el
/// playhead por delante de lo que se oye. El anclaje es el origen temporal.
final class PlayheadTests: XCTestCase {

    private let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)

    /// A 120 BPM en 1/16, un Step dura 125 ms.
    private var stepNanoseconds: Int64 { 125_000_000 }

    // MARK: - Qué Step suena

    func testAtTheOriginThePlayheadIsOnTheFirstStep() {
        let playhead = Playhead(elapsedNanoseconds: 0, timeline: timeline, steps: Steps(16)!)
        XCTAssertEqual(playhead.step, 0)
    }

    func testThePlayheadAdvancesOneStepPerStepDuration() {
        for step in 0..<16 {
            let elapsed = stepNanoseconds * Int64(step)
            let playhead = Playhead(
                elapsedNanoseconds: elapsed, timeline: timeline, steps: Steps(16)!)
            XCTAssertEqual(playhead.step, step, "a \(elapsed) ns")
        }
    }

    /// Dentro de un Step el índice no cambia: el playhead se mueve de forma
    /// continua, pero el Step que suena es uno solo.
    func testThePlayheadStaysOnAStepUntilTheNextOneBegins() {
        let playhead = Playhead(
            elapsedNanoseconds: stepNanoseconds * 3 + stepNanoseconds - 1,
            timeline: timeline,
            steps: Steps(16)!
        )
        XCTAssertEqual(playhead.step, 3)
    }

    /// **El anillo se cierra.** Completar la vuelta devuelve el playhead al
    /// Step 0, que es la naturaleza cíclica que la forma circular existe para
    /// hacer evidente.
    func testThePlayheadWrapsAroundTheRing() {
        let full = stepNanoseconds * 16
        for lap in 0..<4 {
            let playhead = Playhead(
                elapsedNanoseconds: full * Int64(lap) + stepNanoseconds * 5,
                timeline: timeline,
                steps: Steps(16)!
            )
            XCTAssertEqual(playhead.step, 5, "vuelta \(lap)")
        }
    }

    func testTheRingLengthFollowsSteps() {
        for count in Steps.validRange {
            let elapsed = stepNanoseconds * Int64(count)
            let playhead = Playhead(
                elapsedNanoseconds: elapsed, timeline: timeline, steps: Steps(count)!)
            XCTAssertEqual(playhead.step, 0, "Steps \(count) — la vuelta no cerró donde debía")
        }
    }

    // MARK: - Dónde cae en la vuelta

    /// La fracción de vuelta es continua: sirve para dibujar el playhead entre
    /// dos posiciones, no solo sobre ellas.
    func testTurnIsContinuousWithinTheRing() {
        let quarter = Playhead(
            elapsedNanoseconds: stepNanoseconds * 4,
            timeline: timeline,
            steps: Steps(16)!
        )
        XCTAssertEqual(quarter.turn, 0.25, accuracy: 1e-9)

        let halfwayIntoAStep = Playhead(
            elapsedNanoseconds: stepNanoseconds * 4 + stepNanoseconds / 2,
            timeline: timeline,
            steps: Steps(16)!
        )
        XCTAssertEqual(halfwayIntoAStep.turn, 0.25 + (1.0 / 16.0) / 2, accuracy: 1e-9)
    }

    func testTurnStaysWithinTheTurn() {
        for nanoseconds in stride(
            from: Int64(0), to: stepNanoseconds * 40, by: Int(stepNanoseconds / 7))
        {
            let playhead = Playhead(
                elapsedNanoseconds: nanoseconds,
                timeline: timeline,
                steps: Steps(16)!
            )
            XCTAssertGreaterThanOrEqual(playhead.turn, 0, "a \(nanoseconds) ns")
            XCTAssertLessThan(playhead.turn, 1, "a \(nanoseconds) ns")
        }
    }

    /// El Step y la fracción de vuelta no pueden discrepar: la fracción siempre
    /// cae dentro del sector del Step que dice estar sonando.
    func testTurnAlwaysFallsInsideItsOwnStepSector() {
        for count in Steps.validRange {
            let step = Double(1) / Double(count)
            for nanoseconds in stride(
                from: Int64(0), to: stepNanoseconds * 20, by: Int(stepNanoseconds / 5))
            {
                let playhead = Playhead(
                    elapsedNanoseconds: nanoseconds,
                    timeline: timeline,
                    steps: Steps(count)!
                )
                let sector = Double(playhead.step) * step
                XCTAssertGreaterThanOrEqual(
                    playhead.turn, sector - 1e-9, "Steps \(count) · \(nanoseconds) ns")
                XCTAssertLessThan(
                    playhead.turn, sector + step + 1e-9, "Steps \(count) · \(nanoseconds) ns")
            }
        }
    }

    // MARK: - Bordes

    /// Un tiempo negativo no puede ocurrir con el transporte corriendo, pero si
    /// ocurriera no se inventa una posición fuera del anillo.
    func testNegativeElapsedTimeStaysAtTheStartOfTheRing() {
        let playhead = Playhead(elapsedNanoseconds: -1, timeline: timeline, steps: Steps(16)!)
        XCTAssertEqual(playhead.step, 0)
        XCTAssertEqual(playhead.turn, 0)
    }

    func testASingleStepRingIsAlwaysOnItsOnlyStep() {
        for nanoseconds in stride(
            from: Int64(0), to: stepNanoseconds * 5, by: Int(stepNanoseconds / 3))
        {
            let playhead = Playhead(
                elapsedNanoseconds: nanoseconds, timeline: timeline, steps: Steps(1)!)
            XCTAssertEqual(playhead.step, 0, "a \(nanoseconds) ns")
        }
    }
}
