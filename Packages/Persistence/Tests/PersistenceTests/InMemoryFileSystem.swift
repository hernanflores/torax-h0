import Foundation

@testable import Persistence

/// Un sistema de ficheros en memoria, para los tests.
///
/// **Es lo que hace probables los tres casos que importan** y que contra un
/// disco real se provocan con ceremonia o no se provocan: disco lleno, escritura
/// que falla a mitad, y fichero corrupto. Aquí son tres líneas.
///
/// **No es un doble tonto: registra lo que se le pide.** Cuántas escrituras hubo
/// y sobre qué fichero es exactamente lo que el debounce del Autosave necesita
/// afirmar —«N cambios seguidos producen *una* escritura»— y lo que permite
/// comprobar que guardar el Bank 3 no toca los otros quince.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {

    /// Los ficheros, por ruta.
    private(set) var files: [String: Data] = [:]

    /// Los directorios creados.
    private(set) var directories: Set<String> = []

    /// Cada escritura, en orden. La cuenta es la afirmación del debounce.
    private(set) var writes: [String] = []

    /// El siguiente `write` falla con esto, y luego se limpia.
    ///
    /// **Falla *antes* de tocar nada**, que es lo que modela una escritura
    /// atómica interrumpida: el fichero anterior tiene que seguir intacto.
    var failNextWrite: Error?

    /// Todas las escrituras fallan mientras esto sea distinto de `nil`. Modela
    /// un disco lleno, que no se arregla solo.
    var failEveryWrite: Error?

    init() {}

    func read(_ url: URL) throws -> Data? {
        files[url.path]
    }

    func write(_ data: Data, to url: URL) throws {
        if let error = failEveryWrite { throw error }
        if let error = failNextWrite {
            failNextWrite = nil
            throw error
        }
        files[url.path] = data
        writes.append(url.path)
    }

    func move(_ source: URL, to destination: URL) throws {
        guard let data = files[source.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        files[destination.path] = data
        files[source.path] = nil
    }

    func createDirectory(_ url: URL) throws {
        directories.insert(url.path)
    }

    // MARK: - Ayudas de test

    /// Cuántas veces se escribió esa ruta.
    func writeCount(for url: URL) -> Int {
        writes.filter { $0 == url.path }.count
    }

    /// Deja un fichero con contenido arbitrario, para los casos de corrupción.
    func plant(_ contents: String, at url: URL) {
        files[url.path] = Data(contents.utf8)
    }

    var fileCount: Int { files.count }
}
