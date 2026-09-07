import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de la ranura armada: el Pattern que espera al límite de compás.
///
/// **El protocolo publicado no se toca.** Lo armado es una ranura aparte con su
/// propio contador; el anillo de cuatro, su generación y su disciplina siguen
/// exactamente como estaban. Es lo que permite que el cambio de Pattern entre
/// sin reabrir la parte del handoff que costó validar.
///
/// **Quién hace qué:** el hilo principal **arma** —es un gesto de usuario—, y el
/// hilo del scheduler **adopta**, en el límite. El instante lo decide quien
/// conoce la rejilla.
final class ArmedPatternTests: XCTestCase {

    private func pattern(steps: Int) -> Pattern {
        Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)),
            at: 0
        )
    }

    private func steps(of pattern: Pattern?) -> Int? {
        pattern?.cycle(at: 0)?.shape.steps.count
    }

    // MARK: - Armar no cambia lo que suena

    /// **Armar no publica.** Es la propiedad entera: entre pulsar el Pattern y
    /// el límite del compás sigue sonando el de antes.
    func testArmingDoesNotChangeWhatIsPublished() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))

        XCTAssertEqual(steps(of: handoff.load()), 16)
    }

    func testNothingIsArmedToBeginWith() {
        XCTAssertFalse(PatternHandoff(pattern(steps: 16)).hasArmedPattern)
    }

    func testArmingSaysSo() {
        let handoff = PatternHandoff(pattern(steps: 16))
        handoff.arm(pattern(steps: 8))

        XCTAssertTrue(handoff.hasArmedPattern)
    }

    // MARK: - Adoptar

    /// Adoptar publica lo armado, y a partir de ahí es lo que suena.
    func testAdoptingPublishesTheArmedPattern() {
        let handoff = PatternHandoff(pattern(steps: 16))
        handoff.arm(pattern(steps: 8))

        XCTAssertTrue(handoff.adoptArmedPattern())

        XCTAssertEqual(steps(of: handoff.load()), 8)
        XCTAssertFalse(handoff.hasArmedPattern)
    }

    /// **Adoptar sin nada armado no hace nada**, y lo dice devolviendo `false`.
    /// Es la llamada que el scheduler hace en cada límite de compás, casi
    /// siempre sin nada pendiente: tiene que ser barata y no tener efecto.
    func testAdoptingWithNothingArmedDoesNothing() {
        let handoff = PatternHandoff(pattern(steps: 16))

        XCTAssertFalse(handoff.adoptArmedPattern())
        XCTAssertEqual(steps(of: handoff.load()), 16)
    }

    /// **Armar dos veces deja lo último.** Cambiar de idea antes del límite es
    /// normal en directo, y no hay cola: hay un pendiente.
    func testArmingTwiceKeepsTheLastOne() {
        let handoff = PatternHandoff(pattern(steps: 16))

        handoff.arm(pattern(steps: 8))
        handoff.arm(pattern(steps: 12))
        XCTAssertTrue(handoff.adoptArmedPattern())

        XCTAssertEqual(steps(of: handoff.load()), 12)
    }

    /// Adoptar dos veces seguidas: la segunda no hace nada.
    func testAdoptingTwiceOnlyWorksOnce() {
        let handoff = PatternHandoff(pattern(steps: 16))
        handoff.arm(pattern(steps: 8))

        XCTAssertTrue(handoff.adoptArmedPattern())
        XCTAssertFalse(handoff.adoptArmedPattern())
        XCTAssertEqual(steps(of: handoff.load()), 8)
    }

    /// **Desarmar existe**, para el caso de FR10: Stop se lleva lo pendiente por
    /// otro camino y no puede quedar armado nada.
    func testDisarmingClearsThePending() {
        let handoff = PatternHandoff(pattern(steps: 16))
        handoff.arm(pattern(steps: 8))

        handoff.disarm()

        XCTAssertFalse(handoff.hasArmedPattern)
        XCTAssertFalse(handoff.adoptArmedPattern())
        XCTAssertEqual(steps(of: handoff.load()), 16)
    }

    /// Publicar directamente —el camino de siempre, con el transporte parado—
    /// no toca lo armado.
    func testPublishingDoesNotDisturbTheArmedPattern() {
        let handoff = PatternHandoff(pattern(steps: 16))
        handoff.arm(pattern(steps: 8))

        handoff.publish(pattern(steps: 4))

        XCTAssertEqual(steps(of: handoff.load()), 4)
        XCTAssertTrue(handoff.hasArmedPattern)
    }

    // MARK: - Concurrencia

    /// **Un escritor armando en bucle y un lector adoptando no producen un
    /// Pattern mezclado.**
    ///
    /// Es la extensión al camino armado del test que el handoff ya tenía. Lo que
    /// se afirma es que todo lo que sale de `load()` es **uno de los Patterns
    /// que se armaron**, entero: nunca medio uno y medio otro.
    func testArmingAndAdoptingConcurrentlyNeverMixesTwoPatterns() {
        let valid = Set([4, 8, 12, 16])
        let handoff = PatternHandoff(pattern(steps: 16))
        let done = expectation(description: "armado concurrente")
        done.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for index in 0..<20_000 {
                handoff.arm(self.pattern(steps: [4, 8, 12, 16][index % 4]))
            }
            done.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<20_000 {
                _ = handoff.adoptArmedPattern()
                if let steps = self.steps(of: handoff.load()) {
                    XCTAssertTrue(valid.contains(steps), "Pattern mezclado: \(steps) steps")
                }
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 30)
    }

    // MARK: - La regla de tiempo real

    /// Adoptar no puede asignar: lo que se copia es un `Pattern`, que sigue
    /// siendo trivial.
    func testThePatternIsStillTrivial() {
        XCTAssertTrue(_isPOD(Pattern.self), "el Pattern dejó de ser trivial")
    }
}
