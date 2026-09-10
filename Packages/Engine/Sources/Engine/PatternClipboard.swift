/// Un Pattern copiado, esperando a que lo peguen.
///
/// **Guarda el material entero y no un índice** (FR1). Es lo que permite pegar
/// en otro Bank: allí el hueco 3 contiene otra cosa, así que un número de hueco
/// no nombraría nada. El material viaja como valor y el Banco de origen no
/// interviene en el pegado.
///
/// **Recuerda de dónde salió solo para dibujar la marca** (FR2, FR12). No
/// participa en el pegado, que siempre escribe en el Bank vigente.
///
/// **Vive mientras viva la app** (FR3). No se persiste: no toca `Persistence`,
/// ni el formato de disco, ni `schemaVersion`. Se pierde al cerrar, y eso es lo
/// que un portapapeles hace.
public struct PatternClipboard: Equatable, Sendable {

    /// El material copiado.
    public let pattern: Pattern

    /// El Bank del que salió, solo para la marca.
    public let bankIndex: Int

    /// El hueco del que salió, solo para la marca.
    public let slotIndex: Int

    public init(pattern: Pattern, bankIndex: Int, slotIndex: Int) {
        self.pattern = pattern
        self.bankIndex = bankIndex
        self.slotIndex = slotIndex
    }

    /// Qué hueco lleva la marca de origen mirando ese Bank, o `nil` si no es el
    /// suyo.
    ///
    /// **Solo se dibuja en su Banco** (FR12): mirando otro no hay celda que
    /// marcar, y la señal de que hay algo cargado es que `paste` está
    /// habilitado.
    public func markedSlot(inBank index: Int) -> Int? {
        index == bankIndex ? slotIndex : nil
    }

    /// En qué hueco cae un pegado.
    ///
    /// **Parado, el seleccionado; corriendo, el armado si lo hay y si no el que
    /// suena** (FR8). Sonando, tocar un hueco no mueve la selección —solo arma,
    /// y la selección se mueve cuando el material entra en el compás—, así que
    /// el armado es la única forma de apuntar a un hueco distinto del que suena.
    ///
    /// Es estática porque decide con lo que se le da y no con lo que guarda: el
    /// destino no depende del material copiado.
    public static func destination(selected: Int, armed: Int?, isRunning: Bool) -> Int {
        guard isRunning, let armed else { return selected }
        return armed
    }
}
