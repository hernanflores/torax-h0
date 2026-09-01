import CoreMIDI
import Engine
import MIDI
import Observation

/// Estado de la pantalla de transporte.
///
/// **Es una capa fina a propósito.** Toda la lógica que merece test vive en los
/// paquetes: el reparto y su texto en `Engine`, la selección de destino, la
/// desconexión y el transporte en `MIDI`. Aquí solo se cablean, porque el
/// proyecto de app no tiene target de test y la máquina no tiene runtime de
/// simulador (`conductor/workflow.md`). Cuanto menos haya en esta capa, menos
/// código queda sin cubrir.
/// **Aislado al hilo principal.** Es donde vive el estado que lee la interfaz, y
/// además lo que permite capturarlo desde el callback de CoreMIDI: una clase
/// `@MainActor` es `Sendable`, así que el cierre de recepción puede referirla
/// sin romper las garantías de concurrencia.
@Observable
@MainActor
final class TransportModel {

    /// Configuración del Track con la que arranca la app.
    ///
    /// **Fija, y no editable por ninguna vía.** Es el estado «sin controlador
    /// conectado» que `product-guidelines.md` especifica: solo lectura y
    /// transporte. Un slider provisional para Steps o Pulses sería el
    /// antipatrón que ese documento nombra —parámetros generativos que solo
    /// existen en pantalla— y habría que desmontarlo después. La entrada de
    /// control llega en el track siguiente.
    ///
    /// 16/5 porque es uno de los casos de la Pre Spec y se reconoce de oído:
    /// equilibrado pero asimétrico.
    static let initialShape: Shape = {
        // Steps 16 y Pulses 5 son literales dentro de rango, así que el
        // desempaquetado no puede fallar. Es el único sitio de la app que lo
        // hace, y por eso lleva esta justificación (`swift.md`).
        let steps = Steps(16)!
        return Shape(steps: steps, pulses: Pulses(5)!)
    }()

    /// El marco tonal del Track seleccionado. Configuración táctil, no de knob
    /// (`product-guidelines.md`), y **de cada Track** desde la v2.
    var frame: TonalFrame { track.frame }

    /// La superficie de pads del Track seleccionado: qué altura tiene cada pad
    /// ahora mismo.
    ///
    /// Se calcula del Track, que es donde viven el marco y el registro: guardarla
    /// aparte sería un segundo sitio donde pueden discrepar.
    var surface: PadSurface { PadSurface(frame: track.frame, octaveShift: track.padOctaveShift) }

    /// Cambia Scale o Root y reencuadra el pool.
    ///
    /// **Sigue disponible sin controlador conectado:** es configuración, no
    /// material generativo, y la frontera de `product-guidelines.md` la pone del
    /// lado de la pantalla.
    func setFrame(_ updated: TonalFrame) {
        controlInput.setFrame(updated)
        syncFromControlInput()
    }

    /// Cambia el canal del Track seleccionado.
    ///
    /// Táctil, como Scale y Root: es configuración y no material generativo.
    func setChannel(_ channel: Channel) {
        controlInput.setChannel(channel)
        syncFromControlInput()
    }

    /// Selecciona un Track desde la pantalla.
    ///
    /// **Hace lo mismo que su step button.** Sin controlador conectado es la
    /// única vía, y con controlador las dos tienen que coincidir o la pantalla
    /// mentiría.
    func selectTrack(_ index: Int) {
        controlInput.selectTrack(index)
        syncFromControlInput()
    }

    /// Copia el estado de la entrada de control al modelo observable.
    ///
    /// Es un solo sitio a propósito: cada camino que edita —knob, pad, pantalla—
    /// termina aquí, y así no hay ninguno que se olvide de refrescar la mitad.
    private func syncFromControlInput() {
        pattern = controlInput.pattern
        selectedTrackIndex = controlInput.selectedTrackIndex
    }

    /// Con qué material arranca la app.
    ///
    /// **Una sola altura, que es la que sonaba antes de Tonal.** La Pre Spec
    /// describe el pool de una nota como «centro estable», así que es un estado
    /// legítimo y no un relleno.
    ///
    /// Arrancar con el pool vacío también sería válido —el Track dispara y no
    /// tiene material— pero la app abriría muda, y averiguar que hay que pulsar
    /// un pad para que suene no es algo que la pantalla comunique todavía.
    static let initialPool = PitchPool().inserting(Pitch(48)!)

