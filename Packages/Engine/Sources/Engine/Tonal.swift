/// Una altura MIDI.
///
/// **Existe en `Engine` y no se toma prestada de `MIDI`** porque el motor no
/// importa nada de plataforma: es el compilador quien garantiza esa pureza
/// (`tech-stack.md`), y tomar el tipo del otro lado la rompería. La conversión
/// vive en la capa MIDI, que es la que conoce ambos.
public struct Pitch: Equatable, Sendable, Comparable {

    public static let validRange: ClosedRange<Int> = 0...127

    public let value: Int

    /// Devuelve `nil` fuera del rango MIDI.
    public init?(_ value: Int) {
        guard Self.validRange.contains(value) else { return nil }
        self.value = value
    }

    /// Vía interna para valores ya acotados por construcción.
    init(unchecked value: Int) {
        self.value = value
    }

    /// Dónde cae dentro de la octava, ignorando en cuál está.
    public var pitchClass: Int { value % 12 }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.value < rhs.value }
}

/// El centro tonal: la fundamental que transpone la Scale.
///
/// Es una clase de altura, no una altura concreta: Do es Do en todas las
/// octavas. La Pre Spec lo define así —«**Root:** fundamental que transpone la
/// Scale»— y de ahí sale que el marco tonal se repita octava a octava.
public struct Root: Equatable, Sendable {

    public static let validRange: Range<Int> = 0..<12

    public let pitchClass: Int

    /// Devuelve `nil` fuera de la octava.
    public init?(_ pitchClass: Int) {
        guard Self.validRange.contains(pitchClass) else { return nil }
        self.pitchClass = pitchClass
    }

    /// Do, que es el Root con el que arranca todo.
    ///
    /// Existe como constante pública porque un argumento por defecto no puede
    /// usar una vía interna, igual que `Channel.first`.
    public static let c = Root(0)!
}

extension Pitch: CustomStringConvertible {

    /// Nombre de la altura, con octava.
    ///
    /// **Con octava porque un pool son alturas concretas, no clases.** Do3 y Do4
    /// son dos entradas distintas, y sin la octava se verían iguales en
    /// pantalla.
    ///
    /// Convención científica: Do central —MIDI 60— es C4, así que la octava del
    /// extremo grave es −1.
    public var description: String {
        "\(Root(pitchClass)!.description)\(value / 12 - 1)"
    }
}

extension Root: CustomStringConvertible {

    /// Sostenidos y no bemoles, elegido por consistencia: un solo nombre por
    /// clase de altura, sin que dependa de la escala en curso.
    public var description: String {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][pitchClass]
    }
}

/// El conjunto de notas permitido, antes de elegir centro tonal.
///
/// **Solo presets en v1.** La Pre Spec admite escalas de usuario —«la escala
/// puede ser preset o de usuario»— y quedan fuera de esta rebanada.
///
/// Los intervalos no están en la Pre Spec, que nombra las escalas pero no las
/// escribe. Los de aquí son el registro canónico del proyecto y viven en
/// `TonalFrameTests`.
public enum Scale: Equatable, Sendable, CaseIterable {
    case minor
    case major
    case dorian
    case phrygian
    case pentatonic

    /// Orden en que se recorren, y en que se muestran.
    ///
    /// Sigue el orden de la rejilla del handoff de diseño, para que el knob y la
    /// pantalla no discrepen.
    public static let ordered: [Scale] = [.minor, .major, .dorian, .phrygian, .pentatonic]

    /// Un bit por clase de altura: el bit *i* está a uno si el semitono *i* por
    /// encima de la fundamental pertenece a la escala.
    ///
    /// **Máscara y no array por la misma razón que en `EuclideanRhythm`:**
    /// consultarla es un desplazamiento y una comparación, sin nada que recorrer
    /// ni que asignar. Doce bits caben de sobra en un `UInt16`.
    ///
    /// > **Nota del 2026-08-28 — qué pentatónica.** La Pre Spec nombra la
    /// > escala pero no dice cuál, y la lista ya trae Major y Minor completas.
    /// > Se elige la **pentatónica menor** (0-3-5-7-10), que es la menor sin sus
    /// > dos semitonos: da un pool sin choques y es la que hace de esta lista un
    /// > gradiente de tensión decreciente. Si se quisiera la mayor, es añadir un
    /// > caso, no cambiar nada más.
    var pitchClassMask: UInt16 {
        switch self {
        case .minor: 0b0101_1010_1101  // 0 2 3 5 7 8 10
        case .major: 0b1010_1011_0101  // 0 2 4 5 7 9 11
        case .dorian: 0b0110_1010_1101  // 0 2 3 5 7 9 10
        case .phrygian: 0b0101_1010_1011  // 0 1 3 5 7 8 10
        case .pentatonic: 0b0100_1010_1001  // 0 3 5 7 10
        }
    }

