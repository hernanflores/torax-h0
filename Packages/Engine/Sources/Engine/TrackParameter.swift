/// Todo lo que se puede ajustar en un Track.
///
/// **Vive en `Engine` y no en la capa de entrada** porque nombra conceptos del
/// dominio, no del transporte: *qué* se puede ajustar es una propiedad del
/// motor; *por dónde* llega la orden —un knob, un mensaje MIDI, un test— es
/// otra cosa, y cambiará más veces que esta lista.
///
/// **Se llamaba `ShapeParameter` y solo nombraba cuatro.** Con Groove entero
/// son nueve. El nombre viejo obligaba a que la
/// pantalla y el mapeo de CC supieran a qué familia pertenece cada parámetro
/// para poder moverlo, que es un acoplamiento sin ninguna razón de dominio
/// detrás: quien gira un knob quiere mover *ese* parámetro, no consultar su
/// linaje.
///
/// El orden es el de las familias en el flujo del motor —Shape decide *cuándo*,
/// Groove *cómo se interpreta*— y es el que ve la pantalla.
///
/// Lo que falta: el pool de Pitch no está aquí porque no se ajusta con un delta
/// sino con pads, que es otra superficie.
public enum TrackParameter: Hashable, Sendable, CaseIterable {

    // Shape — cuándo y con qué densidad ocurren los eventos.
    case steps
    case pulses
    case rotate
    case division

    // Groove — cómo se interpreta lo que ocurre.
    case velocity
    case sustain
    case probability

    // Groove, en el tiempo — cuándo ocurre respecto a la rejilla.
    case timing
    case delay
}

/// A qué familia funcional pertenece un parámetro.
///
/// **Existe porque el color lo necesita, pero no es color.**
/// `product-guidelines.md` da un acento cromático a cada familia y dice que «el
/// color codifica *qué tipo de parámetro es*; nunca es decorativo». Qué tipo es
/// lo sabe el motor; qué color le toca lo decide la vista. Poner el `switch`
/// allí lo dejaría donde no hay tests, que es lo que `workflow.md` prohíbe.
///
/// **No todas las familias son alcanzables desde un `TrackParameter`.** Tonal
/// no lo es: Scale y Root son táctiles y el pool se edita con pads, así que
/// ninguno de los tres se ajusta con un delta. Está aquí de todas formas porque
/// esta lista clasifica *familias*, no parámetros, y el tercer tab de la
/// pantalla necesita su acento por la misma vía que los otros dos.
public enum ParameterFamily: Equatable, Sendable, CaseIterable {

    /// Cuándo y con qué densidad ocurren los eventos.
    case shape

    /// Cómo se interpreta lo que ocurre.
    case groove

    /// De qué material salen las alturas: Scale, Root y el pool.
    ///
    /// **Es una clasificación, no un parámetro.** Ningún `TrackParameter` cae
    /// aquí y `ParameterFamilyTests` lo fija. Existe para que el tab TONAL saque
    /// su color de `accent(for:)` como los otros dos, en vez de que la vista
    /// resuelva ese caso con un condicional propio — que lo dejaría donde no hay
    /// tests, exactamente lo que esta clasificación existe para evitar.
    case tonal

    /// El nombre de la familia, en el vocabulario de la Pre Spec y sin traducir
    /// (`product-guidelines.md`, NFR7).
    ///
    /// **Vive aquí desde el 2026-09-06.** Se escribía en un `switch` dentro de
    /// `ParameterFamilyCard`, y el card tonal repetía el suyo como literal. Es la
    /// misma clase de texto que `Scale.name`: dominio, no presentación, y se
    /// rompe en silencio — una familia mal nombrada se sigue dibujando.
    ///
    /// **Capitalizado, como el resto del vocabulario.** Que la interfaz lo pinte
    /// en minúsculas es cosa de la capa de presentación.
    public var name: String {
        switch self {
        case .shape: "Shape"
        case .groove: "Groove"
        case .tonal: "Tonal"
        }
    }
}

extension TrackParameter {

    /// La familia a la que pertenece.
    public var family: ParameterFamily {
        switch self {
        case .steps, .pulses, .rotate, .division: .shape
        case .velocity, .sustain, .probability, .timing, .delay: .groove
        }
    }
}

extension TrackParameter: CustomStringConvertible {

    /// Los términos de la Pre Spec, en inglés y sin traducir, como exige
    /// `product-guidelines.md`.
    /// Los extremos entre los que se mueve este parámetro, o `nil` si envuelve
    /// en vez de acotarse.
    ///
    /// **Lo consume el tope del desplazamiento acumulado de Ctrl All** (FR5), y
    /// nada más. Se expone el rango entero y no solo su ancho porque el tope se
    /// calcula contra los **valores concretos** de los Tracks capturados: cuánto
    /// le queda por subir al que más recorrido tiene, y cuánto por bajar al que
    /// más. Ver `CtrlAllOffset.advancing(_:by:)`.
    ///
    /// **`nil` para Rotate, y no un rango vacío.** Rotate envuelve módulo el
    /// `steps.count` de cada Cycle, así que no tiene extremos contra los que
    /// saturar y su knob no puede quedarse muerto: la razón del tope no le
    /// aplica.
    ///
    /// **Sale de los rangos que cada tipo ya declara**, no de una tabla nueva:
    /// duplicar los extremos aquí sería tener dos sitios donde equivocarse, y el
    /// segundo se olvidaría al cambiar el primero.
    public var displacementRange: ClosedRange<Int>? {
        switch self {
        case .steps: Steps.validRange
        case .pulses: Pulses.validRange
        case .rotate: nil
        case .division: 0...(Division.ordered.count - 1)
        case .velocity: Velocity.validRange
        case .sustain: Sustain.validRange
        case .probability: Probability.validRange
        case .timing: Timing.validRange
        case .delay: Delay.validRange
        }
    }

