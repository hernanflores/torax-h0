import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del overlay de Division por Temp, ida y vuelta — Fase 6 de
/// `division-hot-grid_20260911`, FR12, FR13 y FR14.
///
/// **Un fill de Division por Temp es el uso en directo que este track
/// desbloquea.** Hasta ahora, mantener [step 13] y girar Division cambiaba la
/// duración de la nota y nada más; con la rejilla siguiendo al material, el
/// fill suena. El overlay no cruza al hilo del scheduler: publica un `Pattern`
/// normal por el handoff de siempre, así que aquí se publica lo que el overlay
/// devuelve, a mano y en el instante que se elige, y se mira lo que sale.
///
/// **Un gesto son dos reanclajes**, el de la pulsación y el de la soltada, y
/// los dos tienen que cumplir FR6 y FR7.
///
/// El bucle del hilo se simula como en `DelayBudgetDivisionTests`: ventanas
/// cada 10 ms con el horizonte 20 ms por delante del presente. Sin Delay, el
/// origen es Play.
final class DivisionTempOverlayTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    private func cycle(pitch: Int, division: Division) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    private struct Event {
        let step: Int
        let pitch: Int?
        let offset: Int64
        let now: Int64
    }

    /// Recorre ventanas hasta `until` y publica cada Pattern de `gestures` en
    /// la primera ventana a partir de su instante.
    private func run(
        _ pattern: Pattern, gestures: [(at: Int64, pattern: Pattern)], until: Int64
    ) -> [Event] {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        let handoff = PatternHandoff(pattern)
        var pending = gestures
        var events: [Event] = []
        var now: Int64 = 0
        while now < until {
            if let next = pending.first, now >= next.at {
                handoff.publish(next.pattern)
                pending.removeFirst()
            }
            scheduler.advance(toHorizon: now + 20_000_000, refreshingFrom: handoff) {
                track, _, step, pitch, _, offset in
                guard track == 0 else { return }
                events.append(Event(step: step, pitch: pitch?.value, offset: offset, now: now))
            }
            now += 10_000_000
        }
        return events
    }

    /// Mantener Temp y girar Division un clic hacia la derecha, y soltar: los
    /// dos Patterns que `ControlInput` publicaría.
    private func tempFill(on track: Track) -> (held: Pattern, released: Pattern) {
        var overlay = ParameterOverlay()
        let held = overlay.apply(1, to: .division, in: track)
        return (
            Pattern().replacing(held, at: 0),
            Pattern().replacing(overlay.restored(into: held), at: 0)
        )
    }

    private func offset(ofStep step: Int, in events: [Event]) -> Int64? {
        events.first(where: { $0.step == step })?.offset
    }

    private func assertNeitherLostRepeatedNorEarly(
        _ events: [Event], file: StaticString = #filePath, line: UInt = #line
    ) {
        let steps = events.map(\.step)
        XCTAssertEqual(
            steps, Array(steps.first!...steps.last!), "un Step perdido o repetido",
            file: file, line: line)
        for event in events {
            XCTAssertGreaterThanOrEqual(
                event.offset, event.now, "el Step \(event.step) se pidió para el pasado",
                file: file, line: line)
        }
    }

    // MARK: - Un Cycle: el fill suena y soltar no rebobina (FR12, FR14)

    /// **Mantener Temp y girar Division cambia la velocidad mientras dura.** En
    /// 1/16, a los 1000 ms ya salió el Step 8; el 9 queda en su instante,
    /// 1125 ms, y desde ahí van fusas de 62,5 ms.
    func testHoldingTempOnDivisionMakesTheFillSound() {
        let track = Track(cycle(pitch: 48, division: .sixteenth))
        let fill = tempFill(on: track)
        let events = run(
            Pattern().replacing(track, at: 0),
            gestures: [(1_000_000_000, fill.held), (1_500_000_000, fill.released)],
            until: 3_000_000_000)

        XCTAssertEqual(offset(ofStep: 9, in: events), 1_125_000_000)
        for step in 10...15 {
            XCTAssertEqual(
                offset(ofStep: step, in: events),
                1_125_000_000 + Int64(step - 9) * 62_500_000, "Step \(step)")
        }
        assertNeitherLostRepeatedNorEarly(events)
    }

    /// **Soltar devuelve la Division anterior anclada a la soltada, sin
    /// rebobinar la fase** (FR14). El Step 16 cae donde el fill lo dejó,
    /// 1562,5 ms, y no a los 2000 ms que le daría la rejilla de Play. Desde
    /// ahí, otra vez 125 ms.
    func testReleasingTempReturnsTheDivisionWithoutRewindingThePhase() {
        let track = Track(cycle(pitch: 48, division: .sixteenth))
        let fill = tempFill(on: track)
        let events = run(
            Pattern().replacing(track, at: 0),
            gestures: [(1_000_000_000, fill.held), (1_500_000_000, fill.released)],
            until: 3_000_000_000)

        XCTAssertEqual(offset(ofStep: 16, in: events), 1_562_500_000)
        XCTAssertEqual(offset(ofStep: 17, in: events), 1_687_500_000)
        assertNeitherLostRepeatedNorEarly(events)
    }

    // MARK: - Dos Cycles: cada uno recupera la suya

    /// **Con Cycles de Divisions distintas, el overlay iguala y al soltar cada
    /// uno recupera la suya.** Cycle 1 en 1/16 y Cycle 2 en 1/8: el fill pone
    /// los dos en 1/32. Tras soltar, la vuelta del Cycle 2 abre a 1562,5 ms en
    /// 1/8, y el Cycle 1 vuelve 16 corcheas después, a 5562,5 ms, en 1/16.
    func testWithCyclesOfDifferentDivisionsEachGetsItsOwnBack() {
        let track = Track(cycle(pitch: 48, division: .sixteenth))
            .withActiveCount(2)
            .replacing(cycle(pitch: 72, division: .eighth), at: 1)
        let fill = tempFill(on: track)
        let events = run(
            Pattern().replacing(track, at: 0),
            gestures: [(1_000_000_000, fill.held), (1_500_000_000, fill.released)],
            until: 6_500_000_000)

        XCTAssertEqual(events.first(where: { $0.step == 16 })?.pitch, 72)
        XCTAssertEqual(offset(ofStep: 16, in: events), 1_562_500_000)
        XCTAssertEqual(offset(ofStep: 17, in: events), 1_812_500_000, "el Cycle 2 no volvió a 1/8")
        XCTAssertEqual(events.first(where: { $0.step == 32 })?.pitch, 48)
        XCTAssertEqual(offset(ofStep: 32, in: events), 5_562_500_000)
        XCTAssertEqual(offset(ofStep: 33, in: events), 5_687_500_000, "el Cycle 1 no volvió a 1/16")
        assertNeitherLostRepeatedNorEarly(events)
    }
}
