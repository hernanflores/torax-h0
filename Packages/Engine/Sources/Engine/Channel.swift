/// El canal MIDI por el que emite un Track.
///
/// **Existe en `Engine` y no se toma prestado de `MIDI`** por la misma razón que
/// `Pitch`: el motor no importa nada de plataforma —es el compilador quien
/// garantiza esa pureza, según `tech-stack.md`— y tomar el tipo del otro lado la
/// rompería. La conversión vive en la capa MIDI, que es la que conoce ambos.
///
/// Que haya dos tipos con el mismo rango no es duplicación por descuido: es la
/// frontera del paquete, y ya se pagó una vez con `Pitch`.
public struct Channel: Equatable, Sendable {

    /// Los dieciséis canales del protocolo, numerados como los numera el
    /// hardware: de 1 a 16, no de 0 a 15.
    public static let validRange: ClosedRange<Int> = 1...16

    public let number: Int

    /// Devuelve `nil` fuera de los dieciséis canales.
    public init?(_ number: Int) {
        guard Self.validRange.contains(number) else { return nil }
        self.number = number
    }

    /// Vía interna para valores ya acotados por construcción.
    init(unchecked number: Int) {
        self.number = number
    }

    /// El canal 1, que es por donde emitía la app cuando había un Track solo.
    ///
    /// Es el valor por defecto de `Track`, y existe como constante pública
    /// porque un argumento por defecto no puede usar la vía interna.
    public static let first = Channel(unchecked: 1)
}
