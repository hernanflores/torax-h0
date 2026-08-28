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

    /// Altura, canal y velocity con los que suena el Track.
    ///
    /// **Constante provisional del camino MIDI, no estado del Track.** No hay
    /// Tonal en esta rebanada, así que no hay pool de alturas del que elegir.
    /// Vive aquí y no en `Track` para que nada consolide la idea de una nota
    /// fija por paso, que `product-guidelines.md` advierte que contradice el
    /// modelo de pool. Por la misma razón no se muestra en pantalla.
    ///
    /// Canal 1, altura 48 y velocity 100 son literales dentro de sus rangos
    /// (1–16, 0–127, 0–127), así que el desempaquetado no puede fallar.
    private static let provisionalVoice = NoteEmitter(
        channel: MIDIChannel(1)!,
        note: MIDINote(48)!,
        velocity: MIDIVelocity(100)!
    )

    /// 120 BPM está dentro del rango válido de `Tempo`, así que no puede fallar.
    private static let tempo = Tempo(beatsPerMinute: 120)!

    private(set) var isPlaying = false
    private(set) var selection = MIDIEndpointSelection(.destination)

    /// De dónde llegan los giros de knob.
    private(set) var sourceSelection = MIDIEndpointSelection(.source)

    /// Track vigente, con los giros ya aplicados.
    private(set) var track = Track(shape: TransportModel.initialShape)

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
    private var controlInput: ControlInput?

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
    private(set) var transientChange: ShapeChange?

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
    var canPlay: Bool { selection.hasEndpoint && transport != nil }

    init() {
        do {
            let output = try CoreMIDIOutput()
            self.output = output

            let watcher = MIDIEndpointWatcher(.destination, enumerating: output.availableDestinations)
            self.watcher = watcher
            selection = watcher.selection

            watcher.onChange = { [weak self] selection in
                self?.destinationsChanged(to: selection)
            }
            // La notificación llega desde el hilo de CoreMIDI; el watcher ya
            // entrega el cambio en el principal.
            output.onSetupChanged = { [weak watcher] in watcher?.setupChanged() }

            transport = Transport(
                configuration: SchedulerConfiguration(
                    timeline: MusicalTimeline(tempo: Self.tempo, division: track.shape.division)
                ),
                track: track,
                emitter: Self.provisionalVoice
            ) { [output, activeDestination] message, hostTime in
                Self.send(message, at: hostTime, through: output, to: activeDestination)
            }

            activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
        } catch {
            outputUnavailable = "MIDI output unavailable"
        }

        connectControlInput()
    }

    /// Cablea la entrada de control: los giros publican por el transporte, que
    /// es quien tiene el handoff que lee el scheduler.
    private func connectControlInput() {
        guard let transport else { return }

        let controlInput = ControlInput(
            track: track,
            publish: { [weak transport] updated in transport?.publish(updated) }
        )
        self.controlInput = controlInput

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
            input.onSetupChanged = { [weak sourceWatcher] in sourceWatcher?.setupChanged() }
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

    /// Aplica un mensaje entrante. Corre en el hilo principal.
    private func apply(_ message: MIDIMessage) {
        guard let controlInput else { return }
        let previous = track.shape
        guard controlInput.receive(message) else { return }
        track = controlInput.track
        announce(ShapeChange(from: previous, to: track.shape))
    }

    /// Muestra el valor grande y programa su desvanecimiento.
    ///
    /// **Cada giro reinicia la cuenta.** Girando sin parar el valor se queda
    /// puesto, que es lo que se quiere: se desvanece «tras la inactividad»
    /// (`product-guidelines.md`), no tras un tiempo fijo desde que apareció.
    private func announce(_ change: ShapeChange?) {
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
