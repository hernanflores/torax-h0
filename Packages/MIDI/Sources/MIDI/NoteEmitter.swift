import Engine

/// Convierte un pulso en el par de mensajes que lo hace sonar.
///
/// **Un pulso no es una nota.** Es una posición del anillo que dispara; hacerla
/// sonar exige note-on y note-off. Sin el segundo la nota queda colgada en el
/// sintetizador, que es lo que pasa si se entrega solo el disparo.
///
/// **El note-off va sellado, no programado.** Se entrega en la misma llamada que
/// el note-on, con su propio instante de emisión futuro, y viaja por el mismo
/// camino. La alternativa —un temporizador o un sleep que lo envíe más tarde—
/// reintroduciría exactamente el jitter que la arquitectura de look-ahead
/// evita: la precisión la da el timestamp, no el momento del envío.
public struct NoteEmitter: Equatable, Sendable {

    /// Duración del gate mientras no exista Sustain.
    ///
    /// **Es una constante provisional, no un valor musical.** Sustain es un
    /// parámetro de Groove y está fuera de esta rebanada; cuando llegue,
    /// sustituye a esto y su default es una Division completa (Pre Spec).
    ///
    /// El valor sale de una restricción, no de un criterio estético: el gate
    /// tiene que caber dentro del Step más corto que el producto puede producir
    /// —50 ms, a 300 BPM con Division 1/16— o el note-off de un pulso llegaría
    /// después del note-on del siguiente y ambos se solaparían en la misma
    /// altura. 25 ms deja la mitad de margen. Hay un test que lo vigila.
    public static let provisionalGateNanoseconds: Int64 = 25_000_000

    public let channel: MIDIChannel
    public let gateNanoseconds: Int64

    public init(
        channel: MIDIChannel,
        gateNanoseconds: Int64 = NoteEmitter.provisionalGateNanoseconds
    ) {
        self.channel = channel
        self.gateNanoseconds = gateNanoseconds
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
    /// Sin asignaciones, sin locks, sin await.
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

        let gateTicks = HostClock.hostTicks(fromNanoseconds: UInt64(max(0, gateNanoseconds)))
        send(
            .noteOff(channel: channel, note: note, velocity: MIDIVelocity(unchecked: 0)),
            hostTime &+ gateTicks
        )
    }
}