    /// El emisor, que ya no lleva nada dentro.
    ///
    /// > **Cambio de la v2.** Llevaba el canal —6, fijo— y la duración del Step.
    /// > Los dos pasan a salir del Track en cada pulso: el canal porque cada
    /// > Track tiene el suyo, y la duración porque cada Track tiene su Division.
    /// > **Lo que se oye cambia**: el Track 1 emite ahora por el canal 1 y no
    /// > por el 6, así que el sintetizador hay que ponerlo en el canal del Track
    /// > —o cambiarle el canal al Track—.
    private static func voice() -> NoteEmitter { NoteEmitter() }

    /// 120 BPM está dentro del rango válido de `Tempo`, así que no puede fallar.
    private static let tempo = Tempo(beatsPerMinute: 120)!

    private(set) var isPlaying = false
    private(set) var selection = MIDIEndpointSelection(.destination)

    /// De dónde llegan los giros de knob.
    private(set) var sourceSelection = MIDIEndpointSelection(.source)

    /// Los dieciséis Tracks, con los giros ya aplicados.
    private(set) var pattern = Pattern.initial

    /// Cuál se está editando y mostrando.
    ///
    /// **Lo mueven los step buttons y también la pantalla**: sin controlador
    /// conectado hay que poder mirar los otros quince, aunque no se puedan
    /// editar.
    private(set) var selectedTrackIndex = 0

    /// El Track seleccionado, que es el que la pantalla muestra.
    var track: Track { pattern.track(at: selectedTrackIndex)! }

    /// Cuáles tienen material: los vacíos no suenan, y eso se ve.
    var tracksWithMaterial: [Bool] {
        (0..<Pattern.trackCount).map { !(pattern.track(at: $0)?.pool.isEmpty ?? true) }
    }

    /// Por qué la salida no está disponible, si no lo está.
    ///
    /// Solo se llena si CoreMIDI no arrancó, que es un fallo real y no una
    /// desconexión. Desenchufar el cable es un estado (`No MIDI device`), no
    /// esto.
    private(set) var outputUnavailable: String?

    private var output: CoreMIDIOutput?
    private var watcher: MIDIEndpointWatcher?
    private var transport: Transport?

    private var input: CoreMIDIInput?
    private var sourceWatcher: MIDIEndpointWatcher?
    /// La entrada de control, que existe **siempre**.
    ///
    /// **Antes se creaba al conectar el controlador**, y eso dejaba a la
    /// pantalla sin nadie a quien pedirle una edición cuando no había cable: el
    /// modelo tenía que llevar una copia del estado y sincronizarla. Ahora es la
    /// única fuente, con o sin controlador; lo que llega por CoreMIDI es solo
    /// otra vía de entrada.
    private let controlInput: ControlInput

    /// Por dónde la entrada de control llega al transporte.
    ///
    /// **Existe porque el transporte puede no existir.** Sin salida MIDI no hay
    /// transporte, y la app tiene que seguir siendo editable —se ve, no se oye—.
    /// Un relevo con el destino dentro deja que la entrada publique siempre y
    /// que el transporte se enchufe cuando aparezca, en vez de repartir esa
    /// condición por cada camino de edición.
    private final class TransportRelay: @unchecked Sendable {
        var transport: Transport?
        func publish(_ pattern: Pattern) { transport?.publish(pattern) }
    }

    private let relay = TransportRelay()

    /// Endpoint al que se está enviando, leído desde el hilo del scheduler.
    ///
    /// **Va en un atómico y no en una propiedad del modelo.** El destino cambia
    /// al enchufar o desenchufar, así que el hilo del scheduler tiene que poder
    /// leerlo mientras suena. Leer una propiedad `@Observable` desde ahí
    /// registraría una dependencia de observación —que asigna memoria— en pleno
    /// camino de tiempo real.
    ///
    /// `0` es el objeto nulo de CoreMIDI, así que sirve como «ninguno».
    private let activeDestination = AtomicCounter(0)

    var destinationStatus: String { selection.statusDescription }
    var sourceStatus: String { sourceSelection.statusDescription }
    var shapeSummary: String { track.shape.description }

    /// Los cinco parámetros de Groove, en reposo, partidos en dos renglones.
    /// El formato y el corte viven en `Engine`, donde se testean.
    var grooveSummaryLines: [String] { track.groove.descriptionLines }

