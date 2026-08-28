/// Cómo se recorre el pool para decidir la altura de cada Pulse.
///
/// **Un solo caso hoy, a propósito.** La Pre Spec describe para Style
/// monofónico «una nota por vez: arpegios, broken chords y patrones
/// ascendentes/descendentes», y Style está fuera de v1. Lo que entra ahora es el
/// ascendente.
///
/// **Por qué es un tipo y no una función suelta.** Mismo criterio que
/// `RelativeEncoding`: hoy solo hace falta una convención, pero llegarán el
/// recorrido aleatorio —con el PRNG sembrado que trae Probability— y las formas
/// de Phrase. Que la convención entre como valor significa que añadirlas será
/// añadir casos, y no reescribir el camino de tiempo real ni a sus llamantes.
///
/// **El nombre no está en la Pre Spec.** El concepto sí —es lo que Style decide
/// para el pool—, pero llamarlo `Style` reservaría un término del dominio para
/// algo más estrecho de lo que significa, y eso es introducir un sinónimo por la
/// puerta de atrás.
public enum PoolTraversal: Equatable, Sendable, CaseIterable {

    /// De grave a agudo, volviendo al principio al agotar el pool.
    case ascending

    /// La altura que le toca al Pulse número `ordinal`.
    ///
    /// Devuelve `nil` con el pool vacío: el Track dispara y no tiene material
    /// que emitir. Es un estado previsto, no un fallo — quien llame no suena, y
    /// ya está.
    ///
    /// Un ordinal negativo no puede llegar del scheduler, que cuenta hacia
    /// arriba. Si llegara **envuelve**, igual que hacen `triggers(atStep:)` y
    /// `Rotate`: un solo criterio para el mismo problema en todo el motor.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func pitch(from pool: PitchPool, atPulse ordinal: Int) -> Pitch? {
        guard !pool.isEmpty else { return nil }

        switch self {
        case .ascending:
            let remainder = ordinal % pool.count
            let index = remainder < 0 ? remainder + pool.count : remainder
            return pool.pitch(at: index)
        }
    }
}
