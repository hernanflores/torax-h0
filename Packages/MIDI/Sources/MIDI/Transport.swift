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
    private let handoff: PatternHandoff

    /// Ancla temporal del playhead. Vive aquí y no en el hilo porque el hilo se
    /// crea y se tira en cada Play; el reloj tiene que sobrevivir a eso para que
    /// quien dibuja consulte siempre al mismo sitio.
    private let playheadClock = PlayheadClock()

    private var scheduler: SchedulerThread?

    /// Último material publicado: los dieciséis Tracks.
    ///
    /// Se guarda aparte del handoff porque `load()` puede descartar una lectura,
    /// y arrancar sin material significaría `.everyStep` — una ráfaga a densidad
    /// máxima en lugar del patrón. Aquí siempre hay un Pattern válido.
    private var lastPublishedPattern: Pattern

    public var isPlaying: Bool { scheduler?.isRunning ?? false }

    /// Los dieciséis Tracks vigentes. Cambiarlos mientras suena se hace con
    /// `publish(_:)`.
    public var pattern: Pattern { lastPublishedPattern }

    /// El Track 1, que es el único que la interfaz edita hasta la fase 4.
    ///
    /// Los literales de índice no fallan: el Pattern siempre tiene dieciséis.
    public var track: Track { lastPublishedPattern.track(at: 0)! }

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
            steps: track.shape.steps
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
        self.handoff = PatternHandoff(Pattern().replacing(track, at: 0))
        self.lastPublishedPattern = Pattern().replacing(track, at: 0)
    }

    deinit {
        scheduler?.stop()
    }

    /// Publica un Track nuevo. Se recoge en la ventana siguiente, suene o no.
    ///
    /// > **Puente de la v2, fase 2.** El handoff ya publica los dieciséis
    /// > Tracks, pero quien llama todavía edita uno solo. Se sustituye el Track 1
    /// > y los otros quince se conservan, que es lo que hace que este puente no
    /// > mienta: no reinicia nada. La fase 4 lo cambia por `publish(_:)` de un
    /// > Pattern entero, y esta sobrecarga desaparece.
    public func publish(_ track: Track) {
        publish(lastPublishedPattern.replacing(track, at: 0))
    }

    /// Publica los dieciséis Tracks. Se recogen en la ventana siguiente.
    public func publish(_ pattern: Pattern) {
        lastPublishedPattern = pattern
        handoff.publish(pattern)
    }

    /// Arranca el reloj.
    ///
    /// El hilo se crea aquí y no en `init` para que la reproducción empiece
    /// siempre con un origen de tiempo recién tomado: reutilizar el hilo haría
    /// Starts playback using the currently published track. Subsequent scheduler events are emitted as MIDI notes.
    public func play() {
        guard !isPlaying else { return }

        let thread = SchedulerThread(
            configuration: configuration,
            material: .track((handoff.load() ?? lastPublishedPattern).track(at: 0)!),
            handoff: handoff,
            playhead: playheadClock
        ) {
            [emitter, send, handoff, lastPublishedPattern, tempo = configuration.timeline.tempo]
            track, _, pitch, groove, hostTime in
            // El canal y la duración del Step son del Track que emite: dieciséis
            // Tracks pueden estar en dieciséis canales y en Divisions distintas.
            // Se leen del snapshot vigente, que es el mismo que produjo el
            // evento.
            let pattern = handoff.load() ?? lastPublishedPattern
            guard let source = pattern.track(at: track) else { return }

            emitter.emit(
                pitch: pitch,
                groove: groove,
                on: MIDIChannel(source.channel),
                stepDurationNanoseconds: Int64(
                    MusicalTimeline(tempo: tempo, division: source.shape.division)
                        .stepDurationNanoseconds),
                atHostTime: hostTime,
                send: send
            )
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
    /// **El hueco del pool se cierra con All Notes Off.** Una altura que
    /// estuviera sonando y se hubiera quitado del pool antes de parar no aparece
    /// en el barrido de arriba. Mientras el gate era de 25 ms eso era inaudible
    /// y quedó anotado como pendiente «cuando Sustain permita gates largos».
    /// Sustain llegó: con 200% sobre una Division 1/1 a 20 BPM la nota colgaría
    /// veinticuatro segundos.
    ///
    /// Se manda además un CC 123 (All Notes Off), que apaga lo que el barrido no
    /// conoce. **Los dos y no uno solo**: el CC 123 cubre las alturas que ya no
    /// están en el pool, y el barrido cubre los sintetizadores que ignoran el CC
    /// 123, que los hay. Ninguno de los dos hace redundante al otro.
    ///
    /// La alternativa —que el hilo del scheduler llevara la cuenta de lo que
    /// encendió y no ha apagado— sería más precisa y metería estado mutable en
    /// el camino de tiempo real para resolver un caso de parada. No se paga.
    ///
    /// **Por qué no va sellado en «ahora».** CoreMIDI emite en orden de
    /// timestamp, así que un note-off a 0 saldría *antes* que cualquier note-on
    /// que el hilo moribundo ya hubiera programado con timestamp futuro — es
    /// decir, antes de la nota que este mensaje existe para apagar. Sellarlo una
    /// ventana por delante lo pone detrás de todo lo ya entregado, porque nada
    /// puede estar programado más allá del look-ahead.
    ///
    /// El retraso es el de la ventana, unos milisegundos: por debajo de lo que
    /// Stops playback and silences active notes.
    /// - Sends an All Notes Off message and note-off messages for pitches in the last published track.
    /// - Does nothing when playback is already stopped.
    public func stop() {
        guard let scheduler else { return }
        scheduler.stop()
        self.scheduler = nil

        let silenceAt =
            HostClock.now()
            &+ HostClock.hostTicks(
                fromNanoseconds: UInt64(max(0, configuration.lookAheadNanoseconds)))

        // **Se apaga Track por Track, cada uno por su canal.** Con dieciséis
        // Tracks en hasta dieciséis canales, apagar solo uno dejaría sonando a
        // los otros quince: exactamente el defecto que este método existe para
        // evitar, multiplicado.
        // **Dos pasadas, y el orden importa.** Primero el `all notes off` de
        // cada canal y después los note-off del material: si el sintetizador
        // honra el primero, lo demás es confirmación; si no lo honra, el barrido
        // lo cubre. Mezclarlos dejaría un `all notes off` de un canal detrás del
        // note-off de otro, que es ruido sin orden.
        //
        // Se apaga Track por Track y canal por canal: con dieciséis Tracks en
        // hasta dieciséis canales, apagar solo uno dejaría sonando a los otros
        // quince, que es este mismo defecto multiplicado.
        var silenced: Set<Int> = []
        for index in 0..<Pattern.trackCount {
            guard let source = lastPublishedPattern.track(at: index) else { continue }
            let channel = MIDIChannel(source.channel)

            // No depende de que el Track tenga material **ahora**: vaciar el
            // pool mientras suena deja notas encendidas que ya no están en él, y
            // el barrido del pool no las cubre por definición.
            guard silenced.insert(channel.number).inserted else { continue }
            send(
                .controlChange(
                    channel: channel,
                    controller: MIDIController.allNotesOff,
                    value: 0
                ),
                silenceAt
            )
        }

        for index in 0..<Pattern.trackCount {
            guard let source = lastPublishedPattern.track(at: index) else { continue }
            let channel = MIDIChannel(source.channel)
            let pool = source.pool

            for slot in 0..<pool.count {
                guard let pitch = pool.pitch(at: slot) else { break }
                send(
                    .noteOff(
                        channel: channel,
                        note: MIDINote(unchecked: UInt8(pitch.value)),
                        velocity: MIDIVelocity(unchecked: 0)
                    ),
                    silenceAt
                )
            }
        }
    }
}
