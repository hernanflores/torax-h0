/// Todo lo que se puede ajustar en un Track.
///
/// **Vive en `Engine` y no en la capa de entrada** porque nombra conceptos del
/// dominio, no del transporte: *qué* se puede ajustar es una propiedad del
/// motor; *por dónde* llega la orden —un knob, un mensaje MIDI, un test— es
/// otra cosa, y cambiará más veces que esta lista.
///
/// **Se llamaba `ShapeParameter` y solo nombraba cuatro.** Con Groove son
/// siete, y con Timing y Delay serán nueve. El nombre viejo obligaba a que la
/// pantalla y el mapeo de CC supieran a qué familia pertenece cada parámetro
/// para poder moverlo, que es un acoplamiento sin ninguna razón de dominio
/// detrás: quien gira un knob quiere mover *ese* parámetro, no consultar su
/// linaje.
///
/// El orden es el de las familias en el flujo del motor —Shape decide *cuándo*,
/// Groove *cómo se interpreta*— y es el que ve la pantalla.
///
/// Lo que falta: Timing y Delay llegan en la rebanada 6; el pool de Pitch no
/// está aquí porque no se ajusta con un delta sino con pads, que es otra
/// superficie.
public enum TrackParameter: Equatable, Sendable, CaseIterable {

    // Shape — cuándo y con qué densidad ocurren los eventos.
    case steps
    case pulses
    case rotate
    case division

    // Groove — cómo se interpreta lo que ocurre.
    case velocity
    case sustain
    case probability
}

/// A qué familia funcional pertenece un parámetro.
///
/// **Existe porque el color lo necesita, pero no es color.**
/// `product-guidelines.md` da un acento cromático a cada familia y dice que «el
/// color codifica *qué tipo de parámetro es*; nunca es decorativo». Qué tipo es
/// lo sabe el motor; qué color le toca lo decide la vista. Poner el `switch`
/// allí lo dejaría donde no hay tests, que es lo que `workflow.md` prohíbe.
///
/// **Tonal no está aquí.** Su acento existe y se usa, pero el pool no se ajusta
/// con un delta sino con pads, así que no es un `TrackParameter` y no tiene por
/// qué aparecer en esta clasificación.
public enum ParameterFamily: Equatable, Sendable, CaseIterable {

    /// Cuándo y con qué densidad ocurren los eventos.
    case shape

    /// Cómo se interpreta lo que ocurre.
    case groove
}

extension TrackParameter {

    /// La familia a la que pertenece.
    public var family: ParameterFamily {
        switch self {
        case .steps, .pulses, .rotate, .division: .shape
        case .velocity, .sustain, .probability: .groove
        }
    }
}

extension TrackParameter: CustomStringConvertible {

    /// Los términos de la Pre Spec, en inglés y sin traducir, como exige
    /// `product-guidelines.md`.
    public var description: String {
        switch self {
        case .steps: "Steps"
        case .pulses: "Pulses"
        case .rotate: "Rotate"
        case .division: "Division"
        case .velocity: "Velocity"
        case .sustain: "Sustain"
        case .probability: "Probability"
        }
    }
}

extension Track {

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
    /// asigna. Se llama desde el hilo de control, al recibir un giro.
    public func applying(_ delta: Int, to parameter: TrackParameter) -> Track {
        switch parameter {
        case .steps, .pulses, .rotate, .division:
            return Track(
                shape: shape.applying(delta, to: parameter),
                pool: pool,
                groove: groove
            )

        case .velocity:
            return withGroove(
                Groove(
                    velocity: groove.velocity.advanced(by: delta),
                    sustain: groove.sustain,
                    probability: groove.probability
                ))

        case .sustain:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain.advanced(by: delta),
                    probability: groove.probability
                ))

        case .probability:
            return withGroove(
                Groove(
                    velocity: groove.velocity,
                    sustain: groove.sustain,
                    probability: groove.probability.advanced(by: delta)
                ))
        }
    }

    private func withGroove(_ groove: Groove) -> Track {
        Track(shape: shape, pool: pool, groove: groove)
    }
}
