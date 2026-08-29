/// Nivel dinámico base de las notas del Track.
///
/// **Vive en la unidad MIDI, 1–127, y no en un porcentaje.** Es lo que viaja
/// por el cable y lo que el sintetizador recibe: convertir desde 0–100%
/// introduciría una pérdida —128 valores no caben en 101— y dos escalas para el
/// mismo dato entre la pantalla y el mensaje. `product-guidelines.md` pide un
/// solo término por concepto; esto es la misma regla aplicada a las unidades.
///
/// **El cero queda fuera a propósito.** En MIDI 1.0 un note-on con velocity 0
/// es la convención de apagado, así que admitirlo dejaría que un parámetro de
/// dinámica produjera silencio por una vía que el resto del código lee como
/// note-off. Para no sonar está Probability.
///
/// Valida en el inicializador, como `Steps` y `Tempo`: un `Velocity` que existe
/// es siempre emisible.
public struct Velocity: Equatable, Sendable {

    /// Rango admitido. El extremo superior es el del protocolo; el inferior
    /// excluye el cero por la razón de arriba.
    public static let validRange: ClosedRange<Int> = 1...127

    /// Default del producto: un nivel medio-alto con margen a los dos lados
    /// para que el primer giro del knob se oiga en cualquier sentido.
    public static let `default` = Velocity(unchecked: 100)

    public let value: Int

    /// Devuelve `nil` si el nivel cae fuera de `validRange`.
    public init?(_ value: Int) {
        guard Self.validRange.contains(value) else { return nil }
        self.value = value
    }

    /// Vía interna para valores ya acotados, como los que produce un giro de
    /// knob. Mismo idioma que `Steps.init(unchecked:)`.
    init(unchecked value: Int) {
        self.value = value
    }
}

/// Duración de nota, como porcentaje de la Division.
///
/// La Pre Spec la describe «de muy corta/percusiva a larga/solapada» y fija su
/// default en «una Division completa», que es exactamente el 100%.
///
/// **Porcentaje y no una duración absoluta** porque la Division cambia con el
/// knob y el tempo con el Bank: un Sustain en milisegundos dejaría de significar
/// lo mismo en cuanto se moviera cualquiera de los dos. Expresado como fracción
/// del Step, «ligado» sigue siendo ligado a cualquier velocidad.
///
/// **Por qué el tope es 200%.** Una nota puede ligar sobre el Step siguiente
/// pero nunca alcanzar el tercero, lo que acota el solape a un solo vecino. El
/// solape no se vigila —ver `NoteEmitter`—, así que acotarlo aquí es lo que hace
/// que su síntoma sea predecible en vez de arbitrario.
public struct Sustain: Equatable, Sendable {

    /// Rango admitido, en porcentaje de la Division.
    public static let validRange: ClosedRange<Int> = 1...200

    /// Default del producto: una Division completa, literal de la Pre Spec.
    public static let `default` = Sustain(unchecked: 100)

    public let percent: Int

    /// Devuelve `nil` si el porcentaje cae fuera de `validRange`.
    ///
    /// El 0% queda fuera: no es una nota corta sino una nota que no suena, y
    /// para eso está `Probability`.
    public init?(percent: Int) {
        guard Self.validRange.contains(percent) else { return nil }
        self.percent = percent
    }

    /// Vía interna para valores ya acotados. Ver `Velocity.init(unchecked:)`.
    init(unchecked percent: Int) {
        self.percent = percent
    }
}

/// Con qué probabilidad suena cada Pulse.
///
/// **Unipolar 0–100% en v1.** La Pre Spec la define con knob bipolar
/// —«clockwise afecta todas las notas; counter-clockwise sólo los Pulses»— pero
/// esa distinción presupone Repeats, que está fuera de v1: sin triggers extra
/// por Pulse, **toda nota es un Pulse** y los dos alcances son el mismo
/// conjunto. Desviación documentada con fecha en `tech-stack.md`, con la
/// condición de vuelta: con Repeats.
///
/// **Los dos extremos son estados válidos.** Al 100% no se omite nada; al 0% no
/// suena nada, que es un Track que dispara y calla — el mismo estado previsto
/// que ya produce un pool vacío, y tampoco es un error.
public struct Probability: Equatable, Sendable {

    /// Rango admitido. A diferencia de los otros dos, incluye el cero.
    public static let validRange: ClosedRange<Int> = 0...100

    /// Default del producto: suena todo. Bajarlo es una decisión, no el punto
    /// de partida.
    public static let `default` = Probability(unchecked: 100)

    public let percent: Int

