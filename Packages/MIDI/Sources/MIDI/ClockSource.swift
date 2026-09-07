import Engine

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
