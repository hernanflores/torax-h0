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

    /// El tempo como se enseña: un decimal.
    ///
    /// **Existe por el reloj externo.** Un tempo estimado se mueve en las
    /// milésimas de una negra a otra, y un último decimal que baila es ilegible
    /// a un metro — que es el requisito de lectura de `product-guidelines.md`, no
    /// una preferencia. Lo que se redondea es lo que se enseña; lo que suena
    /// sigue usando el valor entero.
    public var displayBeatsPerMinute: Double { (beatsPerMinute * 10).rounded() / 10 }

    /// El tempo tal y como se escribe en la interfaz: `124 bpm`.
    ///
    /// **Vivía en la vista y bajó aquí el 2026-09-06**, en la auditoría de la
    /// Fase 1 de `screens-redesign_20260906`. Era un `String(format:locale:)`
    /// repetido en dos sitios de `AppChrome`, y lo único que impedía que un iPad
    /// en español escribiera `120,0 BPM` era un comentario encima. Un comentario
    /// no es una defensa; un test sí.
    ///
    /// **Redondea a entero, y por eso el separador decimal no aparece nunca.**
    /// Es la misma razón que `displayBeatsPerMinute` documenta un escalón más
    /// arriba: un último decimal que baila con el reloj externo es ilegible a un
    /// metro. Al enseñarlo entero, la trampa del locale deja de poder ocurrir en
    /// vez de quedar esquivada.
    ///
    /// La unidad va en minúsculas porque **todo texto visible lo va**
    /// (`product-guidelines.md`, enmienda del 2026-09-06). Es el único sitio de
    /// `Engine` donde eso importa, y no lo contradice: no es un término de la
    /// Pre Spec, es una unidad.
    public var displayDescription: String {
        "\(Int(displayBeatsPerMinute.rounded())) bpm"
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
    /// **Internal y no private desde el 2026-09-07**: `RepeatTime` construye su
    /// propia lista de fracciones —tresillos incluidos— y necesita la misma vía,
    /// por la misma razón. Ampliar `Division.ordered` para dársela cambiaría por
    /// dónde pasa el knob de Division, que es otro parámetro.
    init(unchecked numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let whole = Division(unchecked: 1, denominator: 1)
    public static let half = Division(unchecked: 1, denominator: 2)
    public static let quarter = Division(unchecked: 1, denominator: 4)
    public static let eighth = Division(unchecked: 1, denominator: 8)
    public static let sixteenth = Division(unchecked: 1, denominator: 16)
    public static let thirtySecond = Division(unchecked: 1, denominator: 32)

    /// Los valores por los que recorre el knob, **de más lenta a más rápida**.
    ///
    /// Cada uno dura la mitad que el anterior: girar se percibe como duplicar o
    /// dividir la velocidad de la línea, que es lo que la Pre Spec describe —
    /// «cambia la velocidad sin cambiar la estructura».
    ///
    /// **Llega hasta 1/32 desde la rebanada 5, y antes no.** La lista se cortaba
    /// en 1/16 porque el note-off se sellaba un gate constante de 25 ms por
    /// delante del note-on, y a 300 BPM —el tempo máximo— un Step de 1/32 dura
    /// exactamente esos 25 ms: las notas se habrían solapado sin que nadie lo
    /// pidiera. Aquella nota dejaba escrita la condición para extenderla —«los
    /// valores más rápidos entran cuando Sustain sustituya al gate, en
    /// Groove»— y Sustain la cumple.
    ///
    /// Ahora el gate es un porcentaje del Step, así que el caso extremo se
    /// comporta: con Sustain 100% el note-off cae justo donde empieza el
    /// siguiente note-on, y el solape empieza por encima del 100%, que es donde
    /// el usuario lo pide. Hay un test que lo fija.
    ///
    /// El tipo sigue admitiendo cualquier fracción positiva; esta lista es solo
    /// por dónde pasa el knob.
    public static let ordered: [Division] = [
        whole, half, quarter, eighth, sixteenth, thirtySecond,
    ]

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

    /// El Step desde el que se mide, y el instante que ese Step ocupa.
    ///
    /// **Existen porque la Division se gira mientras suena.** Sin ancla, cambiar
    /// la Division de una rejilla recalcularía también todo el pasado: el Step
    /// siguiente saltaría a un instante que no tiene nada que ver con el que se
    /// estaba tocando, y la línea daría un tumbo en vez de cambiar de velocidad.
    /// Con ancla, **el pasado queda como sonó y el futuro obedece al knob**.
    ///
    /// En reposo valen cero los dos, que es la rejilla de siempre: medida desde
    /// el origen de Play. Un Track que no ha cambiado de Division no sabe que
    /// esto existe.
    public let anchorStep: Int
    public let anchorNanoseconds: Int64

    public init(tempo: Tempo, division: Division) {
        self.init(tempo: tempo, division: division, anchorStep: 0, anchorNanoseconds: 0)
    }

    private init(tempo: Tempo, division: Division, anchorStep: Int, anchorNanoseconds: Int64) {
        self.tempo = tempo
        self.division = division
        self.anchorStep = anchorStep
        self.anchorNanoseconds = anchorNanoseconds
    }

    /// La misma rejilla con otra Division, **midiendo desde el instante que ese
    /// Step ya ocupaba**.
    ///
    /// El ancla se calcula aquí y no la recibe de fuera, a propósito: el
    /// instante del corte es el que esta rejilla dice que es, y dejarlo entrar
    /// como parámetro abriría la puerta a que quien reancla y quien emite
    /// discreparan sobre dónde caía el Step.
    ///
    /// **Reanclar sobre la misma Division no mueve nada**, y es el caso de casi
    /// todas las ventanas: el instante que se guarda es el que el propio cálculo
    /// devolvía. Por eso quien llama puede permitirse no comprobarlo.
    ///
    /// **`delay` retrasa el ancla respecto a ese instante**, y es cero salvo en
    /// un caso: con Delay negativo, una Division más lenta hace crecer lo que
    /// cada Step se adelanta a su rejilla, y el scheduler retrasa el ancla eso
    /// mismo para que el Step del corte siga sonando cuando sonaba (enmienda
    /// de FR17 de `division-hot-grid_20260911`). Lo que entra de fuera es un
    /// desplazamiento sobre el instante que esta rejilla calcula, no el
    /// instante: quien reancla y quien emite siguen sin poder discrepar sobre
    /// dónde caía el Step.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func rebased(
        to division: Division, atStep step: Int, delayedBy delay: Int64 = 0
    ) -> MusicalTimeline {
        MusicalTimeline(
            tempo: tempo,
            division: division,
            anchorStep: step,
            anchorNanoseconds: nanosecondOffset(forStep: step) + delay
        )
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
    /// **Se mide desde el ancla y se sigue multiplicando, nunca acumulando.** La
    /// distancia es `step - anchorStep`, así que el error queda acotado a un
    /// redondeo por ancla en vez de a uno por Step — que es la misma razón por
    /// la que esto multiplicaba desde el origen antes de que el ancla existiera.
    /// Sin ancla los dos cálculos son el mismo.
    ///
    /// Los índices anteriores al ancla salen de la misma multiplicación, con
    /// distancia negativa: la rejilla se extiende hacia atrás con la duración
    /// **nueva**. No describen lo que sonó —eso lo describía la rejilla
    /// anterior, que ya no existe— y nadie los consulta: la marca de agua del
    /// `LookAheadScheduler` solo avanza.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func nanosecondOffset(forStep step: Int) -> Int64 {
        anchorNanoseconds + Int64((stepDurationNanoseconds * Double(step - anchorStep)).rounded())
    }
}

extension Division: CustomStringConvertible {

    /// Se lee como la fracción que es: `1/16`.
    ///
    /// `product-guidelines.md` pide precisión, no conversación: el valor y nada
    /// más.
    public var description: String { "\(numerator)/\(denominator)" }
}
