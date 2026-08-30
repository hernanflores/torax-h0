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

/// Cuánto se desplaza cada segundo Step — el swing.
///
/// La Pre Spec lo describe como «desplaza cada segundo Step, creando
/// swing/shuffle (rejilla no uniforme)». Este es el primero de los dos
/// parámetros que cambian **cuándo** suena algo, y no qué.
///
/// **El porcentaje es la posición del segundo Step del par dentro del par**, no
/// la fracción que se desplaza. Es la convención del hardware y del software que
/// ya existe, y se lee sola: al 50% el par está partido por la mitad y la
/// rejilla es recta; al 66,7% el par es un tresillo; al 75% el Step impar cae
/// medio Step tarde.
///
/// **Por debajo del 50% no hay nada que ganar.** Sería swing invertido —el Step
/// impar adelantado— y para adelantar está `Delay`, que además lo hace sobre el
/// Track entero y con el presupuesto de adelanto que eso exige.
///
/// **El tope de 75% es una decisión de corrección, no de gusto.** Medio Step es
/// el desplazamiento máximo con el que un Step nunca alcanza al siguiente:
/// pasado ese punto la secuencia de emisión podría invertirse, y un evento que
/// adelanta a su predecesor es una nota fuera de sitio, no un valor extremo.
/// La invariante de orden está fijada por un test exhaustivo.
///
/// **El tresillo exacto cae entre dos valores del knob.** Con porcentaje entero,
/// 2:1 sería 66,67% y el knob pasa por 66 y por 67; el más cercano se separa
/// menos de un 0,7% de la duración del Step —a 1/16 y 120 BPM, unos 0,9 ms—, que
/// está por debajo de lo que distingue el oído. Un décimo de porcentaje daría
/// exactitud a cambio de diez veces más recorrido de knob para el mismo tramo.
public struct Timing: Equatable, Sendable {

    /// Rango admitido. El extremo inferior es la rejilla recta; el superior, el
    /// límite que conserva el orden de emisión.
    public static let validRange: ClosedRange<Int> = 50...75

    /// La rejilla recta: ningún Step se mueve.
    public static let straight = Timing(unchecked: 50)

    /// Default del producto: recto. El swing es una decisión, no el punto de
    /// partida — mismo criterio que `Probability.default`.
    public static let `default` = straight

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

/// Cuánto se desplaza el Track entero respecto a la rejilla.
///
/// La Pre Spec: «desplaza el Track entero hacia adelante o atrás respecto a la
/// rejilla». A diferencia de `Timing`, se aplica a todos los Steps por igual.
///
/// **Porcentaje de la Division y no milisegundos**, por la misma razón que
/// `Sustain`: expresado en tiempo absoluto dejaría de significar lo mismo en
/// cuanto se moviera el tempo o la Division. «Medio Step antes» sigue siendo
/// medio Step a cualquier velocidad.
///
/// **Es el único parámetro del motor con rango negativo**, y esa mitad es la que
/// tiene coste. Un evento adelantado hay que calcularlo antes de su instante, o
/// se pide su emisión para un momento que ya pasó; de ahí el *presupuesto de
/// adelanto*, que desplaza el origen de la rejilla al arrancar y amplía el
/// horizonte de selección mientras suena. Enmienda fechada del 2026-08-30 en
/// `tech-stack.md`.
///
/// El cero no es un extremo sino el centro: el knob lo cruza sin caso especial.
public struct Delay: Equatable, Sendable {

    /// Rango admitido, en porcentaje de la Division. Simétrico: un Step entero
    /// hacia cada lado.
    public static let validRange: ClosedRange<Int> = -100...100

    /// Default del producto: sobre la rejilla.
    public static let `default` = Delay(unchecked: 0)

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

extension Sustain {

    /// Cuánto dura la nota, dado lo que dura un Step.
    ///
    /// **La aritmética vive en `Engine` y no en la capa MIDI** por la razón de
    /// siempre: `workflow.md` dice que si algo merece un test está donde se
    /// testea, y un porcentaje mal aplicado se oye como notas que se cortan o
    /// que no se sueltan.
    ///
    /// Entera y en nanosegundos, sin coma flotante: esto acaba corriendo en el
    /// hilo del scheduler. El orden —multiplicar antes de dividir— conserva la
    /// precisión que dividir primero perdería.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Calculates the gate duration for a step using the sustain percentage.
    /// - Parameter stepDurationNanoseconds: The step duration in nanoseconds.
    /// - Returns: The gate duration in nanoseconds.
    public func gateNanoseconds(forStep stepDurationNanoseconds: Int64) -> Int64 {
        stepDurationNanoseconds * Int64(percent) / 100
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
    /// Determines whether the pulse sounds based on this probability and a random draw.
    /// - Parameter generator: The random generator used to produce the draw.
    /// - Returns: `true` if the draw is below the probability percentage, `false` otherwise.
    public func sounds(drawingFrom generator: inout SeededRandom) -> Bool {
        let draw = generator.next() % 100
        return draw < UInt64(percent)
    }
}

extension Velocity {

