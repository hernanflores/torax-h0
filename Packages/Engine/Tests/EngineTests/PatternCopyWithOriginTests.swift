import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de copiar un Pattern **con origen explícito**.
///
/// **Existe porque el origen implícito era el defecto.** `copyingSelectedPattern(to:)`
/// tomaba el hueco seleccionado como origen, y la rejilla le pasaba ese mismo
/// hueco como destino: la celda se copiaba sobre sí misma y no cambiaba nada.
/// Con las dos puntas explícitas el error deja de poder escribirse.
///
/// El caso `from == to` sigue sin cambiar nada, pero ahora es una decisión
/// escrita y no un accidente de cableado.
final class PatternCopyWithOriginTests: XCTestCase {

    /// Copiar de un hueco a otro dentro del Bank vigente, **con el origen
    /// distinto del seleccionado**: es el gesto que la pantalla no podía
    /// expresar.
    func testCopyingFromASlotOtherThanTheSelectedOne() {
        let project = Project.initial.selectingPattern(9).copyingPattern(from: 0, to: 4)

        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 4), Pattern.initial)
        XCTAssertEqual(
            project.bank(at: 0)?.pattern(at: 0), Pattern.initial, "el origen no se mueve")
    }

    /// Opera sobre el Bank seleccionado, no sobre el primero.
    func testCopyingHappensInsideTheSelectedBank() {
        let project = Project()
            .replacing(Bank().replacing(Pattern.initial, at: 2), at: 5)
            .selectingBank(5)
            .copyingPattern(from: 2, to: 3)

        XCTAssertEqual(project.bank(at: 5)?.pattern(at: 3), Pattern.initial)
        XCTAssertEqual(project.bank(at: 0), Bank(), "el Bank 1 no se toca")
    }

    /// Copiar sobre un hueco con material lo sustituye, sin confirmación y sin
    /// mezcla — el mismo criterio que `Bank.copyingPattern(from:to:)`.
    func testCopyingOverMaterialReplacesIt() {
        let other = Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)),
            at: 0
        )
        let project = Project.initial
            .replacing(
                Bank().replacing(Pattern.initial, at: 0).replacing(other, at: 1),
                at: 0
            )
            .copyingPattern(from: 0, to: 1)

        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 1), Pattern.initial)
    }

    /// Fuera de rango, en cualquiera de las dos puntas, el Project vuelve
    /// intacto. No es un error, con el criterio del resto del motor (FR24).
    func testCopyingOutsideTheRangeReturnsTheProjectUnchanged() {
        let project = Project.initial

        for index in [-1, Bank.patternCount, Int.max, Int.min] {
            XCTAssertEqual(project.copyingPattern(from: index, to: 2), project, "origen \(index)")
            XCTAssertEqual(project.copyingPattern(from: 0, to: index), project, "destino \(index)")
        }
    }

    /// **El caso que el defecto disparaba**, ahora escrito y esperado: origen y
    /// destino iguales dejan el Project como estaba.
    func testCopyingASlotOntoItselfChangesNothing() {
        let project = Project.initial
        XCTAssertEqual(project.copyingPattern(from: 0, to: 0), project)
    }

    /// Copiar no mueve la selección ni los ajustes de sesión.
    func testCopyingMovesNeitherTheSelectionNorTheSessionSettings() {
        let project = Project.initial
            .selectingPattern(3)
            .selectingTrack(4)
            .withClockSource(.external)
            .remembering(destinationNamed: "BeatStep Pro", sourceNamed: "Network Session 1")
        let after = project.copyingPattern(from: 0, to: 7)

        XCTAssertEqual(after.selectedBank, project.selectedBank)
        XCTAssertEqual(after.selectedPattern, project.selectedPattern)
        XCTAssertEqual(after.selectedTrack, project.selectedTrack)
        XCTAssertEqual(after.clockSource, project.clockSource)
        XCTAssertEqual(after.destinationName, project.destinationName)
        XCTAssertEqual(after.sourceName, project.sourceName)
    }

    // MARK: - Escribir un Pattern suelto, que es lo que el pegado necesita

    /// Un `Pattern` cualquiera entra en el hueco indicado del Bank vigente.
    ///
    /// **Es lo que `copyingSelectedPattern(to:)` no puede expresar** (FR22): el
    /// material del portapapeles puede venir de otro Bank, donde el hueco 3
    /// contiene otra cosa. El origen no es un índice, es un valor.
    func testReplacingALoosePatternIntoASlotOfTheSelectedBank() {
        let material = Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)),
            at: 0
        )
        let project = Project.initial.selectingBank(5).replacing(material, at: 3)

        XCTAssertEqual(project.bank(at: 5)?.pattern(at: 3), material)
    }

    /// Escribir un Pattern no toca ninguno de los otros quince huecos ni los otros Banks.
    func testReplacingLeavesEveryOtherSlotAndBankAlone() {
        let project = Project.initial.replacing(Pattern(), at: 4)

        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(project.bank(at: 1), Bank())
    }

    /// Escribir sobre un hueco con material lo sustituye, sin mezcla.
    func testReplacingOverMaterialReplacesIt() {
        let project = Project.initial.replacing(Pattern(), at: 0)
        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern())
    }

    /// Fuera de rango, el Project vuelve intacto (FR24).
    func testReplacingAPatternOutsideTheRangeReturnsTheProjectUnchanged() {
        let project = Project.initial

        for index in [-1, Bank.patternCount, Int.max, Int.min] {
            XCTAssertEqual(project.replacing(Pattern.initial, at: index), project, "hueco \(index)")
        }
    }

    /// Escribir un Pattern no mueve la selección ni los ajustes de sesión.
    func testReplacingAPatternMovesNeitherTheSelectionNorTheSessionSettings() {
        let project = Project.initial.selectingPattern(3).withClockSource(.external)
        let after = project.replacing(Pattern(), at: 7)

        XCTAssertEqual(after.selectedBank, project.selectedBank)
        XCTAssertEqual(after.selectedPattern, project.selectedPattern)
        XCTAssertEqual(after.clockSource, project.clockSource)
    }
}
