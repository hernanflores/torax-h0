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

/// Qué está pasando con el reloj externo.
///
/// **Bajó de `App` el 2026-09-06.** La tabla de mensajes vivía en
/// `TransportModel`, que está en `App` y no se mide: leía tres estados del
/// `Transport` y decidía cuál contar. Una regla mal escrita ahí no falla —enseña
/// el mensaje equivocado, que es peor que fallar— y `workflow.md` manda que lo
/// que se rompe en silencio esté donde hay tests.
///
/// **Es un valor puro y por eso se puede probar entero.** No toma un `Transport`
/// sino los tres booleanos que lo describen, así que las dieciséis combinaciones
/// se recorren sin hardware ni reloj corriendo.
public enum ClockStatus: Equatable, Sendable, CaseIterable {

    /// Se sigue a un maestro y está sonando.
    case following

    /// **Se estaba siguiendo y dejó de llegar.** Es el único urgente de los
    /// cuatro: el transporte sigue con el último tempo conocido en vez de
    /// pararse, así que sin decirlo la app parecería estar bien mientras se
    /// separa del maestro.
    case lost

    /// Hay maestro pero el transporte está parado.
    case detected

    /// No llega ningún reloj.
    case absent

    /// Qué está pasando, o `nil` con reloj interno — que no tiene nada que
    /// contar: el tempo lo pone la app y ya se ve.
    ///
    /// **Parado, `hasDropped` no se mira.** Describe una pérdida en marcha y no
    /// dice nada con el transporte quieto; lo que importa entonces es si hay
    /// maestro o no.
    public init?(source: ClockSource, isPlaying: Bool, hasDropped: Bool, isEstablished: Bool) {
        guard source == .external else { return nil }

        switch (isPlaying, hasDropped) {
        case (true, true): self = .lost
        case (true, false): self = .following
        case (false, _): self = isEstablished ? .detected : .absent
        }
    }

    /// El texto, en inglés y sin traducir (NFR7).
    public var description: String {
        switch self {
        case .following: "Following external clock"
        case .lost: "Clock lost — holding last tempo"
        case .detected: "External clock detected"
        case .absent: "No clock"
        }
    }
}
