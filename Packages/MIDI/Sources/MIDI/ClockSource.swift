/// Quién manda el tempo.
///
/// **Es una elección del usuario, no una consecuencia del cable.** Si bastara
/// con que llegara un clock para seguirlo, conectar el controlador cambiaría lo
/// que suena sin que nadie lo hubiera pedido, y no habría forma de decir «este
/// maestro no me interesa». Por eso son dos estados explícitos y no una
/// detección automática.
public enum ClockSource: Equatable, Sendable {

    /// El reloj de la app. Es el valor por defecto: es lo que la app hacía antes
    /// de que esta elección existiera.
    case `internal`

    /// El reloj de un maestro externo, por la misma fuente de la que llegan los
    /// knobs.
    case external
}
