import XCTest

@testable import Engine

/// Tests de la rejilla con ancla — Fase 1 de `division-hot-grid_20260911`.
///
/// **Por qué hace falta un ancla.** `MusicalTimeline` multiplica el índice de
/// Step por la duración de Step contra el origen de Play. Eso es lo que la deja
/// sin deriva, y no se toca; pero significa que **no sabe decir «de aquí en
/// adelante, los Steps duran otra cosa»**: cambiarle la Division recalcularía
/// también todo el pasado, y el Step siguiente saltaría a un instante que no
/// tiene nada que ver con el que se estaba tocando.
///
/// El ancla es un índice de Step y el instante que ese Step tenía bajo la
/// rejilla anterior. El pasado queda como sonó y el futuro obedece al knob
/// (FR6).
///
/// Aquí solo se prueba el **cómo**: valor puro, sin hilo, sin reloj y sin
/// CoreMIDI. Quién decide *cuándo* reanclar es del hilo del scheduler y se
/// prueba en `MIDI`.
final class AnchoredTimelineTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    // MARK: - Sin ancla, la rejilla de siempre

    /// **La rejilla de siempre es un caso particular de la anclada**: anclada en
    /// el Step 0 al instante 0. Si esto falla, el resto del proyecto se entera.
    func testAFreshTimelineIsAnchoredAtTheOrigin() {
        let timeline = MusicalTimeline(tempo: tempo, division: .sixteenth)

        XCTAssertEqual(timeline.anchorStep, 0)
        XCTAssertEqual(timeline.anchorNanoseconds, 0)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 0), 0)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 4), 500_000_000)
    }

    // MARK: - El instante del corte se conserva (FR6)

    /// **El Step del ancla cae donde ya iba a caer.** Es toda la promesa de FR6:
    /// girar el knob no adelanta ni retrasa el Step que estaba a punto de sonar,
    /// solo cambia lo que duran los siguientes.
    func testTheAnchoredStepKeepsTheInstantItHadBefore() {
        let original = MusicalTimeline(tempo: tempo, division: .sixteenth)
        let instant = original.nanosecondOffset(forStep: 7)

        let rebased = original.rebased(to: .eighth, atStep: 7)

        XCTAssertEqual(rebased.nanosecondOffset(forStep: 7), instant)
        XCTAssertEqual(rebased.anchorStep, 7)
        XCTAssertEqual(rebased.anchorNanoseconds, instant)
    }

    /// **Un ancla retrasada** mueve el Step del corte exactamente lo pedido, y
    /// los siguientes se miden desde ahí con la Division nueva. Es lo que usa el
    /// scheduler cuando un reanclaje hace crecer el presupuesto de Delay
    /// negativo (enmienda de FR17).
    func testADelayedAnchorMovesTheCutStepByExactlyTheDelay() {
        let original = MusicalTimeline(tempo: tempo, division: .sixteenth)
        let instant = original.nanosecondOffset(forStep: 7)

        let rebased = original.rebased(to: .eighth, atStep: 7, delayedBy: 125_000_000)

        XCTAssertEqual(rebased.anchorNanoseconds, instant + 125_000_000)
        XCTAssertEqual(rebased.nanosecondOffset(forStep: 7), instant + 125_000_000)
        XCTAssertEqual(rebased.nanosecondOffset(forStep: 8), instant + 375_000_000)
    }

    /// Sin retraso es el reanclaje de siempre: el parámetro no cambia nada si
    /// no se pide.
    func testAZeroDelayIsTheUsualRebase() {
        let original = MusicalTimeline(tempo: tempo, division: .sixteenth)

        XCTAssertEqual(
            original.rebased(to: .eighth, atStep: 7, delayedBy: 0),
            original.rebased(to: .eighth, atStep: 7))
    }

    /// Y la Division nueva es la que queda, no la vieja.
    func testRebasingAdoptsTheNewDivision() {
        let rebased = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .eighth, atStep: 7)

        XCTAssertEqual(rebased.division, .eighth)
        XCTAssertEqual(rebased.tempo, tempo)
    }

    // MARK: - Del ancla en adelante manda la Division nueva (criterio 1)

    /// 1/16 → 1/8 **dobla** el tiempo entre Steps. A 120 BPM, de 125 ms a 250.
    func testFromTheAnchorOnwardsTheNewDivisionSetsTheSpacing() {
        let rebased = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .eighth, atStep: 7)

        let anchor = rebased.nanosecondOffset(forStep: 7)
        XCTAssertEqual(rebased.nanosecondOffset(forStep: 8) - anchor, 250_000_000)
        XCTAssertEqual(rebased.nanosecondOffset(forStep: 9) - anchor, 500_000_000)
    }

    /// 1/16 → 1/32 lo **divide**. Es el otro extremo del mismo criterio.
    func testRebasingToAFasterDivisionHalvesTheSpacing() {
        let rebased = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .thirtySecond, atStep: 7)

        let anchor = rebased.nanosecondOffset(forStep: 7)
        XCTAssertEqual(rebased.nanosecondOffset(forStep: 8) - anchor, 62_500_000)
    }

    // MARK: - Reanclar no cuesta nada si nada cambia

    /// **Es el caso de cada ventana.** El hilo del scheduler va a comparar la
    /// Division vigente con la del material en cada ventana y, casi siempre, van
    /// a ser la misma. Reanclar entonces no puede mover ni un offset, o girar
    /// nada produciría un cambio de fase.
    func testRebasingToTheSameDivisionMovesNothing() {
        let original = MusicalTimeline(tempo: tempo, division: .sixteenth)
        let rebased = original.rebased(to: .sixteenth, atStep: 11)

        for step in 11...40 {
            XCTAssertEqual(
                rebased.nanosecondOffset(forStep: step),
                original.nanosecondOffset(forStep: step),
                "El Step \(step) se movió al reanclar sobre la misma Division")
        }
    }

    // MARK: - Sin deriva acumulada (NFR3, criterio 4)

    /// **Tres reanclajes seguidos no acumulan error.** El ancla guarda un
    /// instante ya redondeado, así que cada reanclaje introduce como mucho un
    /// redondeo; lo que no puede pasar es que se sumen Step a Step, que es
    /// exactamente lo que el diseño sin acumulación existe para evitar.
    func testRepeatedRebasingDoesNotAccumulateDrift() {
        let tempo = Tempo(beatsPerMinute: 174)!
        var timeline = MusicalTimeline(tempo: tempo, division: .sixteenth)

        timeline = timeline.rebased(to: .eighth, atStep: 3)
        timeline = timeline.rebased(to: .thirtySecond, atStep: 9)
        timeline = timeline.rebased(to: .quarter, atStep: 14)

        // Desde el último ancla, el cálculo directo: instante del ancla más
        // índice por duración. Si la implementación acumulara, esto se separaría.
        let anchor = Double(timeline.anchorNanoseconds)
        let duration = timeline.stepDurationNanoseconds

        for step in 14...1014 {
            let expected = anchor + duration * Double(step - timeline.anchorStep)
            XCTAssertEqual(
                Double(timeline.nanosecondOffset(forStep: step)), expected, accuracy: 1,
                "Deriva detectada en el Step \(step)")
        }
    }

    /// El intervalo entre Steps consecutivos sigue siendo estable después de
    /// reanclar, que es la otra cara de lo mismo.
    func testConsecutiveIntervalsStayStableAfterRebasing() {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 174)!, division: .sixteenth)
            .rebased(to: .eighth, atStep: 5)
        let nominal = timeline.stepDurationNanoseconds

        for step in 6...1000 {
            let delta =
                Double(timeline.nanosecondOffset(forStep: step))
                - Double(timeline.nanosecondOffset(forStep: step - 1))
            XCTAssertEqual(
                delta, nominal, accuracy: 1,
                "Intervalo irregular entre los Steps \(step - 1) y \(step)")
        }
    }

    // MARK: - Antes del ancla

    /// **Los Steps anteriores al ancla no se consultan nunca**: el
    /// `LookAheadScheduler` tiene una marca de agua que solo avanza, así que
    /// cuando se reancla en el Step *n* ya no queda nadie preguntando por *n-1*.
    ///
    /// Aun así queda escrito qué devuelven, para que nadie lo dé por definido
    /// más adelante: **la rejilla se extiende hacia atrás con la duración
    /// nueva**, que es lo que sale de la misma multiplicación y no un caso
    /// aparte. No describe lo que sonó — lo que sonó lo describía la rejilla
    /// anterior, y ya no existe.
    func testStepsBeforeTheAnchorExtendBackwardsWithTheNewDuration() {
        let timeline = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .eighth, atStep: 7)

        let anchor = timeline.nanosecondOffset(forStep: 7)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 6), anchor - 250_000_000)
        XCTAssertEqual(timeline.nanosecondOffset(forStep: 5), anchor - 500_000_000)
    }

    /// Y el Delay negativo, que es el único que pide índices negativos, sigue
    /// pudiendo pedirlos.
    func testNegativeStepsStillWork() {
        let timeline = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .eighth, atStep: 0)

        XCTAssertEqual(timeline.nanosecondOffset(forStep: -1), -250_000_000)
    }

    // MARK: - Identidad del valor

    /// Dos rejillas con el mismo tempo, la misma Division y el mismo ancla son
    /// la misma. Es lo que permite al scheduler comparar en vez de recordar si
    /// ya reancló.
    func testTimelinesWithTheSameAnchorAreEqual() {
        let one = MusicalTimeline(tempo: tempo, division: .sixteenth).rebased(
            to: .eighth, atStep: 7)
        let other = MusicalTimeline(tempo: tempo, division: .sixteenth)
            .rebased(to: .eighth, atStep: 7)

        XCTAssertEqual(one, other)
    }

    /// Y dos que difieren solo en el ancla **no** son la misma, aunque sus
    /// Divisions coincidan: la fase es parte del valor.
    func testTimelinesThatDifferOnlyInTheAnchorAreNotEqual() {
        let base = MusicalTimeline(tempo: tempo, division: .sixteenth)

        XCTAssertNotEqual(
            base.rebased(to: .eighth, atStep: 7), base.rebased(to: .eighth, atStep: 8))
    }
}
