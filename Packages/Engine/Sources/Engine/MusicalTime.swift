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

    public static let quarter = Division(unchecked: 1, denominator: 4)
    public static let eighth = Division(unchecked: 1, denominator: 8)
    public static let sixteenth = Division(unchecked: 1, denominator: 16)

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
