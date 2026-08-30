import Engine

/// Convierte un pulso en el par de mensajes que lo hace sonar.
///
/// **Un pulso no es una nota.** Es una posición del anillo que dispara; hacerla
/// sonar exige note-on y note-off. Sin el segundo la nota queda colgada en el
/// sintetizador, que es lo que pasa si se entrega solo el disparo.
///
/// **La duración sale de Sustain, no de una constante.** Hasta la rebanada 5 el
/// gate era un valor fijo de 25 ms cuya razón era una restricción —que cupiera
/// en el Step más corto— y no un criterio musical. Ahora es un porcentaje de la
/// Division, que es lo que la Pre Spec pone en su sitio, y el solape deja de ser
/// un accidente a evitar para pasar a ser algo que el usuario pide.
///
/// **El solape no se vigila.** Si una altura vuelve a dispararse antes de que
/// termine su gate, los dos note-off llegan cuando les toca y el primero apaga
/// la nota del segundo. Es una limitación conocida y acotada —el tope de 200%
/// la limita a un solo vecino—, documentada en el spec del track
/// `mvp-groove-static_20260829`. Rastrear notas pendientes exigiría estado
/// mutable en el camino de tiempo real, y no se paga por un caso que solo
/// aparece con un pool de una nota.
///
/// **El note-off va sellado, no programado.** Se entrega en la misma llamada que
/// el note-on, con su propio instante de emisión futuro, y viaja por el mismo
/// camino. La alternativa —un temporizador o un sleep que lo envíe más tarde—
/// reintroduciría exactamente el jitter que la arquitectura de look-ahead
/// evita: la precisión la da el timestamp, no el momento del envío.
public struct NoteEmitter: Equatable, Sendable {

    public let channel: MIDIChannel

    /// Cuánto dura un Step, que es contra lo que Sustain se mide.
    ///
    /// **Se fija al construir y no llega por pulso.** La duración del Step
    /// depende del tempo y de la Division, y ninguno de los dos puede cambiar
    /// mientras suena: `TrackScheduler` documenta que la rejilla la fija la
    /// `MusicalTimeline` con la que se construye y no se vuelve a leer. Pasarlo
    /// en cada pulso sugeriría una flexibilidad que el resto del diseño no
    /// tiene.
    public let stepDurationNanoseconds: Int64

    public init(channel: MIDIChannel, stepDurationNanoseconds: Int64) {
        self.channel = channel
        self.stepDurationNanoseconds = stepDurationNanoseconds
    }

    /// Entrega los dos mensajes del pulso, cada uno con su instante de emisión.
    ///
    /// **La altura y la Velocity llegan por parámetro y ya no son del emisor.**
    /// Las dos fueron constantes que este tipo documentaba como provisionales:
    /// la altura hasta Tonal, la Velocity hasta Groove. Ahora las dos salen del
    /// `Track`, que es lo único que el hilo del scheduler lee. El canal sigue
    /// siendo constante — es ajuste de Setup, no un parámetro generativo, y
    /// llega con el preset del BeatStep Pro.
    ///
    /// **Sin altura no se emite nada.** Un pool vacío es un estado válido: el
    /// Track dispara sus Pulses y no tiene material. No se manda un note-on
    /// huérfano ni un note-off suelto — no suena, y ya está.
    ///
    /// `send` recibe primero el note-on, sellado en `hostTime`, y después el
    /// note-off, sellado un gate más tarde. El cierre no escapa, así que no hay
    /// nada que asignar para llamarlo.
    ///
    /// La velocity del note-off es 0 y no la del note-on: es la convención de
    /// MIDI 1.0 para el apagado, y la que entienden todos los sintetizadores.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Emits a MIDI note-on and its sustain-derived note-off for a pitch.
    /// - Parameters:
    ///   - pitch: The pitch to emit, or `nil` to emit nothing.
    ///   - groove: The velocity and sustain settings for the note.
    ///   - hostTime: The host clock time for the note-on.
    ///   - send: A callback that receives each MIDI message and its host clock time.
    public func emit(
        pitch: Pitch?,
        groove: Groove,
        atHostTime hostTime: UInt64,
        send: (_ message: MIDIMessage, _ hostTime: UInt64) -> Void
    ) {
        guard let pitch else { return }

        // `Pitch` y `MIDINote` comparten el rango 0–127 por definición del
        // protocolo, así que la conversión no puede fallar. Se hace aquí, en la
        // capa que conoce los dos tipos: `Engine` no importa CoreMIDI y no
        // debería.
        let note = MIDINote(unchecked: UInt8(pitch.value))

        // `Velocity` y `MIDIVelocity` comparten rango por construcción —el tipo
        // del motor se validó contra el del protocolo—, así que la conversión no
        // puede fallar. Se hace aquí, en la capa que conoce los dos tipos.
        let velocity = MIDIVelocity(unchecked: UInt8(groove.velocity.value))

        send(.noteOn(channel: channel, note: note, velocity: velocity), hostTime)

        let gateTicks = HostClock.hostTicks(
            fromNanoseconds: UInt64(
                max(0, groove.sustain.gateNanoseconds(forStep: stepDurationNanoseconds))))
        send(
            .noteOff(channel: channel, note: note, velocity: MIDIVelocity(unchecked: 0)),
            hostTime &+ gateTicks
        )
    }
}
