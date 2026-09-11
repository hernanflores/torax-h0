/// Las rejillas con que suena un Track: la vigente y la que había antes de
/// ella.
///
/// **Existe porque la rejilla se reancla mientras suena y el scheduler va por
/// delante.** Cuando la Division cambia, el scheduler ancla la rejilla nueva en
/// un Step que todavía no ha sonado —puede faltarle una ventana de look-ahead,
/// o más con Delay negativo—. Hasta que ese instante llegue, lo que se oye sigue
/// midiéndose con la anterior. Guardar las dos es lo que deja a la interfaz
/// dibujar lo que suena y no lo que el scheduler ya decidió.
///
/// Es la misma razón por la que `CyclePosition.Phase` guarda más de un cursor.
///
/// **Dos bastan en la práctica, y no siempre.** Si la rejilla se reancla dos
/// veces antes de que la primera llegue a sonar, la de antes de ambas se pierde
/// y, durante esa ventana, el tiempo se mide con la anterior extendida hacia
/// atrás. El error queda acotado a lo que el scheduler va por delante, y solo
/// dura hasta que suena el primer ancla.
///
/// No es código de tiempo real: lo consulta la interfaz al redibujar.
public struct PlaybackGrid: Equatable, Sendable {

    /// La rejilla que el scheduler está usando.
    public let current: MusicalTimeline

    /// La que usaba antes de reanclar. Sin reanclaje es la misma que `current`.
    public let previous: MusicalTimeline

    public init(current: MusicalTimeline, previous: MusicalTimeline) {
        self.current = current
        self.previous = previous
    }

    /// La rejilla que manda en `nanoseconds`: la vigente desde su ancla, y la
    /// anterior antes de ella.
    public func timeline(atNanoseconds nanoseconds: Int64) -> MusicalTimeline {
        nanoseconds >= current.anchorNanoseconds ? current : previous
    }
}
