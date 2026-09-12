import Engine

/// Decide qué pulsos de clock entran en la ventana futura que se entrega a
/// CoreMIDI.
///
/// **Es el `LookAheadScheduler` del pulso.** La app emite 24 pulsos por negra
/// como maestro (`midi-clock-master_20260911`), y esos pulsos viajan por el
/// mismo camino que las notas: se calculan por adelantado dentro del horizonte y
/// salen sellados con su timestamp de entrega, para que **el jitter no dependa
/// de cuándo despierta el hilo del scheduler**. Reenviar el tick entrante al
/// vuelo es la alternativa que `tech-stack.md` descarta por escrito.
///
/// **Por qué devuelve un rango y no eventos.** `advance(toHorizon:)` devuelve un
/// `Range<Int>` de índices de tick: dos enteros. No hay array que construir, así
/// que la regla «sin asignaciones en el hilo del scheduler» se cumple por
/// construcción.
///
/// **Invariante.** Sobre llamadas sucesivas cada tick se emite exactamente una
/// vez: los rangos son contiguos y nunca retroceden. Un tick duplicado adelanta
/// al esclavo y uno perdido lo retrasa, y las dos cosas se acumulan.
///
/// **El offset se multiplica desde el ancla, nunca se acumula.** Un tick dura
/// 20,83 ms a 120 BPM, así que sumar la duración tick a tick arrastraría el
/// redondeo hasta separar el pulso del maestro sin que ninguna ventana lo
/// notara. Multiplicando, el error queda acotado a un redondeo por ancla — la
/// misma disciplina que `MusicalTimeline` sigue con los Steps.
public struct ClockPulseScheduler: Equatable, Sendable {

    /// Los pulsos por negra que manda MIDI 1.0. No es un ajuste: es el
    /// protocolo.
    public static let pulsesPerQuarterNote = 24

    /// Duración de la negra vigente, en nanosegundos.
    private var quarterNoteNanoseconds: Double

    /// Índice del tick en el que está anclada la rejilla, y el instante que le
    /// corresponde. Sin reanclajes son `0` y `0`, que es la rejilla de siempre.
    private var anchorTick: Int
    private var anchorNanoseconds: Int64

    /// Primer tick aún no entregado. Marca de agua que solo avanza.
    public private(set) var nextTick: Int

    public init(tempo: Tempo, startingAtTick startingTick: Int = 0) {
        quarterNoteNanoseconds = 60.0 / tempo.beatsPerMinute * 1_000_000_000.0
        anchorTick = startingTick
        anchorNanoseconds = 0
        nextTick = startingTick
    }

    /// Cuánto separa a dos ticks consecutivos con el tempo vigente.
    private var tickDurationNanoseconds: Double {
        quarterNoteNanoseconds / Double(Self.pulsesPerQuarterNote)
    }

    /// Instante en que cae un tick, medido desde el origen de la rejilla.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func nanosecondOffset(forTick tick: Int) -> Int64 {
        anchorNanoseconds
            &+ Int64((Double(tick - anchorTick) * tickDurationNanoseconds).rounded())
    }

    /// Cambia el tempo **sin mover la marca de agua**, anclando la rejilla nueva
    /// en el tick aún no entregado.
    ///
    /// **Por qué el ancla es `nextTick`.** Ese tick todavía no cabía en ninguna
    /// ventana, así que su instante está por delante del horizonte ya servido:
    /// anclar ahí es lo que hace imposible que un cambio de tempo produzca un
    /// pulso para un instante que ya pasó. Es el mismo criterio con el que
    /// `LookAheadScheduler.rebase(to:)` ancla los Steps.
    ///
    /// **Lo ya entregado no se reescribe.** Los ticks que salieron llevan su
    /// timestamp sellado y CoreMIDI los va a emitir donde dijeron; el tempo nuevo
    /// se oye en la ventana siguiente.
    ///
    /// **Reanclar sobre el mismo tempo no mueve nada**, así que quien llama no
    /// tiene que acordarse de si ya reancló.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func rebase(to tempo: Tempo) {
        anchorNanoseconds = nanosecondOffset(forTick: nextTick)
        anchorTick = nextTick
        quarterNoteNanoseconds = 60.0 / tempo.beatsPerMinute * 1_000_000_000.0
    }

    /// Devuelve los ticks que caen antes de `horizonNanoseconds` y no se hayan
    /// entregado ya.
    ///
    /// El límite superior es exclusivo: un tick que caiga exactamente en el
    /// horizonte sale en la ventana siguiente, para que el solape entre ventanas
    /// consecutivas no pueda emitirlo dos veces.
    ///
    /// Un horizonte que no avanza —o que retrocede, o que es negativo mientras
    /// corre el presupuesto de adelanto de Delay— devuelve un rango vacío.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func advance(toHorizon horizonNanoseconds: Int64) -> Range<Int> {
        let upperBound = firstTick(atOrAfter: horizonNanoseconds)
        guard upperBound > nextTick else { return nextTick..<nextTick }

        let range = nextTick..<upperBound
        nextTick = upperBound
        return range
    }

    /// Índice del primer tick cuyo instante es mayor o igual que el horizonte.
    ///
    /// Se estima dividiendo y se corrige con un ajuste acotado, igual que en
    /// `LookAheadScheduler`: el coste es constante aunque el horizonte salte
    /// varias negras. El ajuste existe porque los instantes están redondeados a
    /// nanosegundos enteros y la estimación puede fallar por uno.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    private func firstTick(atOrAfter horizonNanoseconds: Int64) -> Int {
        guard horizonNanoseconds > 0 else { return 0 }

        // **La estimación se mide desde el ancla, no desde el origen.** Con una
        // rejilla reanclada, dividir el horizonte entre la duración de tick daría
        // un índice muy lejano y los ajustes de abajo —pensados para corregir por
        // uno— se volverían un bucle largo dentro del hilo de tiempo real.
        var candidate =
            anchorTick
            + Int(Double(horizonNanoseconds - anchorNanoseconds) / tickDurationNanoseconds)

        while nanosecondOffset(forTick: candidate) < horizonNanoseconds {
            candidate += 1
        }
        while candidate > 0, nanosecondOffset(forTick: candidate - 1) >= horizonNanoseconds {
            candidate -= 1
        }

        return candidate
    }
}