    /// Sin controlador conectado la app es de solo lectura y transporte
    /// (`product-guidelines.md`). Es un estado, no una carencia: no se abre
    /// ninguna vía táctil para suplirlo.
    var isReadOnly: Bool { !sourceSelection.hasEndpoint }

    /// Cuánto se queda el valor grande tras el último giro.
    ///
    /// Lo bastante para leerlo de pie y a un metro sin que estorbe al anillo
    /// después. No es un valor medido: se ajusta con la app en la mano.
    private static let transientLifetime: Double = 1.6

    /// El valor grande que se está mostrando, o `nil` si no hay ninguno.
    private(set) var transientChange: ParameterChange?

    private var transientDismissal: Task<Void, Never>?

    /// El anillo del Track vigente: dónde cae cada Step y cuáles disparan.
    var ring: Ring { Ring(shape: track.shape) }

    /// Dónde está el playhead, o `nil` con el transporte parado.
    ///
    /// **No es estado observable y no debe serlo.** Se consulta al dibujar, y
    /// cambia de forma continua: publicarlo como propiedad observada obligaría a
    /// alguien a refrescarlo a 60 Hz y a invalidar la vista entera en cada
    /// fotograma. Quien lo dibuje se redibuja solo —`TimelineView`— y pregunta
    /// aquí; el valor que recibe deriva del reloj musical, no del temporizador
    /// que provocó el redibujado.
    var playhead: Playhead? { transport?.playhead }

    /// Dónde está el playhead en cada uno de los dieciséis anillos.
    ///
    /// Mismo criterio que `playhead`: no es estado observable, se consulta al
    /// dibujar. Con el transporte parado son dieciséis `nil`, y no una lista
    /// vacía, para que quien dibuja indexe por Track sin comprobar longitudes.
    var playheads: [Playhead?] {
        guard let running = transport?.playheads else {
            return Array(repeating: nil, count: Pattern.trackCount)
        }
        return running.map(Optional.some)
    }

    /// Los dieciséis anillos, dispuestos.
    var rings: RingStack { RingStack(pattern: pattern) }
    var canPlay: Bool { selection.hasEndpoint && transport != nil }

    init() {
        // La entrada de control se construye primero y publica por el relevo:
        // así no depende de que el transporte exista, ni de que llegue a
        // existir.
        let relay = self.relay
        controlInput = ControlInput(
            pattern: .initial,
            publish: { [relay] updated in relay.publish(updated) }
        )

        do {
            let output = try CoreMIDIOutput()
            self.output = output

            let watcher = MIDIEndpointWatcher(
                .destination, enumerating: output.availableDestinations)
            self.watcher = watcher
            selection = watcher.selection

            watcher.onChange = { [weak self] selection in
                self?.destinationsChanged(to: selection)
            }
            // La notificación llega desde el hilo de CoreMIDI; el watcher ya
            // entrega el cambio en el principal.
            output.onSetupChanged = { [weak watcher] in watcher?.setupChanged() }

            let timeline = MusicalTimeline(
                tempo: Self.tempo, division: Pattern.initial.track(at: 0)!.shape.division)
            let createdTransport = Transport(
                configuration: SchedulerConfiguration(timeline: timeline),
                pattern: .initial,
                emitter: Self.voice()
            ) { [output, activeDestination] message, hostTime in
                Self.send(message, at: hostTime, through: output, to: activeDestination)
            }
            transport = createdTransport
            relay.transport = createdTransport

            activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
        } catch {
            outputUnavailable = "MIDI output unavailable"
        }

        connectControlInput()
    }