    /// Nivel resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Ver `Sustain.advanced(by:)`
    /// Adjusts the MIDI velocity by the specified amount within its valid range.
    /// - Parameter delta: The amount to add to the velocity.
    /// - Returns: A velocity clamped between 1 and 127.
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
    /// Adjusts the sustain percentage by the specified amount within its valid range.
    ///
    /// - Parameter delta: The amount to add to the sustain percentage.
    /// - Returns: A sustain value clamped to the valid range.
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
    /// Adjusts the probability by the specified amount while keeping it within the valid range.
    /// - Parameter delta: The amount to add to the probability.
    /// - Returns: The adjusted probability.
    public func advanced(by delta: Int) -> Probability {
        Probability(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension ClosedRange where Bound == Int {

    /// El valor llevado dentro del rango.
    ///
    /// Existe para que los tres parámetros de Groove no repitan la misma pareja
    /// Restricts a value to the bounds of the range.
    /// - Parameter value: The value to restrict.
    /// - Returns: The lower bound if the value is below the range, the upper bound if it is above the range, or the value itself otherwise.
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
    /// Division completa, sobre la rejilla recta y sin desplazar. Es el Groove
    /// que no interpreta nada — el punto de partida desde el que cada knob se
    /// aparta.
    ///
    /// **Que no interprete nada en el tiempo es una propiedad de la que depende
    /// el arnés de medición.** Su modo `everyStep` usa este valor, así que la
    /// medición de regresión sigue midiendo la rejilla de `MusicalTimeline` y no
    /// una desplazada.
    public static let `default` = Groove(
        velocity: .default,
        sustain: .default,
        probability: .default
    )

    public let velocity: Velocity
    public let sustain: Sustain
    public let probability: Probability
    public let timing: Timing
    public let delay: Delay

    /// **Timing y Delay entran con valor por defecto.** `Groove` se construye en
    /// sitios que no saben nada de ellos —tests, código anterior a la rebanada
    /// 6— y los defaults son lo que les permite seguir compilando y sonando
    /// igual. No es comodidad: es la regla de destructividad de
    /// `product-guidelines.md` aplicada al código, un parámetro nuevo no cambia
    /// lo que ya hacía quien no lo pide.
    public init(
        velocity: Velocity,
        sustain: Sustain,
        probability: Probability,
        timing: Timing = .default,
        delay: Delay = .default
    ) {
        self.velocity = velocity
        self.sustain = sustain
        self.probability = probability
        self.timing = timing
        self.delay = delay
    }
}

extension Groove: CustomStringConvertible {

    /// Cómo se lee Groove en pantalla:
    /// `Velocity 100 · Sustain 100% · Probability 75% · Timing 50% · Delay 0%`.
    ///
    /// Mismo formato que `Shape.description`, y por la misma razón: el término
    /// de la Pre Spec en inglés y el valor, sin prosa. `product-guidelines.md`
    /// pide informar, no acompañar.
    ///
    /// **Vive en `Engine` y no en la vista** porque `workflow.md` dice que si
    /// algo en `App` merece un test está en el sitio equivocado. Un formato es
    /// exactamente eso.
    ///
    /// Velocity va sin signo de porcentaje: vive en la unidad MIDI, y ponérselo
    /// diría que es un porcentaje de algo.
    ///
    /// **El signo de Delay se ve, y no es adorno.** Es el único parámetro que
    /// puede ser negativo, y adelantar y atrasar no se distinguen por el
    /// contexto: sin el signo, `Delay 25%` sería ambiguo. La interpolación lo
    /// pone sola en el negativo y lo omite en el positivo, que es la convención
    /// que ya usa `Rotate`.
    public var description: String {
        "Velocity \(velocity.value) · Sustain \(sustain.percent)% · "
            + "Probability \(probability.percent)% · Timing \(timing.percent)% · "
            + "Delay \(delay.percent)%"
    }
}
