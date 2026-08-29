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

    /// Ancla temporal del playhead. Vive aquí y no en el hilo porque el hilo se
    /// crea y se tira en cada Play; el reloj tiene que sobrevivir a eso para que
    /// quien dibuja consulte siempre al mismo sitio.
    private let playheadClock = PlayheadClock()

    private var scheduler: SchedulerThread?

    /// Último Track publicado.
    ///
    /// Se guarda aparte del handoff porque `load()` puede descartar una lectura,
    /// y arrancar sin Track significaría `.everyStep` — una ráfaga a densidad
    /// máxima en lugar del patrón. Aquí siempre hay un Track válido.
    private var lastPublishedTrack: Track

    public var isPlaying: Bool { scheduler?.isRunning ?? false }

    /// Track vigente. Cambiarlo mientras suena se hace con `publish(_:)`.
    public var track: Track { lastPublishedTrack }

    /// Dónde está el playhead sobre el anillo, o `nil` con el transporte
    /// parado.
    ///
    /// **Se calcula al preguntar, no se guarda.** Guardarlo obligaría a alguien
    /// a refrescarlo, y ese alguien sería un temporizador de la interfaz — una
    /// animación no derivada del reloj musical, que `product-guidelines.md`
    /// nombra como antipatrón. Aquí el reloj es la única fuente: quien dibuja
    /// pregunta cuando va a dibujar y siempre obtiene el instante real.
    ///
    /// La aritmética vive en `Engine`, donde se testea sin CoreMIDI; esto solo
    /// le pasa el tiempo transcurrido y el anillo sobre el que resolverlo.
    public var playhead: Playhead? {
        guard let elapsed = playheadClock.elapsedNanoseconds() else { return nil }
        return Playhead(
            elapsedNanoseconds: elapsed,
            timeline: configuration.timeline,
            steps: lastPublishedTrack.shape.steps
        )
    }

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
        self.lastPublishedTrack = track
    }

    deinit {
        scheduler?.stop()
    }

    /// Publica un Track nuevo. Se recoge en la ventana siguiente, suene o no.
    public func publish(_ track: Track) {
        lastPublishedTrack = track
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
            material: .track(handoff.load() ?? lastPublishedTrack),
            handoff: handoff,
            playhead: playheadClock
        ) { [emitter, send] _, pitch, groove, hostTime in
            emitter.emit(pitch: pitch, groove: groove, atHostTime: hostTime, send: send)
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
    /// **Con Tonal ya no basta con una altura.** Se apagan todas las del pool
    /// vigente, porque cualquiera de ellas pudo ser la última en sonar y desde
    /// aquí no se sabe cuál fue — saberlo exigiría que el hilo del scheduler
    /// publicara algo por cada pulso, y eso es trabajo en el camino de tiempo
    /// real para resolver un caso de parada.
    ///
    /// Queda un hueco conocido: una altura que estuviera sonando y se hubiera
    /// quitado del pool antes de parar no se apaga aquí. Dura lo que el gate,
    /// hoy 25 ms, así que es inaudible; cuando Sustain permita gates largos hay
    /// que volver a mirarlo.
    ///
    /// **Por qué no va sellado en «ahora».** CoreMIDI emite en orden de
    /// timestamp, así que un note-off a 0 saldría *antes* que cualquier note-on
    /// que el hilo moribundo ya hubiera programado con timestamp futuro — es
    /// decir, antes de la nota que este mensaje existe para apagar. Sellarlo una
    /// ventana por delante lo pone detrás de todo lo ya entregado, porque nada
    /// puede estar programado más allá del look-ahead.
    ///
    /// El retraso es el de la ventana, unos milisegundos: por debajo de lo que
    /// se percibe como respuesta al botón.
    public func stop() {
        guard let scheduler else { return }
        scheduler.stop()
        self.scheduler = nil

        let silenceAt =
            HostClock.now()
            &+ HostClock.hostTicks(
                fromNanoseconds: UInt64(max(0, configuration.lookAheadNanoseconds)))

        let pool = lastPublishedTrack.pool
        for index in 0..<pool.count {
            guard let pitch = pool.pitch(at: index) else { break }
            send(
                .noteOff(
                    channel: emitter.channel,
                    note: MIDINote(unchecked: UInt8(pitch.value)),
                    velocity: MIDIVelocity(unchecked: 0)
                ),
                silenceAt
            )
        }
    }
}
