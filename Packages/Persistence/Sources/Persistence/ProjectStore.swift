import Engine
import Foundation

/// Guarda y lee el árbol en disco.
///
/// **El reparto de ficheros es el de FR18**: un fichero por Bank más uno de
/// cabecera.
///
/// ```
/// <Application Support>/ToraxH0/
///   project.json          la cabecera: versión, índices y ajustes de sesión
///   banks/bank-01.json    los dieciséis Patterns de ese Bank y su tempo
///   ...
///   banks/bank-16.json
/// ```
///
/// **Por qué así y no un solo fichero.** El Autosave reescribe solo el Bank
/// tocado —~600 KB en vez de ~9 MB— y `Save Bank` puede copiar un fichero entero
/// en vez de recortar un árbol, que es exactamente el gránulo que la Pre Spec le
/// da al punto de retorno: «el punto de retorno intencional de *un* Bank».
///
/// **En Application Support y no en Documents** (FR20): el estado de trabajo no
/// es un documento que el usuario administre, es la memoria del instrumento.
/// Fuera de la vista no se borra ni se mueve por accidente.
///
/// **Es una clase y no un valor** porque lleva una cosa que cambia sola: si el
/// último guardado falló. FR21 pide que ese aviso **no se calle** hasta que uno
/// funcione, y eso es estado con dueño.
public final class ProjectStore: @unchecked Sendable {

    /// **`internal` y no `private` porque los puntos de retorno viven en una
    /// extensión** (`RestorePoint.swift`): son la otra capa de guardado y
    /// merecen su fichero, pero comparten el directorio, la costura y el codec.
    let fileSystem: FileSystem
    let directory: URL

    /// Cómo se nombra un fichero apartado. Inyectable para que los tests no
    /// dependan del reloj.
    private let timestamp: @Sendable () -> String

    /// Por qué falló el último guardado, o `nil` si el último funcionó.
    ///
    /// **Se limpia sola en cuanto un guardado funciona**, que es la otra mitad
    /// de FR21: un aviso que no se apaga cuando el problema se resuelve enseña a
    /// ignorarlo.
    public private(set) var lastSaveFailure: Error?

    /// **Indentado y con las claves ordenadas** (NFR7).
    ///
    /// Es la mitad de la razón por la que `tech-stack.md` eligió JSON:
    /// «inspeccionable, diffeable». Sin las claves ordenadas, dos guardados del
    /// mismo material producen ficheros distintos y el `diff` deja de servir
    /// para nada.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    let decoder = JSONDecoder()

    public init(
        fileSystem: FileSystem = DiskFileSystem(),
        directory: URL = ProjectStore.defaultDirectory,
        timestamp: @escaping @Sendable () -> String = ProjectStore.defaultTimestamp
    ) {
        self.fileSystem = fileSystem
        self.directory = directory
        self.timestamp = timestamp
    }

