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
public struct NoteEmitter {

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
    public let note: MIDINote
    public let velocity: MIDIVelocity
    public let gateNanoseconds: Int64

    public init(
        channel: MIDIChannel,
        note: MIDINote,
        velocity: MIDIVelocity,
        gateNanoseconds: Int64 = NoteEmitter.provisionalGateNanoseconds
    ) {
        self.channel = channel
        self.note = note
        self.velocity = velocity
        self.gateNanoseconds = gateNanoseconds
    }

    /// Entrega los dos mensajes del pulso, cada uno con su instante de emisión.
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
        atHostTime hostTime: UInt64,
        send: (_ message: MIDIMessage, _ hostTime: UInt64) -> Void
    ) {
        send(.noteOn(channel: channel, note: note, velocity: velocity), hostTime)

        let gateTicks = HostClock.hostTicks(fromNanoseconds: UInt64(max(0, gateNanoseconds)))
        send(
            .noteOff(channel: channel, note: note, velocity: MIDIVelocity(unchecked: 0)),
            hostTime &+ gateTicks
        )
    }
}
