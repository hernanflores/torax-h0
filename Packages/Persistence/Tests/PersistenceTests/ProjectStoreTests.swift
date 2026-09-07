import Engine
import XCTest

@testable import Persistence

private typealias Pattern = Engine.Pattern

/// Tests del almacén: escribir, leer, sobrevivir a un disco que falla y no
/// perder nunca un fichero del usuario.
final class ProjectStoreTests: XCTestCase {

    private var files: InMemoryFileSystem!
    private var store: ProjectStore!
    private let root = URL(fileURLWithPath: "/torax")

    override func setUp() {
        super.setUp()
        files = InMemoryFileSystem()
        store = ProjectStore(fileSystem: files, directory: root, timestamp: { "20260907-120000" })
    }

    // MARK: - El JSON se lee con los ojos (NFR7)

    /// **Indentado y con las claves ordenadas.** Es la mitad de la razón por la
    /// que `tech-stack.md` eligió JSON: «inspeccionable, diffeable».
    func testTheWrittenJSONIsIndentedAndSorted() throws {
        try store.save(Project())

        let data = try XCTUnwrap(files.read(store.projectURL))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), "el JSON salió en una sola línea")
        XCTAssertTrue(text.contains("  \"schemaVersion\""), "el JSON no está indentado")

        let keys = ["clockSource", "schemaVersion", "selectedBank", "selectedPattern"]
        let positions = keys.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        XCTAssertEqual(positions.count, keys.count)
        XCTAssertEqual(positions, positions.sorted(), "las claves no salieron ordenadas")
    }

    /// **Dos guardados del mismo material producen bytes idénticos.** Sin eso,
    /// «diffeable» es mentira: cada guardado saldría distinto y el `diff` no
    /// diría nada.
    func testWritingTheSameProjectTwiceProducesIdenticalBytes() throws {
        try store.save(Project.initial)
        let first = try XCTUnwrap(files.read(store.projectURL))

        try store.save(Project.initial)
        let second = try XCTUnwrap(files.read(store.projectURL))

        XCTAssertEqual(first, second)
    }

    // MARK: - Escribir y leer un Bank (FR18, FR20)

    func testABankSurvivesAWriteAndARead() throws {
        let bank = Bank().replacing(Pattern.initial, at: 3).withTempo(Tempo(beatsPerMinute: 96)!)

        try store.save(bank, at: 5)

        XCTAssertEqual(try store.loadBank(at: 5), bank)
    }

    /// **Guardar el Bank 3 no toca los otros quince.** Es lo que el reparto de
    /// ficheros existe para permitir, y lo que hace barato el Autosave.
    func testSavingOneBankTouchesOnlyItsFile() throws {
        try store.save(Project.initial)
        let before = files.fileCount

        try store.save(Bank().replacing(Pattern.initial, at: 0), at: 2)

        XCTAssertEqual(files.fileCount, before, "apareció un fichero que no debía")
        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 2)), 2)
        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 7)), 1, "se reescribió otro Bank")
    }

    /// Un Bank que nunca se guardó no existe, y eso no es un error: es la
    /// primera vez que se abre la app.
    func testAMissingBankIsNilAndNotAnError() throws {
        XCTAssertNil(try store.loadBank(at: 0))
    }

    /// Los dieciséis ficheros se llaman como se enseñan, con cero delante para
    /// que ordenen: `bank-01.json` … `bank-16.json`.
    func testTheBankFilesAreNamedAsTheyAreShown() {
        XCTAssertEqual(store.bankURL(at: 0).lastPathComponent, "bank-01.json")
        XCTAssertEqual(store.bankURL(at: 15).lastPathComponent, "bank-16.json")
        XCTAssertTrue(store.bankURL(at: 0).path.contains("/banks/"))
    }

    /// **En Application Support y no en Documents** (FR20): el estado de trabajo
    /// es la memoria del instrumento, no un documento que el usuario administre.
    func testTheDefaultDirectoryIsApplicationSupport() {
        let path = ProjectStore.defaultDirectory.path
        XCTAssertTrue(path.contains("Application Support"), path)
        XCTAssertFalse(path.contains("Documents"), path)
        XCTAssertTrue(path.hasSuffix("ToraxH0"), path)
    }

    // MARK: - La escritura es atómica (FR21)

    /// **Si la escritura falla, el fichero anterior sigue intacto y legible.**
    /// Es la promesa de la que depende que un Autosave interrumpido no destruya
    /// el guardado anterior.
    func testAFailedWriteLeavesThePreviousFileIntact() throws {
        let good = Bank().replacing(Pattern.initial, at: 0)
        try store.save(good, at: 0)

        files.failNextWrite = CocoaError(.fileWriteOutOfSpace)
        XCTAssertThrowsError(try store.save(Bank(), at: 0))

        XCTAssertEqual(try store.loadBank(at: 0), good)
    }

    /// Y no deja basura: ni temporales huérfanos ni ficheros a medias.
    func testAFailedWriteLeavesNoLeftovers() throws {
        try store.save(Bank(), at: 0)
        let before = files.fileCount

        files.failNextWrite = CocoaError(.fileWriteOutOfSpace)
        try? store.save(Bank(), at: 1)

        XCTAssertEqual(files.fileCount, before)
    }

    // MARK: - El fallo se propaga, no se traga (FR21)

    func testAFailedSaveReachesTheCaller() {
        files.failNextWrite = CocoaError(.fileWriteOutOfSpace)
        XCTAssertThrowsError(try store.save(Bank(), at: 0))
    }

    /// **El aviso no se calla solo**: mientras el disco siga lleno, el estado de
    /// fallo sigue puesto. Un Autosave silencioso que lleva diez minutos fallando
    /// es la peor forma de perder trabajo.
    func testTheFailureStateSurvivesUntilASaveWorks() {
        XCTAssertNil(store.lastSaveFailure)

        files.failEveryWrite = CocoaError(.fileWriteOutOfSpace)
        try? store.save(Bank(), at: 0)
        XCTAssertNotNil(store.lastSaveFailure)

        try? store.save(Bank(), at: 1)
        XCTAssertNotNil(store.lastSaveFailure, "el aviso se apagó con el disco todavía lleno")
    }

    /// Y se apaga en cuanto uno funciona. Un aviso que no se apaga cuando el
    /// problema se resuelve enseña a ignorarlo.
    func testASuccessfulSaveClearsTheFailure() throws {
        files.failNextWrite = CocoaError(.fileWriteOutOfSpace)
        try? store.save(Bank(), at: 0)
        XCTAssertNotNil(store.lastSaveFailure)

        try store.save(Bank(), at: 0)
        XCTAssertNil(store.lastSaveFailure)
    }

    // MARK: - Un fichero ilegible se aparta y no se pierde (FR22)

    /// **Corrupto y versión futura toman el mismo camino**, que es lo que la
    /// Fase 3 preparó al hacer los dos errores distinguibles: se apartan igual,
    /// aunque lo que se le cuente al usuario no sea lo mismo.
    func testACorruptHeaderIsSetAsideAndTheAppStillOpens() throws {
        try store.save(Project.initial)
        files.plant("esto no es json", at: store.projectURL)

        let result = store.load()

        XCTAssertEqual(result.rescuedFiles, ["project.20260907-120000.unreadable"])
        XCTAssertTrue(result.needsAttention)
    }

    func testAFutureSchemaVersionIsSetAsideToo() throws {
        let future = ProjectRecord(Project.initial, schemaVersion: 99)
        let encoder = JSONEncoder()
        files.plant(
            String(data: try encoder.encode(future), encoding: .utf8)!, at: store.projectURL)

        let result = store.load()

        XCTAssertEqual(result.rescuedFiles.count, 1)
        XCTAssertTrue(result.rescuedFiles[0].hasSuffix(".unreadable"))
    }

    /// **El fichero original sigue existiendo.** Es la única copia de lo que el
    /// usuario tenía, y aunque esta app no sepa leerlo, otra versión —o una
    /// persona con un editor— puede.
    func testTheSetAsideFileIsKeptAndNotDeleted() throws {
        files.plant("basura", at: store.projectURL)

        _ = store.load()

        let apartado = root.appendingPathComponent("project.20260907-120000.unreadable")
        XCTAssertEqual(try files.read(apartado), Data("basura".utf8))
        XCTAssertNil(try files.read(store.projectURL), "el fichero ilegible se quedó en su sitio")
    }

    /// **Un Bank ilegible no se lleva por delante a los otros quince.** Es la
    /// ventaja del reparto de ficheros que más se nota el día malo.
    func testOneUnreadableBankDoesNotLoseTheOthers() throws {
        var project = Project.initial
        project = project.replacing(Bank().replacing(Pattern.initial, at: 0), at: 4)
        try store.save(project)

        files.plant("{ roto", at: store.bankURL(at: 4))

        let result = store.load()

        XCTAssertEqual(result.rescuedFiles.count, 1)
        XCTAssertEqual(result.project.bank(at: 0)?.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(result.project.bank(at: 4), Bank(), "el Bank ilegible vuelve vacío")
    }

    /// Apartar dos veces no pisa el primero: la marca lleva segundos.
    func testTheTimestampHasEnoughResolutionToNotOverwrite() {
        let stamp = ProjectStore.defaultTimestamp()
        XCTAssertEqual(stamp.count, "20260907-120000".count)
        XCTAssertTrue(stamp.contains("-"))
    }

    // MARK: - Cargar el Project completo (FR20, FR23)

    func testAProjectSurvivesAFullSaveAndLoad() throws {
        let project = Project.initial
            .selectingBank(3)
            .selectingPattern(7)
            .selectingTrack(2)
            .withClockSource(.external)
            .remembering(destinationNamed: "Digitakt", sourceNamed: "BeatStep Pro")

        try store.save(project)

        XCTAssertEqual(store.load().project, project)
    }

    /// La primera vez que se abre la app no hay nada, y eso no es un fallo.
    func testAnEmptyDiskLoadsAnEmptyProject() {
        let result = store.load()

        XCTAssertEqual(result.project, Project())
        XCTAssertTrue(result.wasEmpty)
        XCTAssertFalse(result.needsAttention)
    }

    /// **Un Project a medio escribir no impide arrancar**: los Banks que falten
    /// salen vacíos.
    func testAHalfWrittenProjectStillLoads() throws {
        try store.saveHeader(of: Project.initial.selectingBank(2))
        try store.save(Bank().replacing(Pattern.initial, at: 0), at: 0)

        let result = store.load()

        XCTAssertEqual(result.project.selectedBank, 2)
        XCTAssertEqual(result.project.bank(at: 0)?.patternsWithMaterial, 1)
        XCTAssertEqual(result.project.bank(at: 9), Bank())
    }

    /// **Sin cabecera legible, los Banks que sí se leyeron no se pierden.** Se
    /// pierde dónde se estaba mirando, que es lo barato.
    func testTheBanksSurviveAnUnreadableHeader() throws {
        try store.save(Project.initial)
        files.plant("roto", at: store.projectURL)

        let result = store.load()

        XCTAssertEqual(result.project.bank(at: 0)?.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(result.project.selectedBank, 0)
        XCTAssertTrue(result.needsAttention)
    }

    /// Un endpoint guardado que ya no existe se restaura como nombre y ya:
    /// que no case con nada es un estado esperado, no un error.
    func testARememberedEndpointComesBackEvenIfTheHardwareIsGone() throws {
        try store.save(
            Project().remembering(destinationNamed: "un sinte que ya no está", sourceNamed: nil))

        let project = store.load().project

        XCTAssertEqual(project.destinationName, "un sinte que ya no está")
        XCTAssertNil(project.sourceName)
    }
}
