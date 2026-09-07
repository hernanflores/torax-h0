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

extension ClockSource {

    /// El nombre, en el vocabulario de la Pre Spec y sin traducir.
    ///
    /// **Vive aquí desde el 2026-09-06.** Se escribía como literal en tres sitios
    /// de `App` —dos segmentos de la pantalla `midi` y un ternario en la barra—,
    /// que es la misma clase de fuga que ya se corrigió con `Scale.name` y
    /// `ParameterFamily.name`. Capitalizado como el resto del vocabulario; la
    /// minúscula la pone la capa de presentación.
    public var name: String {
        switch self {
        case .internal: "Internal"
        case .external: "External"
        }
    }
}

// **Vive en `Engine` desde el 2026-09-07**, y llegó aquí por la misma razón por
// la que `name` bajó de `App` el 2026-09-06: es vocabulario del dominio y no
// tiene una línea de CoreMIDI dentro. Lo pide la rebanada 4 de la v2, donde el
// `Project` guarda qué reloj manda y `Engine` no puede ver el paquete `MIDI`.
