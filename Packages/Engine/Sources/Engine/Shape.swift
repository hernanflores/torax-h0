/// Número de Steps del anillo.
///
/// La Pre Spec describe un rango 1–64, pero v1 se acota a **1–16**: es lo que
/// cabe en el anillo con legibilidad a un metro, que es el criterio de
/// `product-guidelines.md`. El rango largo llega cuando exista una
/// representación que lo aguante.
///
/// Valida en el inicializador, como `Tempo` y `Division`: un `Steps` que existe
/// es siempre válido, y ningún sitio de uso vuelve a comprobarlo.
public struct Steps: Equatable, Sendable {

    /// Rango admitido en v1.
    public static let validRange: ClosedRange<Int> = 1...16

    public let count: Int

    /// Devuelve `nil` si el número de Steps cae fuera de `validRange`.
    public init?(_ count: Int) {
        guard Self.validRange.contains(count) else { return nil }
        self.count = count
    }
}

/// Número de Pulses repartidos sobre el anillo.
///
/// Su límite superior no es una constante: es el `Steps` en el que vive. Por eso
/// el inicializador exige el anillo, en lugar de aceptar un entero suelto que
/// alguien tendría que validar más tarde contra el Track.
public struct Pulses: Equatable, Sendable {

    public let count: Int

    /// Devuelve `nil` si el número de Pulses cae fuera de `1...steps.count`.
    public init?(_ count: Int, in steps: Steps) {
        guard (1...steps.count).contains(count) else { return nil }
        self.count = count
    }
}

/// Desplazamiento del patrón sobre el anillo.
///
/// **No se valida contra un rango a propósito.** Rotate es un giro sobre un
/// anillo cerrado: un valor negativo gira en sentido contrario y un valor mayor
/// que Steps da la vuelta. Ambos son musicalmente significativos, así que
/// rechazarlos obligaría a quien llama a normalizar antes — justo el reparto de
/// responsabilidad que el tipo existe para evitar. La envoltura la resuelve el
/// reparto, que es quien conoce el tamaño del anillo.
public struct Rotate: Equatable, Sendable {

    public let amount: Int

    public init(_ amount: Int) {
        self.amount = amount
    }

    /// Patrón sin girar. Es el valor por defecto del producto.
    public static let none = Rotate(0)
}
