import Engine
import XCTest

@testable import MIDI

/// Tests de lo que el modelo recuerda al armar y aplica al ver moverse el
/// contador (FR8, FR10).
///
/// **El scheduler no conoce índices.** Solo tiene la palabra atómica, así que
/// quién armó qué hueco lo recuerda este lado. La decisión vive aquí y no en
/// `App` porque `App` no se mide (`workflow.md`, NFR3): si hubiera una decisión
/// allí, estaría en el sitio equivocado.
final class PendingAdoptionTests: XCTestCase {

    // MARK: - Lo que se recuerda al armar

    func testItStartsWithNothingArmed() {
        XCTAssertNil(PendingAdoption().armedPatternIndex)
    }

    func testArmingRemembersTheSlot() {
        let pending = PendingAdoption()

        pending.arm(5, adoptionCount: 0)

        XCTAssertEqual(pending.armedPatternIndex, 5)
    }

    /// Armar dos veces antes del compás deja el último, igual que la ranura del
    /// handoff: cambiar de idea antes del límite es normal en directo.
    func testArmingTwiceBeforeTheBarKeepsTheLast() {
        let pending = PendingAdoption()

        pending.arm(5, adoptionCount: 0)
        pending.arm(9, adoptionCount: 0)

        XCTAssertEqual(pending.armedPatternIndex, 9)
        XCTAssertEqual(pending.landed(adoptionCount: 1), 9)
    }

    /// Cancelar quita lo pendiente sin aplicarlo. Es lo que hace el camino
    /// parado, que ya entra en el acto.
    func testCancellingClearsTheArmedSlot() {
        let pending = PendingAdoption()

        pending.arm(5, adoptionCount: 0)
        pending.cancel()

        XCTAssertNil(pending.armedPatternIndex)
        XCTAssertNil(pending.landed(adoptionCount: 1), "aplicó algo cancelado")
    }

    // MARK: - Lo que se aplica al ver el contador moverse

    /// **Con una adopción publicada, el hueco armado es el que hay que aplicar**
    /// — y deja de estar armado, que es lo que hace desaparecer la cuenta atrás
    /// y mueve la rejilla al hueco correcto (FR10).
    func testAMovedCounterYieldsTheArmedSlotAndClearsIt() {
        let pending = PendingAdoption()
        pending.arm(5, adoptionCount: 0)

        XCTAssertEqual(pending.landed(adoptionCount: 1), 5)
        XCTAssertNil(pending.armedPatternIndex, "no se limpió lo pendiente")
    }

    /// Y no se aplica dos veces: el cuadro siguiente ya no tiene nada que hacer.
    func testItDoesNotYieldTheSameAdoptionTwice() {
        let pending = PendingAdoption()
        pending.arm(5, adoptionCount: 0)

        XCTAssertEqual(pending.landed(adoptionCount: 1), 5)
        XCTAssertNil(pending.landed(adoptionCount: 1))
    }

    /// **Sin adopción pendiente, leer el contador no cambia nada.** Es el caso
    /// de casi todos los cuadros.
    func testReadingWithNothingArmedYieldsNothing() {
        let pending = PendingAdoption()

        for count in 0..<10 {
            XCTAssertNil(pending.landed(adoptionCount: UInt64(count)))
        }
    }

    /// **Armar sin que llegue el compás no aplica nada.** El contador no se ha
    /// movido, así que lo armado sigue esperando.
    func testArmingWithoutTheCounterMovingYieldsNothing() {
        let pending = PendingAdoption()
        pending.arm(5, adoptionCount: 3)

        XCTAssertNil(pending.landed(adoptionCount: 3))
        XCTAssertEqual(pending.armedPatternIndex, 5, "dejó de esperar")
    }

    /// Un contador que ya venía movido antes de armar tampoco dispara: lo que
    /// importa es que se mueva **después**.
    func testACounterAlreadyAheadBeforeArmingDoesNotFire() {
        let pending = PendingAdoption()
        pending.arm(5, adoptionCount: 7)

        XCTAssertNil(pending.landed(adoptionCount: 7))
        XCTAssertEqual(pending.landed(adoptionCount: 8), 5)
    }

    // MARK: - Armar encima de algo que ya aterrizó

    /// **Lo que aterrizó se aplica aunque se arme otro encima antes de mirar.**
    /// Suena el que entró en el compás, no el que espera al siguiente; darle el
    /// segundo al modelo pondría la pantalla y el knob en un hueco que todavía
    /// no suena.
    ///
    /// Hace falta pulsar dos Patterns dentro del mismo cuadro a caballo de un
    /// límite de compás, así que no pasa casi nunca — y por eso se resuelve aquí,
    /// donde hay un test, y no confiando en que no pase.
    func testALandingIsNotLostWhenAnotherIsArmedBeforeReading() {
        let pending = PendingAdoption()
        pending.arm(5, adoptionCount: 0)

        // El compás llega —contador a 1— y antes de mirar se arma otro.
        pending.arm(9, adoptionCount: 1)

        XCTAssertEqual(pending.landed(adoptionCount: 1), 5, "se perdió el que ya sonaba")
        XCTAssertEqual(pending.armedPatternIndex, 9, "el que espera dejó de esperar")
        XCTAssertEqual(pending.landed(adoptionCount: 2), 9)
    }
}