    /// Los grados de la escala, en semitonos sobre la fundamental y en orden
    /// ascendente: `major` da `[0, 2, 4, 5, 7, 9, 11]` y `pentatonic` da
    /// `[0, 3, 5, 7, 10]`.
    ///
    /// **Es la máscara vista al revés.** `allows(_:)` responde si una altura
    /// pertenece; esto responde cuál es la enésima. La superficie de pads
    /// necesita lo segundo —el pad 3 es el tercer grado— y `pitchClassMask` ya
    /// tiene el dato, así que se deriva de ella en vez de escribir los
    /// intervalos en un segundo sitio donde puedan divergir.
    ///
    /// El grado 1 es siempre el 0: el Root, por definición. La longitud es el
    /// número de notas de la escala —siete en las heptatónicas, cinco en la
    /// pentatónica—, y de ahí sale que con `pentatonic` sobren pads.
    public var degrees: [Int] {
        let mask = pitchClassMask
        return (0..<12).filter { (mask >> UInt16($0)) & 1 == 1 }
    }

    /// Escala siguiente o anterior en la lista, **deteniéndose en los
    /// extremos**.
    ///
    /// Misma regla que `Division`: un knob que dé la vuelta sorprende, porque no
    /// hay forma de saber que se llegó al final sin pasarse.
    public func advanced(by delta: Int) -> Scale {
        guard let index = Self.ordered.firstIndex(of: self) else { return self }
        let target = min(max(index + delta, 0), Self.ordered.count - 1)
        return Self.ordered[target]
    }
}

/// Scale y Root juntos: el conjunto concreto de alturas que un Track puede usar.
///
/// **El nombre no está en la Pre Spec** —que habla de Scale y de Root por
/// separado— pero el concepto sí: «Scale + Root restringen la salida a una
/// escala y centro tonal». Tenerlo como un valor evita pasar los dos por todas
/// partes y que alguien los combine mal.
public struct TonalFrame: Equatable, Sendable {

    public let scale: Scale
    public let root: Root

    /// Máscara de doce bits ya transpuesta al Root.
    private let mask: UInt16

    public init(scale: Scale, root: Root) {
        self.scale = scale
        self.root = root

        // Rotación circular sobre doce bits, no sobre los dieciséis del tipo:
        // los cuatro de arriba no forman parte de la octava.
        let base = scale.pitchClassMask
        let shift = UInt16(root.pitchClass)
        let octave: UInt16 = 0b1111_1111_1111
        mask = shift == 0 ? base : ((base << shift) | (base >> (12 - shift))) & octave
    }

    /// Si la altura pertenece al marco.
    ///
    /// Depende solo de la clase de altura: si Do está en la escala, lo está en
    /// todas las octavas.
    ///
    /// Realtime: consultable desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func allows(_ pitch: Pitch) -> Bool {
        (mask >> UInt16(pitch.pitchClass)) & 1 == 1
    }

    /// La altura permitida más cercana a la dada.
    ///
    /// **El desempate baja.** Con dos permitidas a la misma distancia se elige
    /// la grave: bajar conserva el registro, y subir puede empujar una nota
    /// fuera del rango MIDI por arriba. Es una decisión escrita, no un efecto
    /// del orden en que se recorre.
    ///
    /// Toda escala tiene al menos cinco notas por octava, así que la búsqueda
    /// termina en pocos semitonos y no hace falta acotarla más.
    public func nearest(to pitch: Pitch) -> Pitch {
        guard !allows(pitch) else { return pitch }

        for distance in 1...12 {
            let below = pitch.value - distance
            if Pitch.validRange.contains(below), allows(Pitch(unchecked: below)) {
                return Pitch(unchecked: below)
            }
            let above = pitch.value + distance
            if Pitch.validRange.contains(above), allows(Pitch(unchecked: above)) {
                return Pitch(unchecked: above)
            }
        }
        return pitch
    }
}
