import XCTest
@testable import Engine

/// Tests del recorrido del pool.
///
/// La Pre Spec, para Style monofónico: «una nota por vez: arpegios, broken
/// chords y patrones ascendentes/descendentes». Style está fuera de v1, así que
/// el único recorrido de esta rebanada es el ascendente.
///
/// **Sin estado, derivado del índice de Step.** Es la misma disciplina que
/// `MusicalTimeline`: el offset de un Step se calcula multiplicando su índice,
/// nunca acumulando. Un contador de Pulses que avanzara solo derivaría en cuanto
/// se descartara una lectura del snapshot o se reiniciara el transporte.
final class PoolTraversalTests: XCTestCase {

    private let pool = PitchPool()
        .inserting(Pitch(60)!)
        .inserting(Pitch(64)!)
        .inserting(Pitch(67)!)

    // MARK: - Cuántos Pulses van

    /// El ordinal de un Pulse es cuántos dispararon antes que él.
    func testThePulseOrdinalCountsTheTriggersBefore() {
        // 8/3 reparte en x..x..x.
        let rhythm = EuclideanRhythm(steps: Steps(8)!, pulses: Pulses(3)!)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 0), 0)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 3), 1)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 6), 2)
    }

    /// **Sigue contando al dar la vuelta.** El anillo se cierra, pero los Pulses
    /// no vuelven a empezar: la vuelta siguiente continúa el arpegio en vez de
    /// reiniciarlo, que es lo que hace que un pool de tres sobre un anillo de
    /// ocho no repita la misma nota en la misma posición.
    func testThePulseOrdinalKeepsCountingAcrossLaps() {
        let rhythm = EuclideanRhythm(steps: Steps(8)!, pulses: Pulses(3)!)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 8), 3)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 11), 4)
        XCTAssertEqual(rhythm.pulseOrdinal(atStep: 16), 6)
    }

    /// Invariante: el ordinal avanza exactamente uno por cada Step que dispara,
    /// y no se mueve en los que no.
    func testTheOrdinalAdvancesOncePerTriggeringStep() {
        for steps in Steps.validRange {
            for pulses in 1...steps {
                let rhythm = EuclideanRhythm(steps: Steps(steps)!, pulses: Pulses(pulses)!)
                var expected = 0
                for step in 0..<(steps * 3) {
                    if rhythm.triggers(atStep: step) {
                        XCTAssertEqual(
                            rhythm.pulseOrdinal(atStep: step), expected,
                            "Steps \(steps) · Pulses \(pulses) · Step \(step)"
                        )
                        expected += 1
                    }
                }
            }
        }
    }

    // MARK: - Qué altura toca

    func testEachPulseTakesTheNextPitch() {
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 0), Pitch(60)!)
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 1), Pitch(64)!)
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 2), Pitch(67)!)
    }

    /// Agotado el pool vuelve al principio: es un arpegio, no una lista que se
    /// acaba.
    func testTheTraversalWrapsBackToTheStart() {
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 3), Pitch(60)!)
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 4), Pitch(64)!)
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: 300), Pitch(60)!)
    }

    /// Determinismo: mismo pool y mismo Pulse, misma altura. Sin PRNG y sin
    /// estado, no hay otra forma de que sea.
    func testTheTraversalIsDeterministic() {
        for ordinal in 0..<50 {
            XCTAssertEqual(
                PoolTraversal.ascending.pitch(from: pool, atPulse: ordinal),
                PoolTraversal.ascending.pitch(from: pool, atPulse: ordinal),
                "Pulse \(ordinal)"
            )
        }
    }

    /// **Un pool de una nota da un centro estable**, que es como la Pre Spec lo
    /// describe.
    func testASinglePitchPoolIsAStableCentre() {
        let single = PitchPool().inserting(Pitch(48)!)
        for ordinal in 0..<20 {
            XCTAssertEqual(
                PoolTraversal.ascending.pitch(from: single, atPulse: ordinal), Pitch(48)!)
        }
    }

    /// **Un pool vacío no da ninguna altura.** El Track dispara sus Pulses y no
    /// tiene material que emitir. Es un estado, no un error.
    func testAnEmptyPoolGivesNothing() {
        for ordinal in 0..<8 {
            XCTAssertNil(PoolTraversal.ascending.pitch(from: PitchPool(), atPulse: ordinal))
        }
    }

    /// Un ordinal negativo no puede llegar del scheduler, que cuenta hacia
    /// arriba. Si llegara **envuelve**, igual que hacen `triggers(atStep:)` y
    /// `Rotate` con los índices negativos: −1 es la última del pool, no la
    /// primera. Un solo criterio para el mismo problema en todo el motor.
    func testANegativeOrdinalWrapsLikeEverythingElse() {
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: -1), Pitch(67)!)
        XCTAssertEqual(PoolTraversal.ascending.pitch(from: pool, atPulse: -3), Pitch(60)!)
    }

    /// Toda altura que sale del recorrido está en el pool. Nunca se inventa
    /// material.
    func testEveryPitchComesFromThePool() {
        for size in 1...8 {
            var built = PitchPool()
            for offset in 0..<size { built = built.inserting(Pitch(60 + offset * 2)!) }
            for ordinal in 0..<40 {
                let pitch = PoolTraversal.ascending.pitch(from: built, atPulse: ordinal)
                XCTAssertNotNil(pitch)
                XCTAssertTrue(built.contains(pitch!), "tamaño \(size) · Pulse \(ordinal)")
            }
        }
    }
}
