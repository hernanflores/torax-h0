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

    public init() {}

    /// Entrega los dos mensajes del pulso, cada uno con su instante de emisión.
    ///
    /// **Ya no queda nada constante en el emisor: todo sale del `Cycle`.** La
    /// altura llegó con Tonal, la Velocity con Groove, y en la v2 el canal y la
    /// duración del Step, que eran lo último que quedaba.
    ///
    /// Los dos dejaron de poder fijarse al construir por la misma razón: son de
    /// cada Track. El canal se edita en pantalla mientras suena, y la duración
    /// del Step depende de la Division, que ahora es de cada uno — así que
    /// dieciséis Tracks tienen hasta dieciséis duraciones distintas sobre el
    /// mismo tempo.
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
        on channel: MIDIChannel,
        stepDurationNanoseconds: Int64,
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
