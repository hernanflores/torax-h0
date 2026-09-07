import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de «esto tiene material».
///
/// **El criterio ya existía y no se inventa otro.** `TransportModel` lo escribe
/// así desde la pantalla del handoff: un Pattern tiene material si **alguno de
/// sus doce Tracks tiene pool**. Lo que cambia el 2026-09-07 es dónde vive —baja
/// a `Engine`, donde hay tests— y que ahora hay 256 Patterns a los que
/// preguntárselo en vez de uno.
///
/// **Por qué el pool y no el Shape.** Un Track sin pool dispara sus Pulses y no
/// tiene alturas que emitir, así que es silencio; los Pulses no pueden ser cero,
/// porque la Pre Spec los define de 1 a Steps. El silencio sale del material, y
/// esa decisión está tomada desde `Pattern.emptyCycle`.
final class MaterialTests: XCTestCase {

    // MARK: - Un Pattern

    func testAnEmptyPatternHasNoMaterial() {
        XCTAssertFalse(Pattern().hasMaterial)
    }

    /// El Pattern de arranque tiene material: una altura en el Track 1.
    func testTheInitialPatternHasMaterial() {
        XCTAssertTrue(Pattern.initial.hasMaterial)
    }

    /// **Basta uno de los doce.** Es la definición, y el test la recorre entera
    /// para que un error de índice no se esconda en el Track 12.
    func testMaterialInAnySingleTrackIsEnough() {
        for index in 0..<Pattern.trackCount {
            let pattern = Pattern().replacing(
                Cycle(
                    shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
                    pool: PitchPool().inserting(Pitch(60)!)),
                at: index
            )
            XCTAssertTrue(pattern.hasMaterial, "Track \(index + 1)")
        }
    }

    /// Un Shape sin pool no es material: dispara y no tiene qué emitir.
    func testAShapeWithoutAPoolIsNotMaterial() {
        let pattern = Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)),
            at: 0
        )
        XCTAssertFalse(pattern.hasMaterial)
    }

    // MARK: - Un Bank

    func testAFreshBankHasNoPatternsWithMaterial() {
        XCTAssertEqual(Bank().patternsWithMaterial, 0)
        XCTAssertFalse(Bank().hasMaterial)
    }

    func testABankCountsOnlyThePatternsThatHaveMaterial() {
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 5)
            .replacing(Pattern.initial, at: 15)

        XCTAssertEqual(bank.patternsWithMaterial, 3)
        XCTAssertTrue(bank.hasMaterial)
    }

    /// **Cuenta los que tienen material, no los huecos.** Es la regla que
    /// `BankGrid` ya lleva escrita: decir «16 patterns» con quince vacíos sería
    /// contar sitios y llamarlos contenido.
    func testAFullBankCountsSixteen() {
        var bank = Bank()
        for index in 0..<Bank.patternCount {
            bank = bank.replacing(Pattern.initial, at: index)
        }
        XCTAssertEqual(bank.patternsWithMaterial, Bank.patternCount)
    }

    /// Borrar un Pattern baja la cuenta. Es la otra mitad: la cuenta es una
    /// lectura del material, no un contador que alguien mantiene.
    func testClearingAPatternLowersTheCount() {
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 1)

        XCTAssertEqual(bank.clearingPattern(at: 1).patternsWithMaterial, 1)
    }

    /// Cuáles, y no solo cuántos: es lo que la rejilla necesita para pintar cada
    /// hueco.
    func testABankSaysWhichPatternsHaveMaterial() {
        let bank = Bank().replacing(Pattern.initial, at: 2)
        let flags = bank.patternsHavingMaterial

        XCTAssertEqual(flags.count, Bank.patternCount)
        XCTAssertTrue(flags[2])
        for index in 0..<Bank.patternCount where index != 2 {
            XCTAssertFalse(flags[index], "Pattern \(index + 1)")
        }
    }

    // MARK: - Un Project

    func testAFreshProjectHasNoBanksWithMaterial() {
        XCTAssertEqual(Project().banksWithMaterial, 0)
    }

    func testAProjectCountsTheBanksThatHaveSomething() {
        let loaded = Bank().replacing(Pattern.initial, at: 0)
        let project = Project().replacing(loaded, at: 0).replacing(loaded, at: 9)

        XCTAssertEqual(project.banksWithMaterial, 2)
    }

    /// El Project de arranque tiene exactamente un Bank con material y un
    /// Pattern dentro de él: es la app de hoy, dicha en el vocabulario nuevo.
    func testTheInitialProjectHasExactlyOneOfEach() {
        XCTAssertEqual(Project.initial.banksWithMaterial, 1)
        XCTAssertEqual(Project.initial.bank(at: 0)?.patternsWithMaterial, 1)
    }
}
