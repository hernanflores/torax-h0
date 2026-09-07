import Engine
import XCTest

@testable import Persistence

private typealias Pattern = Engine.Pattern

/// Tests de `Save Bank` y `Reload`: el punto de retorno intencional.
///
/// **Lo que se prueba aquí es que son dos capas independientes.** El Autosave
/// escribe el trabajo en curso todo el rato; `Save Bank` es una decisión. Si
/// editar después de guardar moviera el punto de retorno, `Reload` no serviría
/// para nada — que es el fallo que estos tests existen para impedir.
final class RestorePointTests: XCTestCase {

    private var files: InMemoryFileSystem!
    private var store: ProjectStore!
    private let root = URL(fileURLWithPath: "/torax")

    override func setUp() {
        super.setUp()
        files = InMemoryFileSystem()
        store = ProjectStore(fileSystem: files, directory: root)
    }

    private func bank(_ tempo: Double) -> Bank {
        Bank().replacing(Pattern.initial, at: 0).withTempo(Tempo(beatsPerMinute: tempo)!)
    }

    // MARK: - Save Bank

    func testSavingABankCreatesItsRestorePoint() throws {
        try store.saveRestorePoint(bank(100), at: 3)

        XCTAssertTrue(store.hasRestorePoint(at: 3))
        XCTAssertEqual(try store.restorePoint(at: 3), bank(100))
    }

    /// **Solo el suyo.** Es el gránulo que la Pre Spec le da: «el punto de
    /// retorno intencional de *un* Bank».
    func testSavingOneBankDoesNotTouchTheOtherFifteen() throws {
        try store.saveRestorePoint(bank(100), at: 3)

        for index in 0..<Project.bankCount where index != 3 {
            XCTAssertFalse(store.hasRestorePoint(at: index), "Bank \(index + 1)")
        }
    }

    /// Guardar dos veces **sustituye** el punto: hay uno por Bank, no una pila.
    func testSavingTwiceReplacesThePoint() throws {
        try store.saveRestorePoint(bank(100), at: 0)
        try store.saveRestorePoint(bank(174), at: 0)

        XCTAssertEqual(try store.restorePoint(at: 0)?.tempo, Tempo(beatsPerMinute: 174)!)
    }

    /// **El punto de retorno vive en su propio fichero**, no dentro del de
    /// trabajo: es lo que hace que las dos capas no se pisen.
    func testTheRestorePointHasItsOwnFile() throws {
        try store.saveRestorePoint(bank(100), at: 0)

        XCTAssertNotEqual(store.restoreURL(at: 0), store.bankURL(at: 0))
        XCTAssertTrue(store.restoreURL(at: 0).path.contains("/restore/"))
        XCTAssertNil(try files.read(store.bankURL(at: 0)), "escribió también el de trabajo")
    }

    // MARK: - Las dos capas son independientes

    /// **Editar después de guardar no mueve el punto de retorno.** Es la
    /// propiedad de la que depende que `Reload` sirva para algo.
    func testEditingAfterSavingDoesNotMoveTheRestorePoint() throws {
        try store.saveRestorePoint(bank(100), at: 0)
        try store.save(bank(174), at: 0)

        XCTAssertEqual(try store.restorePoint(at: 0)?.tempo, Tempo(beatsPerMinute: 100)!)
        XCTAssertEqual(try store.loadBank(at: 0)?.tempo, Tempo(beatsPerMinute: 174)!)
    }

    /// Y el Autosave tampoco lo mueve, que es la misma frase desde el otro lado.
    func testTheAutosaveDoesNotMoveTheRestorePoint() throws {
        try store.saveRestorePoint(bank(100), at: 0)

        let clock = TestClock()
        let autosave = Autosave(store: store, quietPeriod: 1, now: clock.now)
        autosave.changed(bank(90), at: 0)
        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(try store.restorePoint(at: 0)?.tempo, Tempo(beatsPerMinute: 100)!)
    }

    // MARK: - Reload

    /// Guardar, editar, recargar devuelve **exactamente** el estado guardado.
    func testReloadingReturnsExactlyTheSavedState() throws {
        let saved = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 9)
            .withTempo(Tempo(beatsPerMinute: 96)!)

        try store.saveRestorePoint(saved, at: 2)
        try store.save(Bank(), at: 2)

        XCTAssertEqual(try store.restorePoint(at: 2), saved)
    }

    /// **Sin punto de retorno no está disponible, y lo dice.** Volver a vacío no
    /// es volver, es borrar.
    func testReloadIsUnavailableWithoutARestorePoint() {
        let availability = store.reloadAvailability(at: 0)

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.reason, "Este Bank no se ha guardado todavía")
    }

    /// Y con punto de retorno, sí.
    func testReloadIsAvailableOnceTheBankIsSaved() throws {
        try store.saveRestorePoint(bank(100), at: 0)

        XCTAssertTrue(store.reloadAvailability(at: 0).isAvailable)
        XCTAssertNil(store.reloadAvailability(at: 0).reason)
    }

    /// La disponibilidad es **por Bank**: guardar el 1 no habilita el 2.
    func testAvailabilityIsPerBank() throws {
        try store.saveRestorePoint(bank(100), at: 0)

        XCTAssertTrue(store.reloadAvailability(at: 0).isAvailable)
        XCTAssertFalse(store.reloadAvailability(at: 1).isAvailable)
    }

    /// Un Bank sin punto de retorno devuelve `nil` y no lanza: no haberlo
    /// guardado nunca no es un error.
    func testAMissingRestorePointIsNilAndNotAnError() throws {
        XCTAssertNil(try store.restorePoint(at: 0))
    }

    /// **El motivo es legible, no un código.** Un botón deshabilitado sin
    /// explicación se lee como un fallo de la app; aquí es información sobre
    /// cómo funciona el guardado.
    func testTheReasonIsSomethingAPersonCanRead() {
        let reason = try! XCTUnwrap(store.reloadAvailability(at: 0).reason)

        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(reason.contains("nil"))
        XCTAssertFalse(reason.contains("Error"))
    }

    /// Un fallo al guardar el punto de retorno se propaga, como cualquier otra
    /// escritura, y deja el estado de fallo puesto.
    func testAFailedRestorePointSaveIsReported() {
        files.failEveryWrite = CocoaError(.fileWriteOutOfSpace)

        XCTAssertThrowsError(try store.saveRestorePoint(bank(100), at: 0))
        XCTAssertNotNil(store.lastSaveFailure)
    }
}
