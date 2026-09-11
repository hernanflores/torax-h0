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

    /// **`var` desde el 2026-09-11, y no `let`**: la Division se gira mientras
    /// suena, así que la rejilla tiene que poder cambiar sin reconstruir el
    /// scheduler — reconstruirlo perdería la marca de agua, que es lo único que
    /// impide duplicar o perder un Step.
    public private(set) var timeline: MusicalTimeline

    /// Primer Step aún no entregado. Marca de agua que solo avanza.
    public private(set) var nextStep: Int

    public init(timeline: MusicalTimeline, startingAtStep startingStep: Int = 0) {
        self.timeline = timeline
        self.nextStep = startingStep
    }

    /// Cambia la Division **sin mover la marca de agua**, anclando la rejilla
    /// nueva en el Step aún no entregado.
    ///
    /// **Por qué el ancla es `nextStep` y no el Step que suena.** Ese Step
    /// todavía no cabía en ninguna ventana, así que su instante está por delante
    /// del horizonte ya servido: anclar ahí es lo que hace imposible que el
    /// cambio produzca un evento para un instante que ya pasó (FR7). Anclar en
    /// el que suena sí podría, porque su instante quedó atrás.
    ///
    /// **Lo ya entregado no se reescribe** (FR4). Los Steps que salieron con la
    /// rejilla anterior salieron con sus timestamps sellados y CoreMIDI los va a
    /// emitir donde dijeron; el cambio empieza a oírse en la ventana siguiente.
    ///
    /// **Reanclar sobre la misma Division no mueve nada**, así que quien llama
    /// no tiene que acordarse de si ya reancló: el instante que se guarda es el
    /// que el propio cálculo devolvía.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func rebase(to division: Division) {
        timeline = timeline.rebased(to: division, atStep: nextStep)
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
    /// Finds the first step at or after the specified timeline horizon.
    /// - Parameter horizonNanoseconds: The horizon in nanoseconds.
    /// - Returns: The index of the first step whose offset is greater than or equal to the horizon, or `0` when the horizon is zero or negative.
    private func firstStep(atOrAfter horizonNanoseconds: Int64) -> Int {
        guard horizonNanoseconds > 0 else { return 0 }

        let stepDuration = timeline.stepDurationNanoseconds
        // **La estimación se mide desde el ancla, no desde el origen.** Dividir
        // el horizonte entre la duración de Step solo acierta si la rejilla
        // empieza en cero; con una rejilla reanclada daría un índice muy lejano
        // y los ajustes de abajo —pensados para corregir por uno— se volverían
        // un bucle largo dentro del hilo de tiempo real.
        var candidate =
            timeline.anchorStep
            + Int(Double(horizonNanoseconds - timeline.anchorNanoseconds) / stepDuration)

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
