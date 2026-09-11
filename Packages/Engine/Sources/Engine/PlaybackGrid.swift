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

    /// La rejilla que manda en `nanoseconds`: la anterior hasta que las dos
    /// marcan la misma posición, y la vigente desde ahí.
    public func timeline(atNanoseconds nanoseconds: Int64) -> MusicalTimeline {
        Double(nanoseconds) >= switchNanoseconds ? current : previous
    }

    /// El instante en que se pasa de la anterior a la vigente.
    ///
    /// **Sin Delay es el ancla**, porque ahí las dos rejillas marcan el mismo
    /// Step: el ancla conserva el instante que ese Step tenía.
    ///
    /// **Con el ancla retrasada no lo es**, y cambiar en el ancla hacía saltar
    /// el anillo. Encontrado en el iPad el 2026-09-11, con Delay −100% y 1/16 →
    /// 1/8. El scheduler retrasa el ancla lo que crece el presupuesto de Delay
    /// (enmienda de FR17), y hasta llegar a ella la rejilla anterior seguía
    /// contando con su Step corto: el anillo se adelantaba hasta casi un Step y,
    /// en el ancla, volvía atrás. Las dos rectas se cruzan antes, en el
    /// instante en que suena el Step del corte, y cambiar ahí deja el anillo
    /// continuo.
    ///
    /// El cruce se calcula multiplicando las dos duraciones y no restando sus
    /// inversas: con Divisions del knob el resultado sale exacto. Se acota
    /// entre las dos anclas por si las rejillas no fueran consecutivas.
    var switchNanoseconds: Double {
        let anchor = Double(current.anchorNanoseconds)
        let before = previous.stepDurationNanoseconds
        let after = current.stepDurationNanoseconds
        guard before != after else { return anchor }

        // Cuántos Steps va por delante la anterior en el ancla de la vigente.
        let stepsSincePreviousAnchor: Double =
            (anchor - Double(previous.anchorNanoseconds)) / before
        let previousPosition: Double = Double(previous.anchorStep) + stepsSincePreviousAnchor
        let lead: Double = previousPosition - Double(current.anchorStep)

        let nanosecondsPerStepOfLead: Double = before * after / (after - before)
        let crossing: Double = anchor - lead * nanosecondsPerStepOfLead
        let earliest = Double(previous.anchorNanoseconds)
        return min(max(crossing, earliest), anchor)
    }
}
