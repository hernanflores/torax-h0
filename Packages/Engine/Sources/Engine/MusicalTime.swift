/// Tempo en pulsos por minuto.
///
/// El rango se valida en el tipo, no en cada sitio de uso
/// (`conductor/code_styleguides/swift.md`): un `Tempo` que existe es siempre
/// musicalmente válido.
public struct Tempo: Equatable, Sendable {

    /// Rango admitido. Fuera de él no hay uso musical razonable y sí riesgo de
    /// desbordar los cálculos de la ventana de scheduling.
    public static let validRange: ClosedRange<Double> = 20...300

    public let beatsPerMinute: Double

    /// Devuelve `nil` si el tempo cae fuera de `validRange`.
    public init?(beatsPerMinute: Double) {
        guard Self.validRange.contains(beatsPerMinute) else { return nil }
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Valor rítmico de cada Step, expresado como fracción de redonda.
///
/// Término de la Pre Spec: Division cambia la velocidad de la línea sin
/// cambiar su estructura. Default del producto: 1/16.
public struct Division: Equatable, Sendable {

    public let numerator: Int
    public let denominator: Int

    /// Devuelve `nil` si numerador o denominador no son positivos.
    ///
    /// Valida como `Tempo`: un `Division` que existe es siempre musicalmente
    /// válido, y ningún sitio de uso tiene que volver a comprobarlo.
    public init?(numerator: Int, denominator: Int) {
        guard numerator > 0, denominator > 0 else { return nil }
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Vía interna para las constantes de abajo, cuyos valores son literales
    /// conocidos. Evita tener que forzar el desempaquetado del inicializador
    /// validador, que `code_styleguides/swift.md` prohíbe fuera de tests.
    private init(unchecked numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let whole = Division(unchecked: 1, denominator: 1)
    public static let half = Division(unchecked: 1, denominator: 2)
    public static let quarter = Division(unchecked: 1, denominator: 4)
    public static let eighth = Division(unchecked: 1, denominator: 8)
    public static let sixteenth = Division(unchecked: 1, denominator: 16)

    /// Los valores por los que recorre el knob, **de más lenta a más rápida**.
    ///
    /// Cada uno dura la mitad que el anterior: girar se percibe como duplicar o
    /// dividir la velocidad de la línea, que es lo que la Pre Spec describe —
    /// «cambia la velocidad sin cambiar la estructura».
    ///
    /// **Por qué se corta en 1/16 y no sigue a 1/32.** El note-off de cada pulso
    /// se sella un gate provisional por delante del note-on, y ese gate tiene
    /// que caber dentro del Step más corto que el producto pueda producir. A 300
    /// BPM —el tempo máximo— un Step de 1/32 dura exactamente 25 ms, que es el
    /// gate: las notas empezarían a solaparse. Los valores más rápidos entran
    /// cuando Sustain sustituya al gate, en Groove.
    ///
    /// El tipo sigue admitiendo cualquier fracción positiva; esta lista es solo
    /// por dónde pasa el knob.
    public static let ordered: [Division] = [whole, half, quarter, eighth, sixteenth]

    /// Extremos de la lista. Opcionales porque `ordered` es un array.
    public static var slowest: Division? { ordered.first }
    public static var fastest: Division? { ordered.last }

    /// Devuelve la Division que está `delta` posiciones más adelante en la
    /// lista; hacia delante es más rápida.
    ///
    /// **Se detiene en los extremos, no envuelve.** Un knob que saltara de 1/16
    /// a 1/1 al pasarse convertiría un ajuste fino en un cambio brutal de
    /// velocidad — y `product-guidelines.md` pide que girar produzca «siempre un
    /// cambio inmediato y proporcional».
    ///
    /// Una Division que no esté en la lista se devuelve intacta: el recorrido no
    /// puede inventar un punto de partida que no existe.
    public func advanced(by delta: Int) -> Division {
        guard let index = Self.ordered.firstIndex(of: self) else { return self }
        let target = min(max(index + delta, 0), Self.ordered.count - 1)
        return Self.ordered[target]
    }

    /// Fracción de redonda que ocupa un Step con esta Division.
    var fractionOfWholeNote: Double {
        Double(numerator) / Double(denominator)
    }
}

/// Traduce índices de Step a offsets temporales en nanosegundos.
///
/// **Sin deriva por construcción.** El offset de un Step se calcula
/// multiplicando su índice por la duración de Step, nunca acumulando
/// (`t += paso`).
///
/// La diferencia no es de magnitud sino de forma: el error de la acumulación
/// crece linealmente y sin límite, mientras que el de la multiplicación queda
/// acotado a un único redondeo por muchos Steps que pasen. Medido a 174 BPM
/// sobre 1000 Steps, la acumulación deriva 448 ns y la multiplicación 0.48 ns.
///
/// A esa escala la acumulación todavía no es audible —unos 19 µs por hora—,
/// así que la razón para descartarla no es que suene mal hoy, sino que su error
/// no tiene techo y no hay nada que ganar a cambio.
///
/// Los offsets son relativos a un origen que fija quien programa; este tipo no
/// conoce el tiempo de host ni la plataforma, y por eso vive en `Engine`.
public struct MusicalTimeline: Equatable, Sendable {

    public let tempo: Tempo
    public let division: Division

    public init(tempo: Tempo, division: Division) {
        self.tempo = tempo
        self.division = division
    }

    /// Duración de un Step en nanosegundos.
    ///
    /// Una redonda dura cuatro pulsos; un Step dura la fracción de redonda que
    /// indique la Division.
    public var stepDurationNanoseconds: Double {
        let nanosecondsPerBeat = 60.0 / tempo.beatsPerMinute * 1_000_000_000.0
        return nanosecondsPerBeat * 4.0 * division.fractionOfWholeNote
    }

    /// Offset del Step indicado respecto al origen de la línea de tiempo.
    ///
    /// Admite índices negativos: los usará Delay, que desplaza un Track entero
    /// hacia atrás respecto a la rejilla.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func nanosecondOffset(forStep step: Int) -> Int64 {
        Int64((stepDurationNanoseconds * Double(step)).rounded())
    }
}

extension Division: CustomStringConvertible {

    /// Se lee como la fracción que es: `1/16`.
    ///
    /// `product-guidelines.md` pide precisión, no conversación: el valor y nada
    /// más.
    public var description: String { "\(numerator)/\(denominator)" }
}
