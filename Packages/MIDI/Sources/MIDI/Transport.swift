import Engine

/// Play y stop con reloj interno.
///
/// **Reparto de responsabilidades.** El transporte no calcula tiempo ni decide
/// qué Steps disparan: arranca y para el hilo del scheduler, convierte cada
/// pulso en notas con el `NoteEmitter` y las entrega al camino de envío. La
/// rejilla la lleva `SchedulerThread`, el material `TrackScheduler`.
///
/// **El envío se inyecta.** Recibe un cierre en vez de hablar con
/// `CoreMIDIOutput`, para que play y stop se puedan verificar sin sintetizador y
/// sin CoreMIDI. Quien lo construya en producto le pasa el envío real.
///
/// **Límite conocido.** Parar y volver a arrancar deprisa puede duplicar notas:
/// es la carrera registrada en el track `scheduler-lifecycle_20260826`, que este
/// track no arregla. Es el primero que puede observarla, porque es el primero
/// que tiene transporte.
public final class Transport: @unchecked Sendable {

    /// Se invoca por cada mensaje, desde el hilo del scheduler.
    ///
    /// Quien lo implemente hereda las reglas de tiempo real: sin asignaciones,
    /// sin locks, sin logging.
    public typealias Send = @Sendable (_ message: MIDIMessage, _ hostTime: UInt64) -> Void

    private let configuration: SchedulerConfiguration
    private let emitter: NoteEmitter
    private let send: Send
    private let handoff: TrackHandoff

    private var scheduler: SchedulerThread?

    public var isPlaying: Bool { scheduler?.isRunning ?? false }

    /// Track vigente. Cambiarlo mientras suena se hace con `publish(_:)`.
    public var track: Track? { handoff.load() }

    public init(
        configuration: SchedulerConfiguration,
        track: Track,
        emitter: NoteEmitter,
        send: @escaping Send
    ) {
        self.configuration = configuration
        self.emitter = emitter
        self.send = send
        self.handoff = TrackHandoff(track)
    }

    deinit {
        scheduler?.stop()
    }

    /// Publica un Track nuevo. Se recoge en la ventana siguiente, suene o no.
    public func publish(_ track: Track) {
        handoff.publish(track)
    }

    /// Arranca el reloj.
    ///
    /// El hilo se crea aquí y no en `init` para que la reproducción empiece
    /// siempre con un origen de tiempo recién tomado: reutilizar el hilo haría
    /// que el segundo Play arrancara a mitad del anillo.
    public func play() {
        guard !isPlaying else { return }

        let thread = SchedulerThread(
            configuration: configuration,
            track: handoff.load(),
            handoff: handoff
        ) { [emitter, send] _, hostTime in
            emitter.emit(atHostTime: hostTime, send: send)
        }
        scheduler = thread
        thread.start()
    }

    /// Para el reloj y apaga lo que estuviera sonando.
    ///
    /// **Por qué un note-off inmediato además de los ya sellados.** Cada pulso
    /// entrega su note-off con timestamp futuro, así que lo que ya salió se
    /// apaga solo. Pero parar entre el note-on y su note-off deja esa nota
    /// sonando en el sintetizador hasta que alguien la apague, y no hay nadie
    /// más que vaya a hacerlo: el hilo que la habría apagado es el que se acaba
    /// de detener.
    ///
    /// El timestamp 0 es la convención de CoreMIDI para «ahora», que es lo que
    /// se quiere: parar es un gesto, no un evento de la rejilla.
    public func stop() {
        guard let scheduler else { return }
        scheduler.stop()
        self.scheduler = nil

        send(
            .noteOff(channel: emitter.channel, note: emitter.note, velocity: MIDIVelocity(unchecked: 0)),
            0
        )
    }
}
