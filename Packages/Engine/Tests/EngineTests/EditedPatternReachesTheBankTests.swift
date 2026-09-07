import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de que una edición del Pattern llegue al Bank y al Project.
///
/// **Escritos el 2026-09-07 después de un fallo en dispositivo**: con una pieza
/// sonando, el card de bancos decía «no patterns» y el hueco activo `empty`. La
/// causa era que `pattern` y `project` eran dos estados separados en `App` y solo
/// el primero recibía las ediciones — y lo peor no era lo que se veía, sino que
/// **`Save Bank` fijaba el punto de retorno sobre material que ya no existía**.
///
/// El arreglo vive en `App`, que no se mide. Lo que se puede probar aquí es la
/// mecánica de la que depende: que escribir el Pattern en su hueco deje al Bank
/// y al Project diciendo la verdad. Si alguna de estas propiedades se rompiera,
/// el fallo volvería aunque el cableado fuera correcto.
final class EditedPatternReachesTheBankTests: XCTestCase {

    /// Un Pattern con material en un Track.
    private func edited() -> Pattern {
        Pattern().replacing(
            Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
                pool: PitchPool().inserting(Pitch(60)!)
            ),
            at: 0
        )
    }

    /// **Escribir el Pattern en su hueco hace que el Bank lo cuente.**
    ///
    /// Es la lectura exacta que el card de bancos hace, y la que decía «no
    /// patterns».
    func testWritingAPatternMakesTheBankCountIt() {
        let bank = Bank().replacing(edited(), at: 0)

        XCTAssertEqual(bank.patternsWithMaterial, 1)
        XCTAssertTrue(bank.hasMaterial)
    }

    /// Y que el hueco deje de decir `empty`, que es lo que se veía en la rejilla.
    func testTheSlotStopsBeingEmpty() {
        let bank = Bank().replacing(edited(), at: 0)

        XCTAssertEqual(
            bank.slotStates(playing: 0, queued: nil, isRunning: false)[0],
            .ready)
        XCTAssertEqual(
            Bank().slotStates(playing: 0, queued: nil, isRunning: false)[0],
            .empty,
            "el hueco vacío tiene que seguir diciendo empty")
    }

    /// **Y el Project entero lo ve.** Es la cadena completa: Pattern → Bank →
    /// Project, que es por donde la edición tiene que viajar.
    func testTheProjectSeesTheEditThroughTheWholeChain() {
        var project = Project.initial.selectingBank(2).selectingPattern(5)

        let bank = (project.bank(at: 2) ?? Bank()).replacing(edited(), at: 5)
        project = project.replacing(bank, at: 2)

        XCTAssertEqual(project.bank(at: 2)?.pattern(at: 5), edited())
        XCTAssertEqual(project.bank(at: 2)?.patternsWithMaterial, 1)
        XCTAssertEqual(project.banksWithMaterial, 2, "el Bank 1 conserva el suyo")
    }

    /// **Escribir en el hueco elegido y no en el primero.** El fallo simétrico
    /// que un arreglo apresurado introduciría: guardar siempre en el 0.
    func testTheEditLandsInTheSelectedSlotAndNotTheFirst() {
        var project = Project().selectingBank(3).selectingPattern(9)

        let bank = (project.bank(at: 3) ?? Bank()).replacing(edited(), at: 9)
        project = project.replacing(bank, at: 3)

        XCTAssertEqual(project.bank(at: 3)?.pattern(at: 9), edited())
        XCTAssertEqual(project.bank(at: 3)?.pattern(at: 0), Pattern())
        XCTAssertEqual(project.bank(at: 0), Bank())
    }

    /// **El punto de retorno se fija sobre lo que hay, no sobre lo que había.**
    ///
    /// Es la consecuencia grave del fallo: `Save Bank` guardaba el Bank del
    /// Project, y el Project no tenía la edición.
    func testSavingCapturesTheEditedBankAndNotTheStaleOne() {
        let stale = Bank()
        let current = stale.replacing(edited(), at: 0)

        XCTAssertNotEqual(current, stale)
        XCTAssertEqual(current.patternsWithMaterial, 1)
        XCTAssertEqual(stale.patternsWithMaterial, 0)
    }
}
