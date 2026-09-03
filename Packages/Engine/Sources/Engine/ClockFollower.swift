/// Qué pasó al recibir un tick del reloj externo.
public enum ClockTick: Equatable, Sendable {

    /// El tick cae dentro de la negra en curso. No hay nada nuevo que decidir.
    case pending

    /// El tick cierra una negra, en el instante que lleva dentro.
    ///
    /// Es el instante contra el que se corrige la fase: el maestro dice «aquí
    /// cae el pulso», y la rejilla se compara con eso.
    case quarterNote(atNanoseconds: Int64)
}

/// Sigue un reloj MIDI externo y estima su tempo.
///
/// **Promedia la negra entera, no el intervalo suelto.** Un reloj MIDI manda 24
/// ticks por negra, y el intervalo entre dos ticks consecutivos lleva encima
/// todo el jitter del cable: creérselo daría un tempo que baila. Aquí se mide de
/// negra a negra —24 intervalos— y el error de un tick se reparte entre los 24.
///
/// **Por eso el tempo se actualiza una vez por negra y no antes.** Es la
/// latencia declarada del modo esclavo: un cambio del maestro tarda hasta una
/// negra en verse, y la spec del track lo registra como limitación conocida.
///
/// **No guarda ventana.** Le basta el instante en que se cerró la negra anterior
/// y cuántos ticks van desde entonces: dos enteros. No hace falta recordar los
/// 24 instantes intermedios para promediarlos, porque la media de 24 intervalos
/// contiguos **es** la distancia entre los extremos partida por 24. Además de
/// ahorrar estado, deja el tipo trivial, que es lo que exige alimentarlo desde
/// el callback de recepción de CoreMIDI.
///
/// **Un tempo fuera de `Tempo.validRange` se rechaza, no se acota.** Acotar en
/// silencio mostraría 300 BPM sin que nada lo explique; rechazar conserva el
/// último tempo bueno y deja la marca para que la pantalla lo diga.
///
/// No conoce el tiempo de host ni la plataforma: recibe instantes en
/// nanosegundos y por eso vive en `Engine`.
public struct ClockFollower: Equatable, Sendable {

    /// Ticks por negra que define la especificación MIDI.
    public static let ticksPerQuarterNote = 24

    /// Instante en que se cerró la última negra, o el del primer tick recibido.
    private var anchorNanoseconds: Int64

    /// Ticks recibidos desde el ancla.
    private var ticksSinceAnchor: Int

    /// Si el ancla ya existe. Sin ella no hay nada contra lo que medir.
    private var isAnchored: Bool

    /// Tempo estimado, o `nil` mientras no se haya cerrado ninguna negra con un
    /// valor válido.
    public private(set) var tempo: Tempo?

    /// Si la última negra cerrada dio un tempo fuera de rango.
    ///
    /// Describe la negra vigente, no la historia: volver al rango lo limpia.
    public private(set) var isOutOfRange: Bool

    public init() {
        anchorNanoseconds = 0
        ticksSinceAnchor = 0
        isAnchored = false
        tempo = nil
        isOutOfRange = false
    }

    /// Olvida lo aprendido. Se llama al arrancar el transporte: el maestro
    /// anterior no dice nada del siguiente.
    public mutating func reset() {
        self = ClockFollower()
    }

    /// Recibe un tick del maestro y devuelve si con él se cerró una negra.
    ///
    /// El primer tick tras `init()` o `reset()` fija el ancla y no estima nada.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    @discardableResult
    public mutating func receive(tickAtNanoseconds instant: Int64) -> ClockTick {
        guard isAnchored else {
            anchorNanoseconds = instant
            ticksSinceAnchor = 0
            isAnchored = true
            return .pending
        }

        ticksSinceAnchor += 1
        guard ticksSinceAnchor >= Self.ticksPerQuarterNote else { return .pending }

        estimate(quarterNoteClosingAt: instant)
        anchorNanoseconds = instant
        ticksSinceAnchor = 0
        return .quarterNote(atNanoseconds: instant)
    }

    /// Convierte la duración de la negra recién cerrada en tempo.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    private mutating func estimate(quarterNoteClosingAt instant: Int64) {
        let quarterNoteNanoseconds = Double(instant - anchorNanoseconds)
        guard quarterNoteNanoseconds > 0 else {
            isOutOfRange = true
            return
        }

        let beatsPerMinute = 60.0 * 1_000_000_000.0 / quarterNoteNanoseconds
        guard let estimated = Tempo(beatsPerMinute: beatsPerMinute) else {
            isOutOfRange = true
            return
        }

        tempo = estimated
        isOutOfRange = false
    }
}
