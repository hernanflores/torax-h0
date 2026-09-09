import Engine
import Foundation
import XCTest

@testable import Persistence

/// Test de que el camino de carga pasa por el migrador.
///
/// **Hallazgo del 2026-09-08, al planificar `midi-learn_20260908`.**
/// `ProjectRecord.migrated(_:)` documenta que «lo que hace falta ahora es que el
/// sitio esté decidido y que **la llamada esté puesta**». La llamada no estaba
/// puesta: `loadHeader` invocaba `validated()` directamente, y el único sitio
/// que llamaba a `migrated(_:)` era un test de `Engine`.
///
/// **Hoy las dos rutas hacen lo mismo** —`migrated(_:)` solo valida—, así que
/// esto no cambia ningún comportamiento. Deja de ser inofensivo el día que
/// alguien escriba la primera migración de verdad confiando en ese comentario:
/// el fichero pasaría por la ruta que no migra y se apartaría, que es la pérdida
/// de trabajo que este paquete existe para impedir.
///
/// Este test es lo único que puede notar la diferencia antes de ese día.
final class MigrationHookTests: XCTestCase {

    /// Un fichero de la versión vigente abre. Es el caso normal, y aquí está
    /// para que el de abajo no sea el único que toca este camino.
    func testAProjectOfTheCurrentVersionOpens() throws {
        let fileSystem = InMemoryFileSystem()
        let store = ProjectStore(fileSystem: fileSystem, directory: URL(fileURLWithPath: "/"))
        try store.save(Project().selectingBank(3))

        XCTAssertEqual(store.load().project.selectedBank, 3)
    }

    /// **La condición que fija el hallazgo**: lo que decide si un fichero abre
    /// es lo que diga `migrated(_:)`, no `validated()` por su cuenta. Con una
    /// versión que esta app no entiende, el fichero se aparta y la app abre
    /// vacía — que es el comportamiento de siempre, ahora por la ruta correcta.
    func testAnUnsupportedVersionIsSetAsideThroughTheMigrator() throws {
        let fileSystem = InMemoryFileSystem()
        let store = ProjectStore(fileSystem: fileSystem, directory: URL(fileURLWithPath: "/"))
        let future = try JSONEncoder().encode(
            ProjectRecord(Project().selectingBank(3), schemaVersion: 99))
        try fileSystem.write(future, to: URL(fileURLWithPath: "/project.json"))

        let loaded = store.load()

        XCTAssertEqual(loaded.project.selectedBank, 0)
        XCTAssertFalse(loaded.rescuedFiles.isEmpty)
    }
}
