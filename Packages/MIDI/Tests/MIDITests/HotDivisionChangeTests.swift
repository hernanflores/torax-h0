import Engine
import XCTest

@testable import MIDI

/// Tests del cambio de Division con el transporte corriendo — Fase 2 de
/// `division-hot-grid_20260911`.
///
/// **El defecto que cierran.** La rejilla de cada Track se construía al pulsar
/// Play y no volvía a mirarse: girar Division mientras suena cambiaba la
/// duración de la nota —que la recalcula `Transport` por nota— y **no el
/// espaciado de los Steps**. En un instrumento tonal eso se oye; en una pista
/// rítmica de one-shots el knob parecía muerto.
///
/// Se testea sobre `TrackScheduler` y no sobre `SchedulerThread` por la misma
/// razón que el resto: aquí el horizonte se da a mano, así que lo que se
/// comprueba es un hecho y no una carrera contra el reloj.
final class HotDivisionChangeTests: XCTestCase {

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    /// Un Step de 1/16 dura 125 ms a 120 BPM; uno de 1/8, 250.
    private let step: Int64 = 125_000_000

    private func cycle(division: Division) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().toggling(Pitch(60)!)
        )
    }

    private func track(division: Division) -> Track {
        Track(cycle(division: division))
    }

    /// Avanza una ventana y devuelve los pares (Step, offset emitido).
    private func emit(
        _ scheduler: inout TrackScheduler,
        toHorizon horizon: Int64
    ) -> [(step: Int, offset: Int64)] {
        var emitted: [(step: Int, offset: Int64)] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: nil) { _, step, _, _, offset in
            emitted.append((step, offset))
        }
        return emitted
    }

    // MARK: - El defecto, escrito como test (FR1, FR2, criterio 1)

    /// **1/16 → 1/8 dobla el tiempo entre Steps.** Es el criterio 1 del track y
    /// lo que el usuario dice que no ocurría.
    func testPublishingASlowerDivisionDoublesTheSpacing() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: track(division: .sixteenth))
        _ = emit(&scheduler, toHorizon: 4 * step)

        scheduler.refresh(with: track(division: .eighth))
        let emitted = emit(&scheduler, toHorizon: 4 * step + 8 * 250_000_000)

        let offsets = emitted.map(\.offset)
        XCTAssertGreaterThan(offsets.count, 2)
        for index in 1..<offsets.count {
            XCTAssertEqual(
                offsets[index] - offsets[index - 1], 250_000_000,
                "Los Steps siguen separados como si la Division no hubiera cambiado")
        }
    }

    /// Y 1/16 → 1/32 lo divide, que es el otro extremo del recorrido del knob.
    func testPublishingAFasterDivisionHalvesTheSpacing() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: track(division: .sixteenth))
        _ = emit(&scheduler, toHorizon: 4 * step)

        scheduler.refresh(with: track(division: .thirtySecond))
        let offsets = emit(&scheduler, toHorizon: 8 * step).map(\.offset)

        XCTAssertGreaterThan(offsets.count, 2)
        for index in 1..<offsets.count {
            XCTAssertEqual(offsets[index] - offsets[index - 1], 62_500_000)
        }
    }

    // MARK: - El instante del corte (FR6)

    /// El primer Step que sale con la rejilla nueva cae **donde ya iba a caer**.
    /// Girar el knob no adelanta ni retrasa el Step que estaba a punto de sonar.
    func testTheFirstStepOnTheNewGridKeepsItsInstant() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: track(division: .sixteenth))
        let before = emit(&scheduler, toHorizon: 4 * step)
        let nextStepIndex = before.last!.step + 1
        let instantItWouldHaveHad = timeline.nanosecondOffset(forStep: nextStepIndex)

        scheduler.refresh(with: track(division: .eighth))
        let after = emit(&scheduler, toHorizon: 4 * step + 250_000_000)

        XCTAssertEqual(after.first?.step, nextStepIndex)
        XCTAssertEqual(after.first?.offset, instantItWouldHaveHad)
    }

    // MARK: - No se reinicia nada (FR5, criterio 2)

    /// **El Track sigue por donde iba.** Los índices de Step continúan la
    /// secuencia: girar el knob no devuelve el desarrollo al principio del
    /// anillo, que es lo que haría reconstruir el scheduler.
    func testChangingTheDivisionDoesNotRestartTheRing() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: track(division: .sixteenth))
        let before = emit(&scheduler, toHorizon: 6 * step)

        scheduler.refresh(with: track(division: .eighth))
        let after = emit(&scheduler, toHorizon: 6 * step + 4 * 250_000_000)

        XCTAssertEqual(after.first?.step, before.last!.step + 1)
    }

    /// Ni un Step se pierde ni se repite a lo largo de varios cambios seguidos
    /// (FR7, criterio 3). Es el invariante del look-ahead visto desde arriba.
    func testNoStepIsLostOrRepeatedAcrossSeveralChanges() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        var emitted: [Int] = []
        var horizon: Int64 = 0

        for window in 0..<60 {
            horizon += 20_000_000
            emitted.append(contentsOf: emit(&scheduler, toHorizon: horizon).map(\.step))

            if window == 5 { scheduler.refresh(with: track(division: .eighth)) }
            if window == 17 { scheduler.refresh(with: track(division: .thirtySecond)) }
            if window == 33 { scheduler.refresh(with: track(division: .quarter)) }
        }

        XCTAssertFalse(emitted.isEmpty)
        XCTAssertEqual(emitted, Array(emitted.first!...emitted.last!))
    }

    // MARK: - Lo ya sellado no se reescribe (FR4)

    /// Lo emitido en la ventana anterior salió con la rejilla anterior y se
    /// queda como salió: el cambio empieza a oírse en la ventana siguiente.
    func testAlreadyEmittedStepsKeepTheirOldOffsets() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: track(division: .sixteenth))
        let before = emit(&scheduler, toHorizon: 4 * step)

        for (step, offset) in before {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }

    // MARK: - El caso de cada ventana

    /// **Refrescar con la misma Division no cambia ni un offset.** Es lo que
    /// ocurre en casi todas las ventanas de casi todas las reproducciones, y
    /// tiene que ser indistinguible de no haber refrescado.
    func testRefreshingWithTheSameDivisionEmitsExactlyTheSame() {
        var touched = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        var untouched = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))

        var touchedOffsets: [Int64] = []
        var untouchedOffsets: [Int64] = []
        var horizon: Int64 = 0

        for _ in 0..<40 {
            horizon += 20_000_000
            touched.refresh(with: track(division: .sixteenth))
            touchedOffsets.append(contentsOf: emit(&touched, toHorizon: horizon).map(\.offset))
            untouchedOffsets.append(contentsOf: emit(&untouched, toHorizon: horizon).map(\.offset))
        }

        XCTAssertFalse(touchedOffsets.isEmpty)
        XCTAssertEqual(touchedOffsets, untouchedOffsets)
    }

    // MARK: - La vía del arnés (FR18)

    /// El arnés mide **la rejilla**, no el material: sin Track publicado no hay
    /// Division a la que seguir, y su timeline se queda donde la configuración
    /// la puso.
    func testTheMeasurementPathNeverRebases() {
        var scheduler = TrackScheduler(timeline: timeline, material: .everyStep)

        for (step, offset) in emit(&scheduler, toHorizon: 8 * step) {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }
}
