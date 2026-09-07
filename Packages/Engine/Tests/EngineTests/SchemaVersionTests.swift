import XCTest

@testable import Engine

/// Tests de la versión de esquema.
///
/// **Entra desde el primer commit aunque no haya nada a lo que migrar**, porque
/// `tech-stack.md` lo exige y porque el primer cambio ya está fechado: las
/// rebanadas 5 y 6 —Note Repeater y Modulation— añaden campos al `Cycle`.
///
/// **Lo que no entra son migradores.** Escribir uno de v1 a v2 antes de que
/// exista v2 es probar una migración inventada, que envejece con el esquema
/// real. Lo que sí entra es el punto donde enchufarla y, sobre todo, **un error
/// distinguible**: la Fase 4 tiene que poder tratar una versión futura igual que
/// un fichero corrupto, y para eso necesita saber cuál de los dos es.
final class SchemaVersionTests: XCTestCase {

    /// La versión que esta app escribe.
    func testTheCurrentSchemaVersionIsOne() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    /// Todo Project escrito lleva la versión vigente.
    func testEveryWrittenProjectCarriesTheCurrentVersion() {
        XCTAssertEqual(ProjectRecord(Project()).schemaVersion, ProjectRecord.currentSchemaVersion)
        XCTAssertEqual(ProjectRecord(Project.initial).schemaVersion, 1)
    }

    /// Un fichero de la versión vigente se valida y pasa.
    func testTheCurrentVersionValidates() throws {
        let record = ProjectRecord(Project.initial)
        XCTAssertEqual(
            try record.validated().project(with: banks(of: Project.initial)),
            Project.initial
        )
    }

    /// **Una versión futura falla con un error propio, no con uno de
    /// decodificación.** Es la mitad que importa: la Fase 4 decide qué hacer con
    /// el fichero según de qué falle, y `DecodingError` no distingue «esto no es
    /// JSON válido» de «esto lo escribió una app más nueva».
    func testAFutureVersionFailsWithItsOwnError() {
        let future = ProjectRecord(Project(), schemaVersion: ProjectRecord.currentSchemaVersion + 1)

        XCTAssertThrowsError(try future.validated()) { error in
            XCTAssertEqual(
                error as? SchemaError,
                .unsupportedSchemaVersion(
                    found: ProjectRecord.currentSchemaVersion + 1,
                    supported: ProjectRecord.currentSchemaVersion
                )
            )
        }
    }

    /// Y una versión **anterior** también falla hoy, porque no hay migradores.
    ///
    /// **No es lo mismo que la futura y por eso se prueba aparte**: ésta es la
    /// que dejará de fallar en cuanto exista el primer migrador, y la de arriba
    /// no dejará de fallar nunca.
    func testAnOlderVersionAlsoFailsUntilThereIsAMigrator() {
        let old = ProjectRecord(Project(), schemaVersion: 0)
        XCTAssertThrowsError(try old.validated())
    }

    /// El punto de enchufe existe y hoy no hace nada: devuelve el record tal
    /// cual cuando la versión ya es la vigente.
    func testTheMigrationHookIsThereAndDoesNothingYet() throws {
        let record = ProjectRecord(Project.initial)
        XCTAssertEqual(try ProjectRecord.migrated(record), record)
    }

    /// El error dice qué se encontró y qué se soporta. Un mensaje que solo diga
    /// «versión no soportada» obliga a abrir el fichero a mano para saber cuál.
    func testTheErrorSaysWhatItFoundAndWhatItSupports() {
        let error = SchemaError.unsupportedSchemaVersion(found: 7, supported: 1)
        XCTAssertTrue(error.description.contains("7"))
        XCTAssertTrue(error.description.contains("1"))
    }

    /// Los dieciséis Banks de un Project, que es lo que la cabecera necesita
    /// para reconstruirlo: en disco viven en ficheros aparte (FR18).
    private func banks(of project: Project) -> [Bank] {
        (0..<Project.bankCount).compactMap { project.bank(at: $0) }
    }
}
