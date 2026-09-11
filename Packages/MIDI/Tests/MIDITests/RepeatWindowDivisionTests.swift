import Engine
import XCTest

@testable import MIDI

/// Tests de la ventana de repeticiones tras un cambio de Division — Fase 4 de
/// `division-hot-grid_20260911`, FR15.
///
/// **Dos lados que tienen que medir contra el mismo Step.** El corte de las
/// repeticiones —cuánto falta hasta el Pulse siguiente— y el hueco base de Time
/// salen los dos de la duración de Step. Mientras la rejilla estaba congelada en
/// Play, el corte se medía con la duración vieja y el hueco con la Division
/// viva: al girar el knob, un Repeats que cabía se recortaba, o uno que no cabía
/// caía encima del Pulse siguiente.
///
/// Los números son a 120 BPM con Time en 1/32: el hueco base es 62,5 ms en
/// cualquier Division, porque Time es una fracción de redonda y no de Step.
final class RepeatWindowDivisionTests: XCTestCase {

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    /// Un Step de 1/16 dura 125 ms a 120 BPM.
    private let step: Int64 = 125_000_000

    /// Un Cycle que dispara en todos sus Steps y cuelga tres repeticiones de
    /// cada Pulse, separadas 1/32.
    private func cycle(division: Division) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!),
            noteRepeater: NoteRepeater(
                repeats: Repeats(3)!,
                time: RepeatTime(numerator: 1, denominator: 32)!,
                ramp: .default,
                pace: .default
            )
        )
    }

    private struct Emitted {
        var pulses: [(step: Int, offset: Int64)] = []
        var repetitions: [(step: Int, offset: Int64)] = []
    }

    /// Una ventana en 1/16 y, tras publicar la Division nueva, otra hasta
    /// `horizon`. Devuelve solo lo que salió después del cambio.
    private func emittedAfterChanging(to division: Division, until horizon: Int64) -> Emitted {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .cycle(cycle(division: .sixteenth)))
        scheduler.refresh(with: Track(cycle(division: .sixteenth)))
        scheduler.advance(toHorizon: 4 * step, refreshingFrom: nil) { _, _, _, _, _ in }

        scheduler.refresh(with: Track(cycle(division: division)))
        var emitted = Emitted()
        scheduler.advance(
            toHorizon: horizon,
            refreshingFrom: nil,
            emitRepetition: { _, step, _, _, _, offset in
                emitted.repetitions.append((step, offset))
            },
            emit: { _, step, _, _, offset in emitted.pulses.append((step, offset)) }
        )
        return emitted
    }

    /// Las repeticiones que cuelgan de cada Pulse, en orden de Pulse.
    private func repetitionsPerPulse(_ emitted: Emitted) -> [Int] {
        emitted.pulses.map { pulse in emitted.repetitions.filter { $0.step == pulse.step }.count }
    }

    // MARK: - Una repetición que cabía no se descarta

    /// **1/16 → 1/8: el corte pasa a 250 ms y caben las tres.** A 62,5, 125 y
    /// 187,5 ms del Pulse, las tres antes del siguiente. Con el corte medido
    /// contra el Step viejo —125 ms— solo cabía la primera.
    func testASlowerDivisionLetsEveryRepetitionThatFitsSound() {
        let emitted = emittedAfterChanging(to: .eighth, until: 4 * step + 8 * 250_000_000)

        XCTAssertGreaterThan(emitted.pulses.count, 2)
        XCTAssertEqual(
            repetitionsPerPulse(emitted), Array(repeating: 3, count: emitted.pulses.count),
            "se recortaron repeticiones que cabían en el Step nuevo")
    }

    // MARK: - Una que no cabía no cae encima del Pulse siguiente

    /// **1/16 → 1/32: el corte pasa a 62,5 ms y no cabe ninguna.** La primera
    /// caería justo en el Pulse siguiente, que es la nota que el corte existe
    /// para no duplicar.
    func testAFasterDivisionLetsNoRepetitionLandOnTheNextPulse() {
        let emitted = emittedAfterChanging(to: .thirtySecond, until: 4 * step + 8 * 62_500_000)

        XCTAssertGreaterThan(emitted.pulses.count, 2)
        XCTAssertTrue(emitted.repetitions.isEmpty, "una repetición cayó sobre el Pulse siguiente")
    }

    /// **La propiedad general, en cada Pulse emitido tras el cambio:** toda
    /// repetición cae estrictamente entre su Pulse y el siguiente. Se recorre
    /// el knob entero para que ninguna Division quede sin mirar.
    func testEveryRepetitionFallsBeforeTheNextPulseInEveryDivision() {
        for division in Division.ordered {
            let emitted = emittedAfterChanging(to: division, until: 4 * step + 4_000_000_000)

            for (current, next) in zip(emitted.pulses, emitted.pulses.dropFirst()) {
                for repetition in emitted.repetitions where repetition.step == current.step {
                    XCTAssertGreaterThan(repetition.offset, current.offset, "\(division)")
                    XCTAssertLessThan(
                        repetition.offset, next.offset,
                        "con \(division) una repetición del Step \(current.step) pisó el siguiente")
                }
            }
        }
    }

    // MARK: - El hueco base no depende de la Division

    /// **Time es una fracción de redonda**: la primera repetición cae a 62,5 ms
    /// del Pulse en 1/8 igual que en 1/16. Si el hueco se midiera contra un Step
    /// y la Division contra otro, aquí saldría el doble o la mitad.
    func testTheBaseGapStaysOneThirtySecondAfterTheChange() {
        let emitted = emittedAfterChanging(to: .eighth, until: 4 * step + 4 * 250_000_000)

        guard let pulse = emitted.pulses.first,
            let first = emitted.repetitions.first(where: { $0.step == pulse.step })
        else { return XCTFail("no salió ningún Pulse con repeticiones") }
        XCTAssertEqual(first.offset - pulse.offset, 62_500_000)
    }
}
