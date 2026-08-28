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
@Observable
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

    /// Por qué la salida no está disponible, si no lo está.
    ///
    /// Solo se llena si CoreMIDI no arrancó, que es un fallo real y no una
    /// desconexión. Desenchufar el cable es un estado (`No MIDI device`), no
    /// esto.
    private(set) var outputUnavailable: String?

    let shape = TransportModel.initialShape

    private var output: CoreMIDIOutput?
    private var watcher: MIDIEndpointWatcher?
    private var transport: Transport?

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
    var shapeSummary: String { shape.description }
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
                    timeline: MusicalTimeline(tempo: Self.tempo, division: shape.division)
                ),
                track: Track(shape: shape),
                emitter: Self.provisionalVoice
            ) { [output, activeDestination] message, hostTime in
                Self.send(message, at: hostTime, through: output, to: activeDestination)
            }

            activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
        } catch {
            outputUnavailable = "MIDI output unavailable"
        }
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
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private static func send(
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
