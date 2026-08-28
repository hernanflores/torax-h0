/// Cómo codifica un controlador el giro de un encoder relativo.
///
/// **Los encoders del producto operan en modo relativo** (`product-guidelines.md`):
/// incrementan o decrementan desde el valor actual del software, sin saltos y
/// sin zona muerta de pickup. El byte que llega en el mensaje no es una
/// posición absoluta: es un desplazamiento con signo, y cada fabricante lo
/// codifica a su manera.
///
/// **Por qué es un tipo y no una función suelta.** Hoy solo hace falta una
/// convención, pero el preset del BeatStep Pro traerá las suyas. Que la
/// convención entre como valor significa que añadirlas será añadir casos, no
/// reescribir el decodificador ni a sus llamantes. Sus valores exactos se
/// verificarán contra el manual del fabricante cuando llegue ese track.
public enum RelativeEncoding: Equatable, Sendable, CaseIterable {

    /// Complemento a dos de 7 bits: `0x01`…`0x3F` son +1…+63 y `0x7F`…`0x41`
    /// son −1…−63. Es la convención más extendida.
    case twosComplement

    /// Traduce el byte de un mensaje de control a un desplazamiento con signo.
    ///
    /// Devuelve `0` para todo lo que no represente un giro: el cero, el centro
    /// ambiguo y cualquier valor fuera del rango de datos MIDI.
    ///
    /// No es código de tiempo real: corre en el hilo de control, no en el del
    /// scheduler.
    public func delta(from value: UInt8) -> Int {
        // Un byte de datos MIDI nunca supera 127. Si llega uno, no se inventa
        // un giro.
        guard value <= 0x7F else { return 0 }

        switch self {
        case .twosComplement:
            // `0x40` es el centro ambiguo. En complemento a dos estricto valdría
            // −64, pero muchos controladores lo emiten en reposo: interpretarlo
            // como el mayor decremento posible convertiría un knob quieto en un
            // salto brutal.
            guard value != 0x00, value != 0x40 else { return 0 }

            return value < 0x40 ? Int(value) : Int(value) - 128
        }
    }
}
