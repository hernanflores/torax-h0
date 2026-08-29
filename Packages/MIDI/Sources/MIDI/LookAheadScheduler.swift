import Engine

/// Decide qué Steps entran en la ventana futura que se entrega a CoreMIDI.
///
/// **Por qué look-ahead.** El scheduler no espera a que llegue el instante de
/// cada evento para enviarlo: calcula por adelantado los Steps que caen dentro
/// de un horizonte y los entrega ya sellados con su timestamp de entrega. Es
/// CoreMIDI quien los emite en el instante exacto. La consecuencia es la razón
/// de la arquitectura: **el jitter deja de depender de cuándo despierta el hilo
/// del scheduler**, que puede llegar tarde dentro de la ventana sin que se note.
///
/// **Por qué devuelve un rango y no eventos.** `advance(toHorizon:)` devuelve un
/// `Range<Int>` de índices de Step: dos enteros. No hay array que construir ni
/// buffer que preasignar, así que la regla "sin asignaciones en el hilo del
/// scheduler" se cumple por construcción y no por vigilancia.
///
/// **Invariante.** Sobre llamadas sucesivas, cada Step se emite exactamente una
/// vez: los rangos devueltos son contiguos y nunca retroceden. Duplicar un Step
/// sería una nota repetida; omitirlo, una nota perdida.
public struct LookAheadScheduler {

    public let timeline: MusicalTimeline

    /// Primer Step aún no entregado. Marca de agua que solo avanza.
    public private(set) var nextStep: Int

    public init(timeline: MusicalTimeline, startingAtStep startingStep: Int = 0) {
        self.timeline = timeline
        self.nextStep = startingStep
    }

    /// Devuelve los Steps cuyo offset cae antes de `horizonNanoseconds`, y que
    /// no se hayan entregado ya.
    ///
    /// El límite superior es exclusivo: un Step que caiga exactamente en el
    /// horizonte se entrega en la ventana siguiente, no en esta. Así el solape
    /// entre ventanas consecutivas no puede emitirlo dos veces.
    ///
    /// Un horizonte que no avanza —o que retrocede— devuelve un rango vacío.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func advance(toHorizon horizonNanoseconds: Int64) -> Range<Int> {
        let upperBound = firstStep(atOrAfter: horizonNanoseconds)
        guard upperBound > nextStep else { return nextStep..<nextStep }

        let range = nextStep..<upperBound
        nextStep = upperBound
        return range
    }

    /// Índice del primer Step cuyo offset es mayor o igual que el horizonte.
    ///
    /// Se estima dividiendo y se corrige con un ajuste acotado, en lugar de
    /// recorrer los Steps uno a uno: el coste es constante aunque el horizonte
    /// salte muy lejos. El ajuste existe porque los offsets están redondeados a
    /// nanosegundos enteros y la estimación puede quedarse corta o pasarse por
    /// uno.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private func firstStep(atOrAfter horizonNanoseconds: Int64) -> Int {
        guard horizonNanoseconds > 0 else { return 0 }

        let stepDuration = timeline.stepDurationNanoseconds
        var candidate = Int(Double(horizonNanoseconds) / stepDuration)

        // La estimación se quedó corta: avanza mientras el Step siga cayendo
        // antes del horizonte.
        while timeline.nanosecondOffset(forStep: candidate) < horizonNanoseconds {
            candidate += 1
        }
        // La estimación se pasó: retrocede mientras el Step anterior ya caiga
        // en el horizonte o después.
        while candidate > 0,
            timeline.nanosecondOffset(forStep: candidate - 1) >= horizonNanoseconds
        {
            candidate -= 1
        }

        return candidate
    }
}
