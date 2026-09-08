import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de la palabra atómica de la adopción (FR7).
///
/// **Es la vía de vuelta**: el hilo del scheduler diciéndole al modelo que la
/// adopción ocurrió. Un contador de generación —lo que importa es que cambió, no
/// su valor— con la misma forma que `CyclePlaybackClock`: sin locks, sin
/// asignaciones y sin callback hacia el modelo, que sería trabajo en el camino
/// de tiempo real.
final class AdoptionGenerationTests: XCTestCase {

    private func pattern(steps: Int) -> Pattern {
        Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)),
            at: 0
        )
    }

    // MARK: - Arranca en cero y se mueve una vez por adopción

    func testItStartsAtZero() {
        XCTAssertEqual(PatternHandoff(pattern(steps: 16)).adoptionCount, 0)
    }

    /// **Una vez por adopción, no una por ventana.** El límite de compás pasa
    /// constantemente y casi siempre sin nada pendiente: si el contador se
    /// moviera ahí, el modelo creería que adoptó cuatro veces por segundo.
    func testItMovesExactlyOncePerAdoption() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))
        XCTAssertTrue(handoff.adoptArmedPattern())

        XCTAssertEqual(handoff.adoptionCount, 1)
    }

    func testAdoptingWithNothingArmedDoesNotMoveIt() {
        let handoff = PatternHandoff(pattern(steps: 16))

        for _ in 0..<50 { XCTAssertFalse(handoff.adoptArmedPattern()) }

        XCTAssertEqual(handoff.adoptionCount, 0, "se movió sin nada pendiente")
    }

    /// Dos adopciones de verdad lo mueven dos veces.
    func testTwoAdoptionsMoveItTwice() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))
        handoff.adoptArmedPattern()
        handoff.arm(pattern(steps: 12))
        handoff.adoptArmedPattern()

        XCTAssertEqual(handoff.adoptionCount, 2)
    }

    // MARK: - Armar no es adoptar

    /// **Armar sin que llegue el compás no lo mueve.** Entre pulsar el Pattern y
    /// el límite no ha ocurrido nada que el modelo deba aplicar.
    func testArmingWithoutAdoptingDoesNotMoveIt() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))

        XCTAssertEqual(handoff.adoptionCount, 0)
    }

    /// **Armar dos veces y adoptar una lo mueve una vez**: cambiar de idea antes
    /// del límite deja el último y sigue siendo una sola adopción.
    func testArmingTwiceAndAdoptingOnceMovesItOnce() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))
        handoff.arm(pattern(steps: 12))
        XCTAssertTrue(handoff.adoptArmedPattern())

        XCTAssertEqual(handoff.adoptionCount, 1)
    }

    /// Y desarmar —lo que hace Stop— tampoco lo mueve: ahí lo pendiente pasa a
    /// vigente por otro camino.
    func testDisarmingDoesNotMoveIt() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))
        handoff.disarm()

        XCTAssertEqual(handoff.adoptionCount, 0)
    }

    // MARK: - Concurrencia

    /// **Leer desde otro hilo no rompe nada**, que es el mismo test que tiene
    /// `CyclePlaybackClock`: el modelo lee al dibujar mientras el scheduler
    /// adopta, y lo único que se afirma es que el contador nunca retrocede y que
    /// acaba contando todas las adopciones.
    func testReadingFromAnotherThreadNeverSeesItGoBackwards() {
        let handoff = PatternHandoff(pattern(steps: 16))
        let adoptions = 20_000
        let done = expectation(description: "adopción concurrente")
        done.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for index in 0..<adoptions {
                handoff.arm(self.pattern(steps: [4, 8, 12, 16][index % 4]))
                handoff.adoptArmedPattern()
            }
            done.fulfill()
        }

        DispatchQueue.global().async {
            var last: UInt64 = 0
            for _ in 0..<adoptions {
                let seen = handoff.adoptionCount
                XCTAssertGreaterThanOrEqual(seen, last, "el contador retrocedió")
                last = seen
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 30)
        XCTAssertEqual(handoff.adoptionCount, UInt64(adoptions))
    }
}
