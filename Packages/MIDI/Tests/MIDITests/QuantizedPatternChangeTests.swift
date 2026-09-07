import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del cambio de Pattern cuantizado: entra en el compás, ni antes ni
/// después.
///
/// **El instante se comprueba sobre el offset, no de oído.** A 120 BPM con
/// Division 1/16 un Step dura 125 ms y un compás son 2 s, es decir dieciséis
/// Steps exactos. El Pattern nuevo tiene que empezar a sonar en el evento cuyo
/// offset es 2 000 000 000 ns y no antes.
final class QuantizedPatternChangeTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Pattern que dispara en los dieciséis Steps con una sola altura, para
    /// que cada evento diga de qué Pattern vino.
    private func pattern(pitch value: Int) -> Pattern {
        Pattern().replacing(
            Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
                pool: PitchPool().inserting(Pitch(value)!)
            ),
            at: 0
        )
    }

    /// Todo lo que se emite hasta ese horizonte, como (offset, altura).
    private func events(
        upTo horizon: Int64,
        from scheduler: PatternScheduler,
        handoff: PatternHandoff
    ) -> [(offset: Int64, pitch: Int)] {
        var collected: [(Int64, Int)] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) {
            _, _, _, pitch, _, offset in
            if let pitch { collected.append((offset, pitch.value)) }
        }
        return collected.map { (offset: $0.0, pitch: $0.1) }
    }

    /// **El Pattern entra en el primer Step del compás siguiente.**
    func testTheArmedPatternEntersOnTheBarBoundary() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        handoff.arm(pattern(pitch: 72))
        let emitted = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        let bar: Int64 = 2_000_000_000
        for event in emitted {
            let expected = event.offset < bar ? 60 : 72
            XCTAssertEqual(
                event.pitch, expected,
                "en \(event.offset) ns sonó \(event.pitch) y tocaba \(expected)")
        }
        XCTAssertTrue(emitted.contains { $0.offset == bar && $0.pitch == 72 })
    }

    /// **Ni antes.** El último evento del compás viejo sigue siendo del Pattern
    /// viejo.
    func testTheLastEventOfTheOldBarIsStillTheOldPattern() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        handoff.arm(pattern(pitch: 72))
        let emitted = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        let last = emitted.last { $0.offset < 2_000_000_000 }
        XCTAssertEqual(last?.offset, 1_875_000_000, "el Step 15 no cae donde debe")
        XCTAssertEqual(last?.pitch, 60)
    }

    /// **Sin nada armado no cambia nada**, por muchas ventanas que pasen.
    func testNothingArmedMeansNothingChanges() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        let emitted = events(upTo: 8_000_000_000, from: scheduler, handoff: handoff)

        XCTAssertFalse(emitted.isEmpty)
        XCTAssertTrue(emitted.allSatisfy { $0.pitch == 60 })
    }

    /// **Armar a mitad de compás espera al siguiente**, no al que ya empezó.
    func testArmingMidBarWaitsForTheNextBoundary() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        // Primera ventana: medio compás, sin nada armado.
        _ = events(upTo: 1_000_000_000, from: scheduler, handoff: handoff)

        handoff.arm(pattern(pitch: 72))
        let emitted = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        XCTAssertTrue(emitted.filter { $0.offset < 2_000_000_000 }.allSatisfy { $0.pitch == 60 })
        XCTAssertTrue(emitted.filter { $0.offset >= 2_000_000_000 }.allSatisfy { $0.pitch == 72 })
    }

    /// El cambio ocurre **una vez**: el compás siguiente no vuelve a cambiar.
    func testTheChangeHappensOnceAndNotEveryBar() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        handoff.arm(pattern(pitch: 72))
        let emitted = events(upTo: 8_000_000_000, from: scheduler, handoff: handoff)

        XCTAssertTrue(emitted.filter { $0.offset >= 2_000_000_000 }.allSatisfy { $0.pitch == 72 })
        XCTAssertFalse(handoff.hasArmedPattern)
    }

    /// **En ventanas pequeñas también.** El scheduler real avanza de 20 en 20 ms,
    /// no de dos segundos: el límite cae dentro de una ventana concreta y ahí es
    /// donde tiene que partirse.
    func testTheBoundaryIsRespectedWithRealisticWindows() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        handoff.arm(pattern(pitch: 72))

        var emitted: [(offset: Int64, pitch: Int)] = []
        var horizon: Int64 = 0
        while horizon < 4_000_000_000 {
            horizon += 20_000_000
            emitted += events(upTo: horizon, from: scheduler, handoff: handoff)
        }

        for event in emitted {
            let expected = event.offset < 2_000_000_000 ? 60 : 72
            XCTAssertEqual(event.pitch, expected, "en \(event.offset) ns")
        }
        XCTAssertTrue(emitted.contains { $0.offset == 2_000_000_000 && $0.pitch == 72 })
    }

    /// Con el transporte parado, publicar es inmediato (FR5): es el camino de
    /// siempre y esta rebanada no lo toca.
    func testPublishingIsStillImmediate() {
        let handoff = PatternHandoff(pattern(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(pitch: 60))

        handoff.publish(pattern(pitch: 72))
        let emitted = events(upTo: 500_000_000, from: scheduler, handoff: handoff)

        XCTAssertTrue(emitted.allSatisfy { $0.pitch == 72 })
    }
}
