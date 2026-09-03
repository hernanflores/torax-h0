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
    /// La mezcla: qué Tracks se oyen.
    ///
    /// **Vive en el transporte y no en el Pattern** porque no es material —ver
    /// la nota del 2026-09-02 en la Pre Spec—, y vive aquí y no en la pantalla
    /// porque quien la lee es el hilo del scheduler, que el transporte arranca.
    ///
    /// **Sobrevive a `stop()`**: parar y volver a arrancar conserva mutes y
    /// solos, porque es mezcla y no transporte.
    ///
    /// **No es pública, y esa es la decisión.** Quien la tocara directamente se
    /// saltaría el apagado de `toggleMute(_:)`, que es justo lo que evita la
    /// nota colgada. Fuera se llega por `mix` para leer y por los dos toggles
    /// para escribir.
    let mutes = MuteMask()

    /// Si se sigue a un maestro externo.
    ///
    /// **Atómica porque la escribe la pantalla y la lee el hilo de recepción de
    /// CoreMIDI**, que atiende el reloj sin saltar al principal. Un `Bool`
    /// desnudo sería una carrera de datos con el compilador de por medio.
    private let followsExternalClock = AtomicFlag(false)

    /// Quién manda el tempo. Por defecto, la app.
    ///
    /// Cambiarlo en caliente es lo que hace el selector de la pantalla `3 ·
    /// MIDI`, y no toca lo que esté sonando: solo decide a quién se hace caso a
    /// partir de ahora.
    public var clockSource: ClockSource {
        get { followsExternalClock.value ? .external : .internal }
        set { followsExternalClock.value = newValue == .external }
    }

    /// Armado: la app pidió sonar y espera el Start del maestro.
    ///
    /// **Es un estado del transporte, no de la pantalla**, porque quien lo mira
    /// para decidir si un Start arranca es el hilo de recepción de CoreMIDI.
    private let armed = AtomicFlag(false)

    /// Si el transporte espera el Start del maestro.
    ///
    /// Sonando ya no está armado: está tocando.
    public var isArmed: Bool { armed.value }

    /// Interno y no privado para que los tests puedan comprobar **contra qué
    /// instante nace la rejilla**, que es lo que el arranque por Start del
    /// maestro cambia.
    let playheadClock = PlayheadClock()

    /// Lo que el scheduler sabe del maestro externo.
    ///
    /// Interno para que los tests puedan leer lo que cruza sin arrancar el
    /// bucle.
    let clockHandoff = ClockHandoff()

    /// Estima el tempo del maestro con sus ticks.
    ///
    /// **Solo lo toca el hilo de recepción de CoreMIDI**, que es de donde llegan
    /// los ticks, así que no necesita protección. La única excepción es
    /// `startPlaying`, que lo reinicia: pasa por el hilo principal, y ahí no hay
    /// reproducción en curso con la que competir.
    private var clockFollower = ClockFollower()

    /// Instante en que arrancó la rejilla, en nanosegundos de host.
    ///
    /// Es contra lo que se mide la fase del maestro. Cero mientras no suene.
    private var gridOriginNanoseconds: Int64 = 0

    /// Suma de las correcciones de fase publicadas desde el arranque.
    private var accumulatedCorrectionNanoseconds: Int32 = 0
    private let cyclePlaybackClock = CyclePlaybackClock()

    private var scheduler: SchedulerThread?

    #if DEBUG
        /// Cuántas veces se ha copiado el snapshot desde que existe el
        /// transporte. Ver `PatternHandoff.loadCount`: existe para que «una
        /// lectura por ventana» sea una propiedad comprobable y no una
        /// intención escrita en un comentario.
        var handoffLoadCount: UInt64 { handoff.loadCount.value }
    #endif

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
    public var track: Cycle { lastPublishedPattern.cycle(at: 0)! }

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

    /// Dónde está el playhead de **cada uno** de los dieciséis, o `nil` con el
    /// transporte parado.
    ///
    /// **Es lo que la pantalla de anillos concéntricos necesita.** `playhead`
    /// resuelve el del primer Track sobre la Division común, que valía cuando el
    /// Pattern era uno; con dieciséis anillos, cada uno cae sobre su propia
    /// rejilla y un playhead compartido mentiría en quince.
    ///
    /// Se calcula al preguntar, por la misma razón que el otro: guardarlo
    /// obligaría a un temporizador de interfaz a refrescarlo, y eso es una
    /// animación no derivada del reloj musical.
    public var playheads: [Playhead]? {
        guard let elapsed = playheadClock.elapsedNanoseconds() else { return nil }
        return Playhead.forEachTrack(
            in: lastPublishedPattern,
            tempo: configuration.timeline.tempo,
            elapsedNanoseconds: elapsed
        )
    }

    /// Por qué Cycle va **cada uno** de los dieciséis, o `nil` con el transporte
    /// parado.
    ///
    /// **Se deduce del reloj anclado a la fase del scheduler.** El hilo que
    /// suena publica una palabra atómica al cambiar de Cycle; `CyclePosition`
    /// combina ese cursor con el reloj real, sin locks y sin confundir el
    /// horizonte de look-ahead con lo que ya está sonando.
    ///
    /// Se calcula al preguntar, por la misma razón que `playheads`: guardarlo
    /// obligaría a un temporizador de interfaz a refrescarlo, y eso es una
    /// animación no derivada del reloj musical.
    public var cyclesInCourse: [CyclePosition]? {
        guard let elapsed = playheadClock.elapsedNanoseconds() else { return nil }
        return cyclePlaybackClock.positions(
            in: lastPublishedPattern, tempo: configuration.timeline.tempo,
            elapsedNanoseconds: elapsed)
    }

    /// Arranca con los dieciséis Tracks.
    public init(
        configuration: SchedulerConfiguration,
        pattern: Pattern,
        emitter: NoteEmitter,
        send: @escaping Send
    ) {
        self.configuration = configuration
        self.emitter = emitter
        self.send = send
        self.handoff = PatternHandoff(pattern)
        self.lastPublishedPattern = pattern
    }

    /// Atajo para quien todavía piensa en un Track: lo pone en la primera
    /// posición y deja los otros quince vacíos.
    public convenience init(
        configuration: SchedulerConfiguration,
        track: Cycle,
        emitter: NoteEmitter,
        send: @escaping Send
    ) {
        self.init(
            configuration: configuration,
            pattern: Pattern().replacing(track, at: 0),
            emitter: emitter,
            send: send
        )
    }

    deinit {
        scheduler?.stop()
    }

    // MARK: - La mezcla

    /// Qué Tracks se oyen ahora mismo.
    public var mix: MuteState { mutes.load() }

    /// Alterna el mute de un Track, y apaga lo que deje de sonar.
    ///
    /// **Es la única puerta.** El gesto táctil y el del controlador entran los
    /// dos por aquí, por la misma razón que la selección de Track: dos caminos
    /// que cambiaran la máscara serían dos sitios donde olvidarse del apagado.
    public func toggleMute(_ index: Int) {
        apply { $0.togglingMute(index) }
    }

    /// Alterna el solo de un Track, y apaga a los que deje fuera.
    public func toggleSolo(_ index: Int) {
        apply { $0.togglingSolo(index) }
    }

    /// Cambia la mezcla y apaga a quien **acaba de** volverse inaudible.
    ///
    /// **El apagado va con la transición, no con el estado.** Se comparan las
    /// dos fotos y se barre solo la diferencia: mutear a quien ya callaba por el
    /// solo de otro no manda nada, y volverse audible tampoco —no hay ninguna
    /// nota que cerrar—. Barrer por estado mandaría un `all notes off` cada vez
    /// que alguien roza un botón.
    ///
    /// **Con el transporte parado no se manda nada**, por lo mismo: no hay nada
    /// sonando. El estado sí cambia, y se nota en cuanto se pulse Play.
    ///
    /// **Fuera del hilo del scheduler** (NFR1): esto es un gesto de usuario, y
    /// corre donde corre `stop()`.
    private func apply(_ change: (MuteState) -> MuteState) {
        let before = mutes.load()
        let after = change(before)
        guard after != before else { return }

        mutes.store(after)

        guard isPlaying else { return }

        var silenced: Set<Int> = []
        for index in 0..<Pattern.trackCount
        where before.isAudible(index) && !after.isAudible(index) {
            silenced.insert(index)
        }
        silence(tracks: silenced, atHostTime: silenceHostTime)
    }

    /// Publica un Track nuevo. Se recoge en la ventana siguiente, suene o no.
    ///
    /// > **Puente de la v2, fase 2.** El handoff ya publica los dieciséis
    /// > Tracks, pero quien llama todavía edita uno solo. Se sustituye el Track 1
    /// > y los otros quince se conservan, que es lo que hace que este puente no
    /// > mienta: no reinicia nada. La fase 4 lo cambia por `publish(_:)` de un
    /// > Pattern entero, y esta sobrecarga desaparece.
    public func publish(_ track: Cycle) {
        publish(lastPublishedPattern.replacing(track, at: 0))
    }

    /// Atiende un mensaje entrante del reloj del maestro.
    ///
    /// Devuelve si el mensaje **era suyo**: los que no lo son siguen su camino
    /// hacia la entrada de control. Consumir de más dejaría los knobs mudos al
    /// elegir `External`.
    ///
    /// **El filtro por fuente está aquí y en un solo sitio.** Con `Internal` no
    /// se consume nada, así que un maestro puede estar mandando Start, Stop y
    /// clock por el mismo puerto del que llegan los knobs sin que pase nada.
    ///
    /// **Lo llama el hilo de recepción de CoreMIDI, sin saltar al principal**, y
    /// con el instante que trae el paquete: el reloj vive de cuándo llegó cada
    /// tick, y una cola de por medio metería su propio retraso en la
    /// estimación.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    @discardableResult
    public func receive(_ message: MIDIMessage, atHostTime hostTime: UInt64) -> Bool {
        guard followsExternalClock.value else { return false }

        switch message {
        case .start:
            // **Solo dispara si la app lo pidió.** El transporte lo decide la
            // app; el maestro decide *cuándo*. Un Start sobre un transporte que
            // nadie armó arrancaría música que nadie pidió.
            if armed.value { startPlaying(atHostTime: hostTime) }
            return true

        case .stop:
            // Simétrico al Start, y por el mismo camino que el botón de la
            // pantalla: `stop()` desarma y hace el barrido de apagado. Parar de
            // otra forma sería tener dos paradas que mantener iguales, y la que
            // se olvidara del barrido dejaría notas colgadas.
            stop()
            return true

        case .timingClock:
            follow(tickAtHostTime: hostTime)
            return true

        case .noteOn, .noteOff, .controlChange:
            return false
        }
    }

    /// Alimenta el estimador con un tick y publica al cerrarse cada negra.
    ///
    /// **Publicar una vez por negra y no por tick es la decisión**: el reloj
    /// entrante tiene su propio jitter, y empujar la rejilla con cada tick lo
    /// trasladaría entero a la salida.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    private func follow(tickAtHostTime hostTime: UInt64) {
        let instant = Int64(HostClock.nanoseconds(fromHostTicks: hostTime))

        guard case .quarterNote(let closing) = clockFollower.receive(tickAtNanoseconds: instant),
            let tempo = clockFollower.tempo
        else { return }

        let quarterNote = 60.0 / tempo.beatsPerMinute * 1_000_000_000.0

        // La fase se mide contra el origen vigente, que es el del arranque más
        // lo ya corregido. Sin sumarlo, cada negra volvería a pedir la misma
        // corrección y la rejilla se pasaría de largo.
        if gridOriginNanoseconds != 0 {
            let origin = gridOriginNanoseconds + Int64(accumulatedCorrectionNanoseconds)
            let correction = PhaseCorrection.nanoseconds(
                gridOriginNanoseconds: origin,
                quarterNoteNanoseconds: quarterNote,
                masterTickNanoseconds: closing,
                limitNanoseconds: Self.phaseCorrectionLimitNanoseconds)
            accumulatedCorrectionNanoseconds &+= Int32(correction)
        }

        clockHandoff.publish(
            quarterNoteNanoseconds: UInt32(quarterNote.rounded()),
            accumulatedCorrectionNanoseconds: accumulatedCorrectionNanoseconds)
    }

    /// Cuánto puede moverse el origen de una vez.
    ///
    /// **Cinco milisegundos por negra.** Acota lo que un tick desviado puede
    /// hacerle a la rejilla —a 120 BPM son diez milisegundos por segundo, de
    /// sobra para recuperar cualquier deriva real— y lo que sobra se corrige en
    /// las negras siguientes en vez de en un salto.
    static let phaseCorrectionLimitNanoseconds: Int64 = 5_000_000

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

        // **Con reloj externo, Play arma y no suena.** Manda un solo transporte:
        // la app pide sonar y el maestro decide cuándo, así que la música
        // empieza con su Start. La pantalla lo enseña como `Waiting for clock`.
        guard clockSource == .internal else {
            // **Armar también olvida al maestro anterior.** Pedir sonar empieza
            // una sesión nueva; lo que se supiera de la anterior no vale, y su
            // fase se medía contra una rejilla que ya no existe. El estimador
            // vuelve a llenarse con los ticks que sigan llegando mientras espera.
            clockFollower.reset()
            clockHandoff.clear()
            accumulatedCorrectionNanoseconds = 0
            armed.value = true
            return
        }

        startPlaying()
    }

    /// Arranca el bucle de verdad.
    ///
    /// **Es el camino único**, venga de `play()` con reloj interno o del Start
    /// del maestro: dos caminos distintos serían dos formas de empezar a sonar
    /// que habría que mantener iguales.
    ///
    /// El origen viene de fuera cuando lo dispara el maestro: la rejilla nace en
    /// el instante de su Start y no cuando este hilo llegue a preguntar la hora.
    ///
    /// Realtime: puede llamarse desde el hilo de recepción de CoreMIDI.
    private func startPlaying(atHostTime origin: UInt64? = nil) {
        armed.value = false

        // **Arrancar olvida al maestro anterior.** Su tempo no dice nada del
        // siguiente, y su fase mucho menos: la rejilla nace ahora.
        clockFollower.reset()
        clockHandoff.clear()
        accumulatedCorrectionNanoseconds = 0
        gridOriginNanoseconds = Int64(
            HostClock.nanoseconds(fromHostTicks: origin ?? HostClock.now()))

        // Los dieciséis con los que se arranca, leídos una sola vez: el
        // scheduler construye con ellos **una rejilla por Track**, cada una con
        // su Division. Sin pasarlos, el hilo caía en la vía del arnés —una sola
        // rejilla, la de la configuración— y los quince restantes sonaban sobre
        // la Division del primero.
        let starting = handoff.load() ?? lastPublishedPattern

        let thread = SchedulerThread(
            configuration: configuration,
            material: .cycle(starting.cycle(at: 0)!),
            handoff: handoff,
            playhead: playheadClock,
            cyclePlaybackClock: cyclePlaybackClock,
            pattern: starting,
            mutes: mutes,
            clock: clockHandoff
        ) {
            [emitter, send, tempo = configuration.timeline.tempo, clockHandoff]
            _, source, _, pitch, groove, hostTime in
            // El canal y la duración del Step son del Track que emite: dieciséis
            // Tracks pueden estar en dieciséis canales y en Divisions distintas.
            //
            // **Llegan con el evento, no se releen.** Antes se volvía al
            // snapshot por cada nota para buscarlos, que con 2,25 KB era
            // invisible y con Cycles sería una copia de decenas de kilobytes por
            // nota dentro del hilo de tiempo real. El scheduler ya lo tiene
            // recogido una vez por ventana, así que lo entrega: además de barato
            // es lo que garantiza que el canal sea el del **mismo** snapshot que
            // produjo el evento.
            emitter.emit(
                pitch: pitch,
                groove: groove,
                on: MIDIChannel(source.channel),
                // **La duración se escala con el maestro.** Se calcula contra
                // el tempo de referencia, como los instantes, y se convierte a
                // tiempo de reloj: sin esto, seguir a un maestro lento dejaría
                // los gates con la longitud del tempo viejo y Sustain sonaría
                // corto.
                //
                // Es una lectura atómica por nota y no una por ventana, a
                // diferencia del resto. Se acepta: aquí lo que se decide es
                // cuánto dura la nota, no cuándo cae, y un cambio de tempo a
                // media ventana como mucho la alarga o acorta lo que el maestro
                // acaba de pedir.
                stepDurationNanoseconds: clockHandoff.reading.wallNanoseconds(
                    forGridNanoseconds: Int64(
                        MusicalTimeline(tempo: tempo, division: source.shape.division)
                            .stepDurationNanoseconds),
                    referenceQuarterNoteNanoseconds: 60.0 / tempo.beatsPerMinute * 1_000_000_000.0),
                atHostTime: hostTime,
                send: send
            )
        }
        scheduler = thread
        thread.start(atHostTime: origin)
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
        // **Desarmar también es parar.** Con reloj externo, Play deja el
        // transporte esperando el Start; Stop tiene que deshacer eso aunque no
        // hubiera empezado a sonar, o el maestro arrancaría música que la app ya
        // no pide.
        armed.value = false
        gridOriginNanoseconds = 0

        guard let scheduler else { return }
        scheduler.stop()
        self.scheduler = nil

        // **Parar es apagar los doce.** El ámbito es lo único que distingue esto
        // de silenciar un Track al mutearlo: el procedimiento —`all notes off`
        // por canal y después el barrido de alturas— es el mismo, y está escrito
        // una sola vez en `silence(tracks:atHostTime:)`.
        silence(tracks: Set(0..<Pattern.trackCount), atHostTime: silenceHostTime)
    }

    /// Cuándo sellar un apagado: una ventana por delante.
    ///
    /// **Por qué no «ahora».** CoreMIDI emite en orden de timestamp, así que un
    /// note-off a 0 saldría *antes* que cualquier note-on que el hilo ya hubiera
    /// programado con timestamp futuro — es decir, antes de la nota que existe
    /// para apagar. Sellarlo una ventana por delante lo pone detrás de todo lo
    /// ya entregado, porque nada puede estar programado más allá del look-ahead.
    ///
    /// El retraso es el de la ventana, unos milisegundos.
    var silenceHostTime: UInt64 {
        HostClock.now()
            &+ HostClock.hostTicks(
                fromNanoseconds: UInt64(max(0, configuration.lookAheadNanoseconds)))
    }

    /// Apaga lo que esos Tracks tuvieran sonando.
    ///
    /// **Dos pasadas, y el orden importa.** Primero el `all notes off` de cada
    /// canal implicado y después los note-off del material: si el sintetizador
    /// honra el primero, lo demás es confirmación; si no lo honra —que los hay—,
    /// el barrido lo cubre. Mezclarlos dejaría un `all notes off` de un canal
    /// detrás del note-off de otro, que es ruido sin orden.
    ///
    /// **Se barren los dieciséis Cycles de cada Track, no solo el vigente.** El
    /// cursor de reproducción vive en el hilo del scheduler, así que desde aquí
    /// no se sabe cuál estaba sonando: saberlo exigiría que ese hilo publicara
    /// algo en cada vuelta, y eso es trabajo en el camino de tiempo real para
    /// resolver un caso de parada. El `cursor` del snapshot no sirve — es el de
    /// edición, y puede apuntar a cualquier sitio.
    ///
    /// Tampoco se barren solo los activos: bajar el número mientras suena deja
    /// el cursor fuera del rango a propósito (FR9 de `cycles`), así que un Cycle
    /// que ya no se recorre puede ser justo el que está sonando.
    ///
    /// **El barrido de alturas no depende de que el Cycle tenga material
    /// ahora:** vaciar el pool mientras suena deja notas encendidas que ya no
    /// están en él, y por eso el `all notes off` de la primera pasada no es
    /// redundante.
    ///
    /// **Un canal compartido se apaga entero, y con él los Tracks que lo
    /// comparten.** El `all notes off` es un mensaje de canal: no existe forma
    /// de apagar «lo del Track 3» si el Track 4 emite por el mismo sitio. El
    /// otro Track vuelve en su siguiente pulso —no queda mudo—, y la pantalla
    /// MIDI existe para ver un choque de canales antes de que ocurra.
    func silence(tracks: Set<Int>, atHostTime silenceAt: UInt64) {
        guard !tracks.isEmpty else { return }

        var silenced: Set<Int> = []
        for index in tracks.sorted() {
            guard let track = lastPublishedPattern.track(at: index) else { continue }

            for slot in 0..<Track.cycleCount {
                guard let cycle = track.cycle(at: slot) else { continue }
                let channel = MIDIChannel(cycle.channel)

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
        }

        // Sin repetir un par canal+altura: doce Tracks por dieciséis Cycles por
        // ocho alturas serían dos mil mensajes, y en la práctica casi todos son
        // el mismo.
        var swept: Set<Int> = []
        for index in tracks.sorted() {
            guard let track = lastPublishedPattern.track(at: index) else { continue }

            for slot in 0..<Track.cycleCount {
                guard let cycle = track.cycle(at: slot) else { continue }
                let channel = MIDIChannel(cycle.channel)
                let pool = cycle.pool

                for poolSlot in 0..<pool.count {
                    guard let pitch = pool.pitch(at: poolSlot) else { break }
                    guard swept.insert(channel.number << 8 | pitch.value).inserted else {
                        continue
                    }
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
}
