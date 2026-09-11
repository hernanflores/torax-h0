import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de Ctrl All sobre Division — Fase 6 de `division-hot-grid_20260911`,
/// FR13 y criterio 11.
///
/// **Un giro de Ctrl All son tantos reanclajes como Tracks, en la misma
/// ventana.** El offset desplaza la Division de los doce a la vez y publica un
/// `Pattern` normal; el scheduler lo lee una vez y cada Track reancla su propia
/// rejilla. Lo que se comprueba es que ninguno pierda, repita ni adelante un
/// Step, y que cada uno siga a lo suyo.
///
/// El bucle del hilo se simula como en `DivisionTempOverlayTests`.
final class DivisionCtrlAllTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    private func cycle(division: Division) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!)
        )
    }

    /// Los doce Tracks con material, cada uno en su Division.
    private func pattern(divisions: (Int) -> Division) -> Pattern {
        (0..<Pattern.trackCount).reduce(into: Pattern()) { pattern, index in
            pattern = pattern.replacing(Track(cycle(division: divisions(index))), at: index)
        }
    }

    private struct Event {
        let step: Int
        let offset: Int64
        let now: Int64
    }

    /// Recorre ventanas hasta `until`, publica cada Pattern en la primera
    /// ventana a partir de su instante, y devuelve lo emitido por Track.
    private func run(
        _ pattern: Pattern, gestures: [(at: Int64, pattern: Pattern)], until: Int64
    ) -> [Int: [Event]] {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        let handoff = PatternHandoff(pattern)
        var pending = gestures
        var events: [Int: [Event]] = [:]
        var now: Int64 = 0
        while now < until {
            if let next = pending.first, now >= next.at {
                handoff.publish(next.pattern)
                pending.removeFirst()
            }
            scheduler.advance(toHorizon: now + 20_000_000, refreshingFrom: handoff) {
                track, _, step, _, _, offset in
                events[track, default: []].append(Event(step: step, offset: offset, now: now))
            }
            now += 10_000_000
        }
        return events
    }

    /// Mantener Ctrl All y girar Division un clic, y soltar.
    private func ctrlAllFill(on pattern: Pattern) -> (held: Pattern, released: Pattern) {
        var offset = CtrlAllOffset()
        let held = offset.apply(1, to: .division, in: pattern)
        return (held, offset.restored(into: held))
    }

    // MARK: - Doce reanclajes en la misma ventana (FR13, criterio 11)

    /// **Los doce reanclan en la misma ventana y ninguno pierde ni repite un
    /// Step.** Todos en 1/16: a los 1000 ms el Step 9 de cada uno queda en
    /// 1125 ms, desde ahí van fusas, y al soltar a los 1500 ms el Step 16 cae a
    /// 1562,5 ms en 1/16 otra vez.
    func testTwelveRebasesInTheSameWindowLoseAndRepeatNothing() {
        let start = pattern { _ in .sixteenth }
        let fill = ctrlAllFill(on: start)
        let byTrack = run(
            start, gestures: [(1_000_000_000, fill.held), (1_500_000_000, fill.released)],
            until: 3_000_000_000)

        XCTAssertEqual(byTrack.count, Pattern.trackCount)
        for (track, events) in byTrack {
            let steps = events.map(\.step)
            XCTAssertEqual(steps, Array(steps.first!...steps.last!), "Track \(track)")
            XCTAssertTrue(events.allSatisfy { $0.offset >= $0.now }, "Track \(track): pasado")

            let offset = { (step: Int) in events.first(where: { $0.step == step })?.offset }
            XCTAssertEqual(offset(9), 1_125_000_000, "Track \(track)")
            XCTAssertEqual(offset(10), 1_187_500_000, "Track \(track): el fill no sonó")
            XCTAssertEqual(offset(16), 1_562_500_000, "Track \(track): soltar rebobinó")
            XCTAssertEqual(offset(17), 1_687_500_000, "Track \(track)")
        }
    }

    /// **Con Divisions distintas cada Track desplaza la suya.** Los pares en
    /// 1/16 y los impares en 1/8: el clic los lleva a 1/32 y a 1/16, y en los
    /// dos casos el espaciado se reduce a la mitad sin perder ni repetir nada.
    func testWithDifferentDivisionsEachTrackShiftsItsOwn() {
        let start = pattern { $0.isMultiple(of: 2) ? .sixteenth : .eighth }
        let fill = ctrlAllFill(on: start)
        let byTrack = run(
            start, gestures: [(1_000_000_000, fill.held)], until: 3_000_000_000)

        for (track, events) in byTrack {
            let steps = events.map(\.step)
            XCTAssertEqual(steps, Array(steps.first!...steps.last!), "Track \(track)")
            XCTAssertTrue(events.allSatisfy { $0.offset >= $0.now }, "Track \(track): pasado")

            let before: Int64 = track.isMultiple(of: 2) ? 125_000_000 : 250_000_000
            let late = events.filter { $0.offset > 1_500_000_000 }
            for (current, next) in zip(late, late.dropFirst()) {
                XCTAssertEqual(next.offset - current.offset, before / 2, "Track \(track)")
            }
        }
    }
}