    public var description: String {
        switch self {
        case .steps: "Steps"
        case .pulses: "Pulses"
        case .rotate: "Rotate"
        case .division: "Division"
        case .velocity: "Velocity"
        case .sustain: "Sustain"
        case .probability: "Probability"
        case .timing: "Timing"
        case .delay: "Delay"
        }
    }
}

extension Cycle {

    /// El Track resultante de desplazar uno de sus parámetros.
    ///
    /// **Este es el despacho que el renombrado hace posible.** Quien recibe un
    /// giro de knob ya no tiene que saber si el parámetro es de Shape o de
    /// Groove: lo dice el caso. Añadir Timing y Delay será añadir dos casos, no
    /// tocar a ningún llamante.
    ///
    /// **Lo que no se mueve se conserva.** Ajustar un parámetro de Shape deja
    /// intactos el Groove y el pool, y al revés. Es la regla de destructividad
    /// de `product-guidelines.md` —«cambiar un parámetro nunca destruye
    /// material»— aplicada a la estructura y no solo al pool tonal.
    ///
    /// No es código de tiempo real: construir un Shape reparte los Pulses, y eso
    /// Applies a delta to the selected track parameter while preserving the other track values.
    /// - Parameters:
    ///   - delta: The amount by which to advance the parameter.
    ///   - parameter: The track parameter to adjust.
    /// - Returns: A new track with the selected parameter adjusted.
    public func applying(_ delta: Int, to parameter: TrackParameter) -> Cycle {
        switch parameter {
        case .steps, .pulses, .rotate, .division:
            // `with(...)` y no `Track(...)`: reconstruir enumerando campos es lo
            // que hizo que un giro de knob perdiera el canal, el marco tonal y
            // el registro de pads en cuanto el Track creció.
            return with(shape: shape.applying(delta, to: parameter))

        case .velocity:
            return withGroove(
                Groove(
                    velocity: groove.velocity.advanced(by: delta),
                    sustain: groove.sustain,
                    probability: groove.probability,
                    timing: groove.timing,
                    delay: groove.delay
                ))

        case .sustain:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain.advanced(by: delta),
                    probability: groove.probability,
                    timing: groove.timing,
                    delay: groove.delay
                ))

        case .probability:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain,
                    probability: groove.probability.advanced(by: delta),
                    timing: groove.timing,
                    delay: groove.delay
                ))

        case .timing:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain,
                    probability: groove.probability,
                    timing: groove.timing.advanced(by: delta),
                    delay: groove.delay
                ))

        case .delay:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain,
                    probability: groove.probability,
                    timing: groove.timing,
                    delay: groove.delay.advanced(by: delta)
                ))
        }
    }

    /// Creates a track with the specified groove while preserving its shape and pool.
    /// - Parameter groove: The replacement groove.
    /// - Returns: A track with the specified groove.
    private func withGroove(_ groove: Groove) -> Cycle {
        with(groove: groove)
    }
}

extension TrackParameter {

    /// Cómo está este parámetro en un Cycle, ya escrito y con su unidad.
    ///
    /// **Existe porque un card en reposo no tiene dos Cycles que comparar.**
    /// Hasta el 2026-09-06 el valor de un parámetro solo se sabía escribir como
    /// efecto de un cambio, dentro de `ParameterChange`: el handoff de iPadOS
    /// pide los nueve a la vez y en reposo, así que la lectura tenía que poder
    /// hacerse sin diferencia.
    ///
    /// **`ParameterChange` pasa a usar esto**, así que las nueve reglas de
    /// escritura viven en un solo sitio en vez de dos. Un test comprueba que lo
    /// que anuncia un giro y lo que dice el card son la misma cadena: si alguna
    /// vez se separan, es un fallo y no una variación.
    ///
    /// El texto no lleva el nombre del parámetro; ése lo da `description`.
    public func value(in track: Cycle) -> String {
        let shape = track.shape
        let groove = track.groove
        switch self {
        case .steps: return "\(shape.steps.count)"
        // **El valor pedido, no `effectivePulses`.** El knob está en este número
        // y mostrar el otro haría creer que se perdió (enmienda del 2026-08-27).
        case .pulses: return "\(shape.pulses.count)"
        case .rotate: return "\(shape.rotate.amount)"
        case .division: return "\(shape.division)"
        // Sin signo de porcentaje: Velocity vive en la unidad MIDI, y ponérselo
        // diría que es un porcentaje de algo.
        case .velocity: return "\(groove.velocity.value)"
        case .sustain: return "\(groove.sustain.percent)%"
        case .probability: return "\(groove.probability.percent)%"
        case .timing: return "\(groove.timing.percent)%"
        // Con signo, y por la misma razón que en `Groove.description`: es el
        // único parámetro que puede ser negativo, y adelantar y atrasar no se
        // distinguen por el contexto.
        case .delay: return "\(groove.delay.percent)%"
        }
    }
}
