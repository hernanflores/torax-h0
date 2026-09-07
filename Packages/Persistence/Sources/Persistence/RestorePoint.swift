import Engine
import Foundation

/// `Save Bank` y `Reload`: el punto de retorno intencional.
///
/// **Son dos capas distintas y esa es toda la idea** (FR16). El Autosave protege
/// el trabajo en curso sin que nadie lo pida; `Save Bank` es una decisión —«hasta
/// aquí me vale»— y `Reload` es volver a ella. La Pre Spec lo pone por su nombre:
/// «crea el punto de retorno intencional de *un* Bank; `Reload` descarta cambios
/// no guardados y vuelve a ese punto».
///
/// **Del Bank vigente y solo de ése**, que es el gránulo que la Pre Spec le da y
/// lo que permite que sea un botón sin selector que equivocar.
///
/// **En disco es una copia del fichero**, en `restore/bank-NN.json`. No hay
/// formato nuevo ni versión aparte: un punto de retorno es un Bank, y guardarlo
/// es escribirlo en otro sitio.
extension ProjectStore {

    /// `restore/bank-01.json`.
    func restoreURL(at index: Int) -> URL {
        directory
            .appendingPathComponent("restore", isDirectory: true)
            .appendingPathComponent(String(format: "bank-%02d.json", index + 1))
    }

    /// Fija el punto de retorno de ese Bank. **Sustituye el anterior**: hay uno
    /// por Bank, no una pila.
    public func saveRestorePoint(_ bank: Bank, at index: Int) throws {
        try write(BankRecord(bank), to: restoreURL(at: index))
    }

    /// Si ese Bank tiene un punto al que volver.
    public func hasRestorePoint(at index: Int) -> Bool {
        ((try? fileSystem.read(restoreURL(at: index))) ?? nil) != nil
    }

    /// El Bank guardado como punto de retorno.
    ///
    /// **Devuelve `nil` si no hay punto**, que no es un error: es el estado de un
    /// Bank en el que nunca se pulsó `Save Bank`.
    public func restorePoint(at index: Int) throws -> Bank? {
        guard let data = try fileSystem.read(restoreURL(at: index)) else { return nil }
        return try decoder.decode(BankRecord.self, from: data).bank
    }

    /// Si `Reload` se puede pulsar, y por qué no cuando no.
    ///
    /// **Sin punto de retorno el botón no está disponible y lo dice** (FR17).
    /// Volver a vacío no es volver, es borrar, y un botón que destruye trabajo
    /// no debe parecerse a uno que lo restaura.
    public func reloadAvailability(at index: Int) -> ReloadAvailability {
        hasRestorePoint(at: index)
            ? .available
            : .unavailable(reason: "Este Bank no se ha guardado todavía")
    }
}

/// Si `Reload` se puede usar.
public enum ReloadAvailability: Equatable, Sendable {

    case available

    /// **Lleva el motivo dentro** porque un botón deshabilitado sin explicación
    /// se lee como un fallo de la app. Aquí no lo es: es información sobre cómo
    /// funciona el guardado.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var reason: String? {
        switch self {
        case .available: nil
        case .unavailable(let reason): reason
        }
    }
}