    /// `<Application Support>/ToraxH0`.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return (base.first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("ToraxH0", isDirectory: true)
    }

    /// La marca de tiempo de un fichero apartado: `20260907-134501`.
    ///
    /// **Con segundos**, para que apartar dos veces el mismo día no pise el
    /// primero.
    public static let defaultTimestamp: @Sendable () -> String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    var projectURL: URL { directory.appendingPathComponent("project.json") }

    /// `banks/bank-01.json`. **Numerado desde 1 y con cero delante**, como se
    /// enseña en pantalla: un fichero se busca a mano y `bank-1` junto a
    /// `bank-12` no ordena.
    func bankURL(at index: Int) -> URL {
        directory
            .appendingPathComponent("banks", isDirectory: true)
            .appendingPathComponent(String(format: "bank-%02d.json", index + 1))
    }

    // MARK: - Guardar

    /// Escribe un Bank. **Solo ése**: los otros quince no se tocan.
    public func save(_ bank: Bank, at index: Int) throws {
        try write(BankRecord(bank), to: bankURL(at: index))
    }

    /// Escribe la cabecera: versión, índices y ajustes de sesión.
    public func saveHeader(of project: Project) throws {
        try write(ProjectRecord(project), to: projectURL)
    }

    /// Escribe el Project entero: la cabecera y los dieciséis Banks.
    ///
    /// **Es para guardar por primera vez y para `Save Bank` de todo**, no para
    /// el Autosave: aquél escribe solo lo que cambió.
    public func save(_ project: Project) throws {
        try saveHeader(of: project)
        for index in 0..<Project.bankCount {
            guard let bank = project.bank(at: index) else { continue }
            try save(bank, at: index)
        }
    }

    /// **Un solo sitio por el que pasa toda escritura**, que es lo que permite
    /// que el estado de fallo sea correcto sin repetirlo en cada método.
    func write(_ record: some Encodable, to url: URL) throws {
        do {
            try fileSystem.createDirectory(url.deletingLastPathComponent())
            try fileSystem.write(try encoder.encode(record), to: url)
            lastSaveFailure = nil
        } catch {
            lastSaveFailure = error
            throw error
        }
    }

    // MARK: - Leer

    /// El Bank de ese fichero, o `nil` si no existe.
    ///
    /// **Lanza si existe y no se puede leer**, que es distinto: un Bank que no
    /// está nunca estuvo; uno ilegible tenía algo dentro, y quien llama decide
    /// si eso se aparta.
    public func loadBank(at index: Int) throws -> Bank? {
        guard let data = try fileSystem.read(bankURL(at: index)) else { return nil }
        return try decoder.decode(BankRecord.self, from: data).bank
    }

    /// Lee el Project entero, apartando lo que no se pueda leer.
    ///
    /// **Nunca lanza, y esa es la promesa** (FR22). Un fichero corrupto o de una
    /// versión desconocida no puede dejar la app sin abrir: se aparta con marca
    /// de tiempo —nunca se borra— y lo que se devuelve dice qué pasó, para que la
    /// pantalla pueda contarlo.
    public func load() -> LoadResult {
        var rescued: [String] = []

        let header = loadHeader(rescuing: &rescued)

        var banks: [Bank] = []
        for index in 0..<Project.bankCount {
            banks.append(loadBank(at: index, rescuing: &rescued) ?? Bank())
        }

        guard let header else {
            // Sin cabecera legible no hay dónde se estaba mirando, pero los
            // Banks que sí se leyeron **no se pierden**: se devuelven en un
            // Project por defecto.
            var project = Project()
            for (index, bank) in banks.enumerated() {
                project = project.replacing(bank, at: index)
            }
            return LoadResult(project: project, rescuedFiles: rescued, wasEmpty: rescued.isEmpty)
        }

        return LoadResult(
            project: header.project(with: banks),
            rescuedFiles: rescued,
            wasEmpty: false
        )
    }

    private func loadHeader(rescuing rescued: inout [String]) -> ProjectRecord? {
        do {
            guard let data = try fileSystem.read(projectURL) else { return nil }
            // **Por el migrador, no por `validated()` a secas.** Hoy hacen lo
            // mismo —`migrated(_:)` solo valida— pero su documentación promete
            // que «la llamada está puesta», y no lo estaba: quien escriba la
            // primera migración de verdad confiando en eso vería el fichero
            // apartarse por la ruta que no migra. Hallazgo del 2026-09-08, al
            // planificar `midi-learn_20260908`.
            return try ProjectRecord.migrated(decoder.decode(ProjectRecord.self, from: data))
        } catch {
            setAside(projectURL, into: &rescued)
            return nil
        }
    }

    private func loadBank(at index: Int, rescuing rescued: inout [String]) -> Bank? {
        do {
            return try loadBank(at: index)
        } catch {
            setAside(bankURL(at: index), into: &rescued)
            return nil
        }
    }

    /// Aparta un fichero ilegible: `project.json` → `project.20260907-134501.unreadable`.
    ///
    /// **Nunca se borra.** Es la única copia de lo que el usuario tenía, y aunque
    /// esta app no sepa leerlo, otra versión —o una persona con un editor—
    /// puede.
    private func setAside(_ url: URL, into rescued: inout [String]) {
        let name = url.deletingPathExtension().lastPathComponent
        let destination =
            url
            .deletingLastPathComponent()
            .appendingPathComponent("\(name).\(timestamp()).unreadable")

        // Si ni siquiera se puede mover, no hay nada más que hacer: lo que no
        // puede pasar es que la app no arranque.
        try? fileSystem.move(url, to: destination)
        rescued.append(destination.lastPathComponent)
    }
}

/// Lo que salió de leer el disco.
public struct LoadResult: Sendable {

    /// El Project con el que arrancar. **Siempre hay uno**: si no había nada, o
    /// si lo que había no se pudo leer, es uno vacío.
    public let project: Project

    /// Los ficheros que se apartaron por ilegibles, por su nombre nuevo.
    /// **Vacío es el caso normal.**
    public let rescuedFiles: [String]

    /// Si no había nada que leer — la primera vez que se abre la app.
    public let wasEmpty: Bool

    /// Si hay algo que contarle al usuario.
    public var needsAttention: Bool { !rescuedFiles.isEmpty }
}