    /// Devuelve `nil` si el porcentaje cae fuera de `validRange`.
    public init?(percent: Int) {
        guard Self.validRange.contains(percent) else { return nil }
        self.percent = percent
    }

    /// Vía interna para valores ya acotados. Ver `Velocity.init(unchecked:)`.
    init(unchecked percent: Int) {
        self.percent = percent
    }
}

extension Probability {

    /// Si este Pulse suena, tirando del generador.
    ///
    /// **En positivo y no como `omits`.** La Pre Spec habla de omisiones, pero
    /// quien llama pregunta si emite: una forma negativa obligaría a un `!` en
    /// el sitio de uso, que es donde los dobles negativos se leen mal.
    ///
    /// **Cada llamada consume exactamente una tirada, incluidos los extremos.**
    /// Cortocircuitar el 100% sin tirar sería más barato y estaría mal: subir y
    /// bajar el knob desplazaría la fase de la secuencia, y dos sesiones con los
    /// mismos giros en distinto orden dejarían de coincidir. La reproducibilidad
    /// que promete `tech-stack.md` depende de que un Pulse cueste una tirada,
    /// pase lo que pase.
    ///
    /// El sesgo del resto —100 no divide a 2⁶⁴— es de una parte en 1,8·10¹⁷ y
    /// no se corrige: sería trabajo en el camino de tiempo real para una
    /// desviación que ninguna sesión musical puede alcanzar.
    ///
    /// Aritmética entera, sin coma flotante: esto corre en el hilo del
    /// scheduler.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func sounds(drawingFrom generator: inout SeededRandom) -> Bool {
        let draw = generator.next() % 100
        return draw < UInt64(percent)
    }
}

extension Velocity {

    /// Nivel resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Ver `Sustain.advanced(by:)`
    /// para el razonamiento, que es común a los tres.
    public func advanced(by delta: Int) -> Velocity {
        Velocity(unchecked: Self.validRange.clamping(value + delta))
    }
}

extension Sustain {

    /// Duración resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Es el criterio de `Steps` y
    /// `Division`, y no el de `Rotate`: un knob que diera la vuelta al pasarse
    /// del tope convertiría un ajuste fino en un salto al otro extremo del
    /// rango, y `product-guidelines.md` pide que girar produzca «siempre un
    /// cambio inmediato y proporcional».
    ///
    /// Girar contra un tope devuelve **el mismo valor**, que es lo que después
    /// permite a `ControlInput` no publicar un snapshot idéntico.
    public func advanced(by delta: Int) -> Sustain {
        Sustain(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension Probability {

    /// Probabilidad resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Ver `Sustain.advanced(by:)`.
    ///
    /// Su extremo inferior es el 0 y no el 1: a diferencia de los otros dos,
    /// «no suena nada» es un estado que el knob tiene que poder alcanzar.
    public func advanced(by delta: Int) -> Probability {
        Probability(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension ClosedRange where Bound == Int {

    /// El valor llevado dentro del rango.
    ///
    /// Existe para que los tres parámetros de Groove no repitan la misma pareja
    /// de `min`/`max` anidados, que es donde un signo cambiado pasa inadvertido.
    func clamping(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

/// Groove — la familia que convierte la secuencia en interpretación.
///
/// La Pre Spec la sitúa tercera en el flujo del motor: «Shape decide *cuándo* y
/// con qué densidad ocurren eventos» → Tonal elige las alturas → «Groove define
/// dinámica, probabilidad, duración y desplazamiento temporal».
///
/// **Entra partida en dos, y el corte es por riesgo.** Los tres de aquí
/// —Velocity, Sustain y Probability— cambian **qué** se envía. Timing y Delay
/// cambian **cuándo**, que es el camino de jitter que costó validar, y llegan
/// aparte para que una regresión de rejilla no se lleve por delante a estos
/// tres. Accent y la forma de la variación quedan fuera de v1 por `product.md`.
///
/// Es un valor trivial a propósito: viaja dentro del `Track` que cruza al hilo
/// del scheduler, y `_isPOD(Track.self)` lo vigila.
public struct Groove: Equatable, Sendable {

    /// Los defaults de producto: suena todo, a nivel medio-alto, durando una
    /// Division completa. Es el Groove que no interpreta nada — el punto de
    /// partida desde el que cada knob se aparta.
    public static let `default` = Groove(
        velocity: .default,
        sustain: .default,
        probability: .default
    )

    public let velocity: Velocity
    public let sustain: Sustain
    public let probability: Probability

    public init(velocity: Velocity, sustain: Sustain, probability: Probability) {
        self.velocity = velocity
        self.sustain = sustain
        self.probability = probability
    }
}