    /// Cablea la entrada de control: los giros publican por el transporte, que
    /// es quien tiene el handoff que lee el scheduler.
    private func connectControlInput() {
        do {
            let input = try CoreMIDIInput { [weak self] message in
                // El callback llega desde el hilo de recepción de CoreMIDI. El
                // salto al principal es obligado: aquí se muta estado observable
                // que lee la interfaz. No está en el camino de timing, así que
                // el coste del salto es irrelevante — lo que tiene que ser
                // rápido es el scheduler, no esto.
                Task { @MainActor in self?.apply(message) }
            }
            self.input = input

            let sourceWatcher = MIDIEndpointWatcher(.source, enumerating: input.availableSources)
            self.sourceWatcher = sourceWatcher
            sourceSelection = sourceWatcher.selection
            connectToSelectedSource()

            sourceWatcher.onChange = { [weak self] selection in
                self?.sourceSelection = selection
                self?.connectToSelectedSource()
            }
            // **Además de reconsultar, se vuelve a conectar.** El watcher solo
            // avisa cuando la *elección* cambia, y CoreMIDI puede tirar la
            // conexión del puerto sin que la lista de fuentes cambie —el
            // dispositivo se reenumera y vuelve con el mismo nombre—. Sin esto,
            // la app se queda con un puerto conectado a nada: los knobs dejan de
            // llegar y no hay nada que la despierte. Conectar es idempotente y
            // desconecta la anterior, así que repetirlo no cuesta nada.
            input.onSetupChanged = { [weak sourceWatcher, weak self] in
                sourceWatcher?.setupChanged()
                Task { @MainActor in self?.connectToSelectedSource() }
            }
        } catch {
            // Sin entrada, la app se queda en solo lectura y transporte. Es un
            // estado previsto, no un fallo que haya que anunciar.
            input = nil
        }
    }

    private func connectToSelectedSource() {
        guard let endpoint = sourceSelection.selected?.endpoint else { return }
        input?.connect(to: endpoint)
    }

    /// Applies a MIDI message to the track and announces the resulting parameter change.
    private func apply(_ message: MIDIMessage) {
        // El Track entero y no solo su Shape: Groove vive dentro, así que
        // comparar Shapes dejaría a Velocity, Sustain y Probability sin poder
        // anunciarse.
        let previous = track
        guard controlInput.receive(message) else { return }
        syncFromControlInput()

        // **Solo se anuncia lo del Track que se está mirando.** Un step button
        // cambia de Track, y comparar el anterior con el nuevo anunciaría como
        // «giro» toda la diferencia entre dos Tracks distintos.
        guard controlInput.selectedTrackIndex == selectedTrackIndex else { return }
        announce(ParameterChange(from: previous, to: track))
    }

    /// Muestra el valor grande y programa su desvanecimiento.
    ///
    /// **Cada giro reinicia la cuenta.** Girando sin parar el valor se queda
    /// puesto, que es lo que se quiere: se desvanece «tras la inactividad»
    /// Displays a parameter change temporarily before clearing it.
    private func announce(_ change: ParameterChange?) {
        guard let change else { return }
        transientChange = change

        transientDismissal?.cancel()
        let dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.transientLifetime))
            guard !Task.isCancelled else { return }
            self?.transientChange = nil
        }
        transientDismissal = dismissal
    }

    /// Elige otra fuente de entrada.
    func selectSource(_ endpoint: MIDIEndpointInfo) {
        sourceSelection = sourceSelection.selecting(endpoint)
        connectToSelectedSource()
    }

    func play() {
        guard canPlay else { return }
        transport?.play()
        isPlaying = transport?.isPlaying ?? false
    }

    func stop() {
        transport?.stop()
        isPlaying = false
    }

    private func destinationsChanged(to selection: MIDIEndpointSelection) {
        self.selection = selection
        activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
        // Perder el destino no para el reloj: el transporte sigue corriendo y
        // vuelve a sonar solo en cuanto haya dónde enviar. Desenchufar es un
        // estado, no una interrupción de la sesión.
    }

    /// Envía un mensaje al destino vigente, si lo hay.
    ///
    /// Es `static` para que el cierre del scheduler no capture el modelo: nada
    /// de este camino puede tocar estado observable.
    ///
    /// `nonisolated` es obligado y correcto: esto corre en el hilo del
    /// scheduler, no en el principal. No toca estado del modelo — por eso es
    /// `static` y recibe todo lo que necesita.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private nonisolated static func send(
        _ message: MIDIMessage,
        at hostTime: UInt64,
        through output: CoreMIDIOutput,
        to destination: AtomicCounter
    ) {
        let endpoint = MIDIEndpointRef(destination.value)
        guard endpoint != 0 else { return }
        output.send(message, to: endpoint, atHostTime: hostTime)
    }
}

extension TransportModel {

    /// Elige otro destino. Es lo único que la pantalla puede cambiar, junto con
    /// el transporte: los parámetros generativos no se tocan en esta rebanada.
    func select(_ destination: MIDIEndpointInfo) {
        selection = selection.selecting(destination)
        activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
    }
}
