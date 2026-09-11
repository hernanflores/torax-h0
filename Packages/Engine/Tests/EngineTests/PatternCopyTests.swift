import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de copiar y borrar un Pattern.
///
/// **Es lo que hace que dieciséis huecos sirvan para algo.** Sin copiar, hacer
/// un break exige reconstruir doce Tracks a mano desde vacío, y los Patterns
/// existirían sin poder usarse como se usan: se parte del groove que ya funciona
/// y se le quita algo.
///
/// Las dos operaciones viven en `Bank` —que es donde están los dieciséis huecos—
/// y el `Project` las ofrece sobre el Bank vigente, que es como las llama la
/// pantalla.
final class PatternCopyTests: XCTestCase {

    // MARK: - Copiar, dentro del Bank

    /// El destino queda **igual por valor** al origen. No es una referencia
    /// compartida: editar uno después no toca al otro, y eso lo dice el test de
    /// abajo.
    func testCopyingAPatternLeavesAnEqualOneInTheSlot() {
        let bank = Bank().replacing(Pattern.initial, at: 0)
        let copied = bank.copyingPattern(from: 0, to: 4)

        XCTAssertEqual(copied.pattern(at: 4), Pattern.initial)
        XCTAssertEqual(copied.pattern(at: 0), Pattern.initial, "el origen no se mueve")
    }

    /// **Son valores, no alias.** Es la propiedad que hace que una variante sea
    /// una variante y no una segunda vista del mismo material.
    func testTheCopyIsIndependentOfTheOriginal() {
        let bank = Bank().replacing(Pattern.initial, at: 0).copyingPattern(from: 0, to: 1)
        let edited = bank.replacing(Pattern(), at: 1)

        XCTAssertEqual(edited.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(edited.pattern(at: 1), Pattern())
    }

    /// Copiar no toca ninguno de los otros catorce.
    func testCopyingLeavesEveryOtherSlotAlone() {
        let bank = Bank().replacing(Pattern.initial, at: 0).copyingPattern(from: 0, to: 9)

        for index in 0..<Bank.patternCount where index != 0 && index != 9 {
            XCTAssertEqual(bank.pattern(at: index), Pattern(), "Pattern \(index + 1)")
        }
    }

    /// Copiar sobre un hueco con material lo **sustituye**. No hay confirmación y
    /// no hay mezcla: el destino pasa a ser el origen.
    func testCopyingOverMaterialReplacesIt() {
        let other = Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)),
            at: 0
        )
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(other, at: 1)
            .copyingPattern(from: 0, to: 1)

        XCTAssertEqual(bank.pattern(at: 1), Pattern.initial)
    }

    /// Copiar un hueco sobre sí mismo no cambia nada y no es un error.
    func testCopyingASlotOntoItselfChangesNothing() {
        let bank = Bank().replacing(Pattern.initial, at: 3)
        XCTAssertEqual(bank.copyingPattern(from: 3, to: 3), bank)
    }

    /// Copiar un hueco vacío es legítimo: deja el destino vacío, que es lo mismo
    /// que borrarlo. No se trata como un caso especial porque no lo es.
    func testCopyingAnEmptySlotEmptiesTheDestination() {
        let bank = Bank().replacing(Pattern.initial, at: 5).copyingPattern(from: 0, to: 5)
        XCTAssertEqual(bank.pattern(at: 5), Pattern())
    }

    /// Fuera de rango, en cualquiera de los dos extremos, devuelve el Bank tal
    /// cual. No es un error, con el mismo criterio que el resto del motor.
    func testCopyingOutsideTheBankReturnsItUnchanged() {
        let bank = Bank().replacing(Pattern.initial, at: 0)
        let outside = [-1, Bank.patternCount, Int.max, Int.min]

        for index in outside {
            XCTAssertEqual(bank.copyingPattern(from: index, to: 2), bank, "origen \(index)")
            XCTAssertEqual(bank.copyingPattern(from: 0, to: index), bank, "destino \(index)")
        }
    }

    // MARK: - Borrar

    /// Borrar deja el hueco en `Pattern()`, que es lo que este track llama
    /// vacío: doce Tracks sin pool. No deja un agujero ni una bandera.
    func testClearingASlotLeavesItEmpty() {
        let bank = Bank().replacing(Pattern.initial, at: 6).clearingPattern(at: 6)
        XCTAssertEqual(bank.pattern(at: 6), Pattern())
    }

    func testClearingLeavesEveryOtherSlotAlone() {
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 1)
            .clearingPattern(at: 1)

        XCTAssertEqual(bank.pattern(at: 0), Pattern.initial)
    }

    /// Borrar un hueco ya vacío no cambia nada.
    func testClearingAnEmptySlotChangesNothing() {
        let bank = Bank().replacing(Pattern.initial, at: 0)
        XCTAssertEqual(bank.clearingPattern(at: 8), bank)
    }

    func testClearingOutsideTheBankReturnsItUnchanged() {
        let bank = Bank().replacing(Pattern.initial, at: 0)
        for index in [-1, Bank.patternCount, Int.max] {
            XCTAssertEqual(bank.clearingPattern(at: index), bank, "\(index)")
        }
    }

    /// Ni copiar ni borrar tocan el tempo del Bank.
    func testNeitherOperationTouchesTheTempo() {
        let bank = Bank().withTempo(Tempo(beatsPerMinute: 90)!).replacing(Pattern.initial, at: 0)
        XCTAssertEqual(bank.copyingPattern(from: 0, to: 1).tempo, Tempo(beatsPerMinute: 90)!)
        XCTAssertEqual(bank.clearingPattern(at: 0).tempo, Tempo(beatsPerMinute: 90)!)
    }

    // MARK: - Sobre el Project, que es como lo llama la pantalla

    // **`copyingSelectedPattern(to:)` se retiró** el 2026-09-10 (FR23 de
    // `pattern-copy_20260910`): su origen implícito era el defecto, porque la
    // pantalla conoce un índice y acababa pasándolo por las dos puntas. Lo que
    // probaba sobre el Project vive ahora en `PatternCopyWithOriginTests`, con
    // el origen dicho; aquí se conserva lo que era suyo y de nadie más — borrar,
    // y que ninguna de las dos operaciones mueva la selección.

    func testTheProjectClearsASlotInTheSelectedBank() {
        let project = Project.initial.clearingPattern(at: 0)
        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern())
    }

    /// Fuera de rango, el Project vuelve intacto.
    func testProjectLevelOperationsOutsideTheRangeReturnItUnchanged() {
        let project = Project.initial
        for index in [-1, Bank.patternCount, Int.max] {
            XCTAssertEqual(project.copyingPattern(from: 0, to: index), project, "copiar \(index)")
            XCTAssertEqual(project.clearingPattern(at: index), project, "borrar \(index)")
        }
    }

    /// Ninguna de las dos mueve la selección ni los ajustes de sesión.
    func testNeitherOperationMovesTheSelection() {
        let project = Project.initial.selectingPattern(0).withClockSource(.external)
        let after = project.copyingPattern(from: 0, to: 4).clearingPattern(at: 9)

        XCTAssertEqual(after.selectedBank, project.selectedBank)
        XCTAssertEqual(after.selectedPattern, project.selectedPattern)
        XCTAssertEqual(after.clockSource, .external)
    }
}
