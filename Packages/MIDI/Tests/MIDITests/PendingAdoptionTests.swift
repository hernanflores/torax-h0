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

    private func adoption(bank: Int = 2, slot: Int = 5, steps: Int = 8)
        -> PendingAdoption.Adoption
    {
        PendingAdoption.Adoption(
            bankIndex: bank,
            patternIndex: slot,
            pattern: Pattern().replacing(
                Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)), at: 0)
        )
    }

    // MARK: - Lo que se recuerda al armar

    func testItStartsWithNothingArmed() {
        XCTAssertNil(PendingAdoption().armedPatternIndex)
    }

    func testArmingRemembersTheSlot() {
        let pending = PendingAdoption()

        pending.arm(adoption(), adoptionCount: 0)

        XCTAssertEqual(pending.armedPatternIndex, 5)
    }

    /// Armar dos veces antes del compás deja el último, igual que la ranura del
    /// handoff: cambiar de idea antes del límite es normal en directo.
    func testArmingTwiceBeforeTheBarKeepsTheLast() {
        let pending = PendingAdoption()
        let last = adoption(bank: 4, slot: 9, steps: 12)

        pending.arm(adoption(), adoptionCount: 0)
        pending.arm(last, adoptionCount: 0)

        XCTAssertEqual(pending.armedPatternIndex, 9)
        XCTAssertEqual(pending.landed(adoptionCount: 1), last)
    }

    /// Cancelar quita lo pendiente sin aplicarlo. Es lo que hace el camino
    /// parado, que ya entra en el acto.
    func testCancellingClearsTheArmedSlot() {
        let pending = PendingAdoption()

        pending.arm(adoption(), adoptionCount: 0)
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
        let adoption = adoption()
        pending.arm(adoption, adoptionCount: 0)

        XCTAssertEqual(pending.landed(adoptionCount: 1), adoption)
        XCTAssertNil(pending.armedPatternIndex, "no se limpió lo pendiente")
    }

    /// El aterrizaje conserva la identidad del Bank, el hueco y el material
    /// exacto que se entregó al scheduler, aunque el modelo ya mire otra cosa.
    func testALandingCarriesTheArmedBankSlotAndPatternSnapshot() {
        let pending = PendingAdoption()
        let armed = adoption(bank: 7, slot: 11, steps: 12)

        pending.arm(armed, adoptionCount: 3)

        XCTAssertEqual(pending.landed(adoptionCount: 4), armed)
    }

    /// Y no se aplica dos veces: el cuadro siguiente ya no tiene nada que hacer.
    func testItDoesNotYieldTheSameAdoptionTwice() {
        let pending = PendingAdoption()
        let adoption = adoption()
        pending.arm(adoption, adoptionCount: 0)

        XCTAssertEqual(pending.landed(adoptionCount: 1), adoption)
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
        pending.arm(adoption(), adoptionCount: 3)

        XCTAssertNil(pending.landed(adoptionCount: 3))
        XCTAssertEqual(pending.armedPatternIndex, 5, "dejó de esperar")
    }

    /// Un contador que ya venía movido antes de armar tampoco dispara: lo que
    /// importa es que se mueva **después**.
    func testACounterAlreadyAheadBeforeArmingDoesNotFire() {
        let pending = PendingAdoption()
        let adoption = adoption()
        pending.arm(adoption, adoptionCount: 7)

        XCTAssertNil(pending.landed(adoptionCount: 7))
        XCTAssertEqual(pending.landed(adoptionCount: 8), adoption)
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
        let landed = adoption(bank: 2, slot: 5, steps: 8)
        let waiting = adoption(bank: 9, slot: 9, steps: 12)
        pending.arm(landed, adoptionCount: 0)

        // El compás llega —contador a 1— y antes de mirar se arma otro.
        pending.arm(waiting, adoptionCount: 1)

        XCTAssertEqual(pending.landed(adoptionCount: 1), landed, "se perdió el que ya sonaba")
        XCTAssertEqual(pending.armedPatternIndex, 9, "el que espera dejó de esperar")
        XCTAssertEqual(pending.landed(adoptionCount: 2), waiting)
    }
}
