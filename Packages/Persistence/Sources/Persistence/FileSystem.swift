import Foundation

/// Lo que este paquete necesita de un sistema de ficheros, y nada más.
///
/// **Es una costura y entra desde el primer commit**, no un refactor posterior.
/// La razón no es purismo: los casos que hay que probar aquí son **disco lleno,
/// fichero corrupto y escritura interrumpida**, y contra un disco real esos tres
/// se provocan con ceremonia —o no se provocan— y dejan basura entre pasadas.
/// Con la costura son tres líneas de test.
///
/// **Cuatro operaciones.** Si algún día hacen falta más, es señal de que el
/// almacén está haciendo algo que no es guardar.
public protocol FileSystem: Sendable {

    /// Los bytes de ese fichero, o `nil` si no existe.
    ///
    /// **No existir no es un error**: es el estado de la primera vez que se abre
    /// la app, y tratarlo como fallo obligaría a distinguirlo en cada sitio de
    /// uso.
    func read(_ url: URL) throws -> Data?

    /// Escribe los bytes **de forma atómica**: a un temporal y renombrando.
    ///
    /// Quien implemente esto tiene que garantizar que un fallo a mitad deja el
    /// fichero anterior intacto. Es la promesa de la que depende que un Autosave
    /// interrumpido no destruya el guardado anterior.
    func write(_ data: Data, to url: URL) throws

    /// Renombra un fichero. Se usa para apartar los ilegibles sin borrarlos.
    func move(_ source: URL, to destination: URL) throws

    /// Crea el directorio y los intermedios que falten. No es error que exista.
    func createDirectory(_ url: URL) throws
}

/// El sistema de ficheros de verdad.
public struct DiskFileSystem: FileSystem {

    /// **No guarda un `FileManager`**, y no es un descuido: `FileManager` no es
    /// `Sendable`, y este tipo cruza al hilo donde se escribe. Se usa
    /// `FileManager.default` en cada llamada, que es seguro para estas
    /// operaciones. La costura que hace testeable el paquete es el protocolo de
    /// arriba, no inyectar un gestor de ficheros.
    private var manager: FileManager { .default }

    public init() {}

    public func read(_ url: URL) throws -> Data? {
        guard manager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// **La atomicidad la da `.atomic`**, que escribe a un temporal y renombra.
    /// No se escribe a mano el temporal: el renombrado dentro del mismo volumen
    /// es lo que hace la operación indivisible, y Foundation ya lo hace bien.
    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func move(_ source: URL, to destination: URL) throws {
        try manager.moveItem(at: source, to: destination)
    }

    public func createDirectory(_ url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
