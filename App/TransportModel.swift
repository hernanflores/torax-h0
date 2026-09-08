import CoreMIDI
import Engine
import MIDI
import Observation
import Persistence

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

    /// Cambia el canal de cualquier Track, desde la pantalla MIDI.
    ///
    /// **No mueve la selección**: ajustar el ruteo no debería cambiar a dónde
    /// apuntan los knobs. La regla y su prueba viven en `ControlInput`, que es
    /// donde se testean sin pantalla de por medio.
    func setChannel(_ channel: Channel, forTrack index: Int) {
        controlInput.setChannel(channel, forTrack: index)
        syncFromControlInput()
    }

    /// Qué Tracks se oyen: la mezcla vigente.
    ///
    /// **Es una copia de lo que tiene el transporte**, refrescada en cada gesto.
    /// La máscara de verdad vive ahí porque quien la lee es el hilo del
    /// scheduler; esto es lo que dibuja la pantalla.
    private(set) var mix = MuteState()

    /// Cuáles de los doce se oyen ahora mismo.
    ///
    /// **Se deriva de `mix` y no se guarda aparte**: dos sitios con la misma
    /// respuesta son dos sitios que pueden discrepar. La regla vive en `MIDI`,
    /// donde se testea; esto solo la pregunta doce veces.
    var audibleTracks: [Bool] {
        (0..<Pattern.trackCount).map { mix.isAudible($0) }
    }

    /// Alterna el mute de un Track desde la pantalla.
    ///
    /// **Hace lo mismo que el gesto del controlador**, por la misma razón que
    /// `selectTrack`: si no coincidieran, la pantalla mentiría sobre lo que el
    /// hardware acaba de hacer. Las dos vías terminan en el transporte, que es
    /// quien apaga lo que deje de sonar.
    func toggleMute(_ index: Int) {
        transport?.toggleMute(index)
        syncMix()
    }

    /// Alterna el solo de un Track desde la pantalla.
    func toggleSolo(_ index: Int) {
        transport?.toggleSolo(index)
        syncMix()
    }

    /// Copia la mezcla del transporte al modelo observable.
    private func syncMix() {
        guard let transport else { return }
        mix = transport.mix
    }

    /// Selecciona un Track desde la pantalla.
    ///
    /// **Hace lo mismo que su step button.** Sin controlador conectado es la
    /// única vía, y con controlador las dos tienen que coincidir o la pantalla
    /// mentiría.
    // MARK: - Banks y Patterns

    var selectedBankIndex: Int { project.selectedBank }
    var selectedPatternIndex: Int { project.selectedPattern }

    /// El Bank vigente.
    var bank: Bank { project.bank(at: project.selectedBank) ?? Bank() }

    /// El estado de los dieciséis huecos del Bank vigente (FR25).
    var patternSlotStates: [PatternSlotState] {
        bank.slotStates(
            playing: project.selectedPattern,
            queued: armedPatternIndex,
            isRunning: isPlaying
        )
    }

    /// Qué hueco espera al compás, si alguno.
    private(set) var armedPatternIndex: Int?

    /// Cuántas negras faltan para que entre el Pattern armado, o `nil` si no hay
    /// ninguno esperando.
    var beatsUntilPatternChange: Int? {
        guard armedPatternIndex != nil, let elapsed = transport?.elapsedNanoseconds else {
            return nil
        }
        return BarGrid(tempo: Tempo(beatsPerMinute: beatsPerMinute) ?? .init(beatsPerMinute: 120)!)
            .beatsUntilNextBoundary(at: elapsed)
    }

    /// Elige un Pattern del Bank vigente.
    ///
    /// **La regla de cómo entra la decide el transporte** (FR5, FR6): parado es
    /// inmediato, sonando espera al compás. Aquí solo se anota qué hueco es el
    /// que entra, para que la pantalla pueda decir `queued`.
    ///
    /// **Y la entrada de control adopta el material nuevo**, que es el fallo que
    /// arregla `control-input-adoption` (FR6): `ControlInput` guarda su propia
    /// copia del Pattern y nadie la reseedeaba, así que el primer giro de knob
    /// republicaba el Pattern anterior entero encima. La rama que suena todavía
    /// no adopta: ahí el material entra en el límite de compás, dentro del hilo
    /// del scheduler, y quien lo cuenta es la vía de vuelta.
    func selectPattern(_ index: Int) {
        guard let material = bank.pattern(at: index) else { return }

        if isPlaying {
            transport?.armForNextBar(material)
            armedPatternIndex = index
        } else {
            project = project.selectingPattern(index)
            pattern = material
            controlInput.adopt(material)
            transport?.publish(material)
            armedPatternIndex = nil
        }
        autosave.changedHeader(project)
    }

    /// Elige otro Bank: su Pattern seleccionado y su tempo (FR11).
    ///
    /// Adopta con el transporte parado, por lo mismo que `selectPattern(_:)`.
    func selectBank(_ index: Int) {
        guard let target = project.bank(at: index) else { return }

        project = project.selectingBank(index)
        transport?.select(target, pattern: project.selectedPattern)

        if !isPlaying {
            pattern = target.pattern(at: project.selectedPattern) ?? Pattern()
            controlInput.adopt(pattern)
            armedPatternIndex = nil
        } else {
            armedPatternIndex = project.selectedPattern
        }
        autosave.changedHeader(project)
    }

    /// Copia el Pattern vigente en otro hueco (FR13).
    func copyPattern(to index: Int) {
        project = project.copyingSelectedPattern(to: index)
        autosave.changed(bank, at: project.selectedBank)
    }

    /// Vacía un hueco (FR13).
    func clearPattern(at index: Int) {
        project = project.clearingPattern(at: index)
        autosave.changed(bank, at: project.selectedBank)
    }

    // MARK: - Guardado

    /// Si `Reload` se puede pulsar, y por qué no cuando no (FR17).
    var reloadAvailability: ReloadAvailability {
        store.reloadAvailability(at: project.selectedBank)
    }

    /// Fija el punto de retorno del Bank vigente (FR16).
    func saveBank() {
        try? store.saveRestorePoint(bank, at: project.selectedBank)
    }

    /// Vuelve al punto de retorno. **Cuantizado**, por el mismo camino que un
    /// cambio de Pattern (FR17).
    ///
    /// Adopta con el transporte parado, por lo mismo que `selectPattern(_:)`.
    func reloadBank() {
        guard let saved = try? store.restorePoint(at: project.selectedBank) else { return }

        project = project.replacing(saved, at: project.selectedBank)
        transport?.select(saved, pattern: project.selectedPattern)

        if !isPlaying {
            pattern = saved.pattern(at: project.selectedPattern) ?? Pattern()
            controlInput.adopt(pattern)
        }
        autosave.changed(saved, at: project.selectedBank)
    }

    /// Escribe lo pendiente ahora. La llama el paso a segundo plano (FR14).
    func flushPendingSaves() {
        try? autosave.flush()
    }

    /// Mira si toca escribir. La llama la pantalla, una vez por segundo.
    func tickAutosave() {
        try? autosave.tick()
    }

    func selectTrack(_ index: Int) {
        controlInput.selectTrack(index)
        syncFromControlInput()
    }

    /// Toca un pad de la rejilla de la pantalla `scale`.
    ///
    /// **Va por la misma puerta que el pad del controlador.** `pressPad(at:)`
    /// vive en `MIDI` y es el mismo cuerpo que atiende al hardware, así que la
    /// regla —alternar en el pool, mover la octava, callar con un modificador
    /// hundido— no existe dos veces.
    func pressPad(at index: Int) {
        controlInput.pressPad(at: index)
        syncFromControlInput()
    }

    /// Copia el estado de la entrada de control al modelo observable.
    ///
    /// Es un solo sitio a propósito: cada camino que edita —knob, pad, pantalla—
    /// termina aquí, y así no hay ninguno que se olvide de refrescar la mitad.
    private func syncFromControlInput() {
        pattern = controlInput.pattern
        selectedTrackIndex = controlInput.selectedTrackIndex
        gesture =
            controlInput.isTempActive
            ? .temp : (controlInput.isCtrlAllActive ? .ctrlAll : .none)

        recordEdit()
    }

    /// Escribe el Pattern vigente en su hueco del Project, y lo pone en cola
    /// para el Autosave.
    ///
    /// **Es el fallo que la pantalla `banks` destapó**: `pattern` y `project`
    /// eran dos estados separados y solo el primero recibía las ediciones. El
    /// Project se quedaba con lo que se cargó del disco, así que el card de
    /// bancos decía «no patterns» con una pieza sonando, el hueco activo decía
    /// `empty`, y —lo peor— **`Save Bank` guardaba el Bank viejo**: el punto de
    /// retorno se fijaba sobre material que ya no existía.
    ///
    /// **Va en `syncFromControlInput` porque ése ya era el sitio único.** Su
    /// propia documentación lo dice: «cada camino que edita —knob, pad,
    /// pantalla— termina aquí, y así no hay ninguno que se olvide de refrescar
    /// la mitad». Refrescaba media mitad.
    ///
    /// **El gesto en curso no se guarda.** Temp y Ctrl All superponen valores
    /// que vuelven solos al soltar, y escribirlos dejaría en disco un fill que
    /// nadie pidió conservar — que es justo lo que esos dos gestos existen para
    /// evitar.
    private func recordEdit() {
        guard gesture == .none else { return }

        project = project.replacing(
            bank.replacing(pattern, at: project.selectedPattern),
            at: project.selectedBank
        )
        autosave.changed(bank, at: project.selectedBank)
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
    /// El árbol entero: dieciséis Banks, dónde se está mirando y los ajustes de
    /// sesión.
    ///
    /// **Es la fuente de verdad del material desde el 2026-09-07.** `pattern`
    /// pasa a derivarse de aquí: el Pattern vigente es el del Bank y el hueco
    /// seleccionados.
    private(set) var project = Project.initial

    /// Los ficheros. **Es el único que toca disco.**
    private let store = ProjectStore()

    /// El guardado automático del trabajo en curso.
    ///
    /// **No es `lazy`**: `@Observable` no admite propiedades diferidas, y además
    /// no hay nada que diferir — construirlo no toca disco.
    @ObservationIgnored private let autosave: Autosave

    /// Qué ficheros se apartaron al arrancar por ilegibles, si alguno.
    ///
    /// **La app abre igual** (FR22); esto es lo que la pantalla cuenta para que
    /// el usuario sepa que su fichero sigue ahí, apartado, y no borrado.
    private(set) var rescuedFiles: [String] = []

    /// Por qué falló el último guardado, si falló.
    ///
    /// **Persistente hasta que uno funcione** (FR21). Un Autosave silencioso que
    /// lleva diez minutos fallando es la peor forma de perder trabajo.
    var saveFailure: String? {
        store.lastSaveFailure.map { _ in "No se pudo guardar" }
    }

    /// El Pattern vigente, derivado del Project.
    private(set) var pattern = Pattern.initial

    /// Cuál se está editando y mostrando.
    ///
    /// **Lo mueven los step buttons y también la pantalla**: sin controlador
    /// conectado hay que poder mirar los otros quince, aunque no se puedan
    /// editar.
    private(set) var selectedTrackIndex = 0

    /// El Track seleccionado, que es el que la pantalla muestra.
    /// **Es el Cycle en edición, no el que suena.** Todo lo que la pantalla
    /// muestra —el anillo, la lectura grande, el pool, la superficie de pads y
    /// el canal— es lo que los knobs están moviendo; lo único que enseña el que
    /// suena es el relleno de la fila de Cycles.
    ///
    /// > **Corregido el 2026-09-02, encontrado en dispositivo.** Esto devolvía
    /// > el Cycle que suena. Con el transporte parado y el knob 10 movido, los
    /// > demás knobs editaban el Cycle correcto y la pantalla seguía enseñando
    /// > el primero: se leía como «el Track dejó de responder».
    var track: Cycle { pattern.editingCycle(at: selectedTrackIndex)! }

    /// Cuáles tienen material: los vacíos no suenan, y eso se ve.
    /// Si el Pattern tiene algo que emitir: alguno de sus doce Tracks con pool.
    ///
    /// Lo usa la pantalla `banks` para decidir si el único pattern que existe
    /// está `ready` o `empty`. Sale del Pattern real, así que esa parte de esa
    /// pantalla no es cáscara.
    /// **Lo decide `Engine` desde el 2026-09-07.** Se calculaba aquí, y con 256
    /// Patterns que preguntar habría dos definiciones de «tiene material» en dos
    /// paquetes — una de ellas donde no hay tests.
    var patternHasMaterial: Bool { pattern.hasMaterial }

    var tracksWithMaterial: [Bool] {
        (0..<Pattern.trackCount).map { !(pattern.editingCycle(at: $0)?.pool.isEmpty ?? true) }
    }

    /// Por dónde emite cada Track.
    ///
    /// **Los doce, no solo el elegido**: la pantalla MIDI enseña el ruteo
    /// entero, así que dice de un vistazo si dos Tracks comparten instrumento
    /// sin tener que seleccionarlos uno a uno.
    var channels: [Channel] {
        (0..<Pattern.trackCount).map { pattern.editingCycle(at: $0)?.channel ?? .first }
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

        /// Entrega un mensaje entrante al reloj del transporte y dice si era
        /// suyo.
        ///
        /// **Existe para poder llamarlo desde el hilo de recepción de
        /// CoreMIDI.** `transport` en el modelo está aislado al hilo principal,
        /// y saltar allí para atender un tick metería la cola del principal
        /// dentro de la estimación del tempo — que es justo lo que el reloj no
        /// puede permitirse.
        func receive(_ message: MIDIMessage, atHostTime hostTime: UInt64) -> Bool {
            transport?.receive(message, atHostTime: hostTime) ?? false
        }

        /// El gesto del controlador desemboca en el transporte, que es quien
        /// apaga lo que deje de sonar. **No hay un segundo camino**: si la
        /// pantalla y el controlador tocaran la máscara por su cuenta, uno de
        /// los dos se saltaría el apagado.
        func apply(_ gesture: MixGesture) {
            switch gesture {
            case .mute(let index): transport?.toggleMute(index)
            case .solo(let index): transport?.toggleSolo(index)
            }
        }
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
    /// Las alturas del pool del Track seleccionado, ya nombradas.
    ///
    /// **`Pitch` sabe decir su nombre** y el pool sabe cuántas tiene; juntarlas
    /// es cableado, no una regla.
    var poolNames: [String] {
        let pool = track.pool
        return (0..<pool.count).compactMap { pool.pitch(at: $0).map { "\($0)" } }
    }

    var shapeSummary: String { track.shape.description }

    /// Los cinco parámetros de Groove, en reposo, partidos en dos renglones.
    /// El formato y el corte viven en `Engine`, donde se testean.
    var grooveSummaryLines: [String] { track.groove.descriptionLines }

    /// Sin controlador conectado la app es de solo lectura y transporte
    /// (`product-guidelines.md`). Es un estado, no una carencia: no se abre
    /// ninguna vía táctil para suplirlo.
    var isReadOnly: Bool { !sourceSelection.hasEndpoint }

    /// Qué gesto momentáneo está puesto, si hay alguno.
    ///
    /// **Los valores no cambian de camino: cambia lo que significan.** El overlay
    /// y el desplazamiento se escriben en el `Pattern` publicado, así que la
    /// lectura, los anillos y el valor grande ya los recogen solos; sin esto, un
    /// gesto puesto y una edición permanente se leerían exactamente igual (FR10,
    /// FR16).
    ///
    /// > **Sustituye a `isTempActive`, que era un `Bool`.** Con dos gestos
    /// > momentáneos, un booleano solo podía decir «hay algo puesto», y lo que el
    /// > usuario necesita saber es **cuál**: los dos son reversibles, y lo que
    /// > los separa es si se mueve un Track o los doce. Mantener el booleano al
    /// > lado del caso habría dejado dos fuentes de verdad para la misma
    /// > pregunta.
    ///
    /// **Los dos nunca están puestos a la vez**, y el empate no se resuelve aquí:
    /// `isCtrlAllActive` ya dice «al mando» y no «hundido», así que con el step
    /// 13 y el 14 bajo los dedos gana Temp sin que la vista ni este modelo tengan
    /// que saberlo. Repartir el desempate entre la entrada y la presentación
    /// acabaría con los dos diciendo cosas distintas.
    private(set) var gesture: ReadoutGesture = .none

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

    /// Por qué Cycle va el Track seleccionado, o `nil` con el transporte
    /// parado.
    ///
    /// Mismo criterio que `playhead`: no es estado observable, se consulta al
    /// dibujar. Deriva del reloj —ver `CyclePosition`— porque el cursor de
    /// reproducción vive en el hilo del scheduler y publicarlo sería trabajo en
    /// el camino de tiempo real para ahorrarle una división a la pantalla.
    var cycleInCourse: Int? {
        transport?.cyclesInCourse?[selectedTrackIndex].cycle
    }

    /// Cuántos Cycles recorre el Track seleccionado.
    var activeCycleCount: Int { pattern.track(at: selectedTrackIndex)?.activeCount ?? 1 }

    /// Cuál se está editando: al que escuchan los knobs y los pads.
    var editingCycle: Int { pattern.track(at: selectedTrackIndex)?.editing ?? 0 }

    /// Cambia cuántos Cycles recorre el Track seleccionado.
    ///
    /// **Táctil, como Scale, Root y el canal**: es configuración y no material
    /// generativo. La Pre Spec lo ponía en un gesto de CTRL sobre el knob y el
    /// BeatStep Pro no tiene CTRL — nota fechada del 2026-09-02 en la Pre Spec.
    func setActiveCycleCount(_ count: Int) {
        controlInput.setActiveCycleCount(count)
        syncFromControlInput()
    }

    /// Los dieciséis anillos, dispuestos.
    var rings: RingStack { RingStack(pattern: pattern) }
    var canPlay: Bool { selection.hasEndpoint && transport != nil }

    /// El tempo vigente, en la unidad que la barra muestra.
    ///
    /// **Ya no es una constante** (track `external-clock_20260903`): con reloj
    /// interno es el de la app, editable en la pantalla MIDI; con reloj externo,
    /// el que se está estimando del maestro.
    ///
    /// **Redondeado a un decimal, y por eso estable.** El estimado se mueve en
    /// las milésimas de un tick a otro y un último decimal que baila es ilegible
    /// a un metro. Lo que se redondea es lo que se enseña; lo que suena usa el
    /// valor entero.
    ///
    /// **Se calcula al preguntar, no se guarda.** Guardarlo obligaría a alguien
    /// a refrescarlo, y ese alguien sería un temporizador de interfaz — el mismo
    /// antipatrón que `product-guidelines.md` nombra y que el playhead ya evita.
    /// Leerlo es una lectura atómica.
    var beatsPerMinute: Double {
        // Misma suscripción que `followsExternalClock`: `setTempo` incrementa el
        // contador y así el número de la barra se ve al instante.
        _ = clockRevision
        guard let transport else { return 120 }
        return transport.currentTempo.displayBeatsPerMinute
    }

    /// El tempo escrito, `124 bpm`.
    ///
    /// **El formato lo pone `Engine`**, donde tiene tests. Aquí solo se pasa el
    /// tempo vigente: la vista no debería saber cuántos decimales lleva un tempo
    /// ni qué locale usar para escribirlos.
    var tempoDescription: String {
        (Tempo(beatsPerMinute: beatsPerMinute) ?? Self.tempo).displayDescription
    }

    /// Si la app sigue a un maestro externo.
    ///
    /// **Lee `clockRevision` antes de responder, y en eso consiste el arreglo.**
    ///
    /// > **El segmentado de la pantalla `midi` no reaccionaba al tocarlo**, y el
    /// > cambio solo se veía al navegar a otra pantalla y volver. La causa es que
    /// > esto sale del `Transport`, que no es observable: `setFollowsExternalClock`
    /// > incrementaba `clockRevision` religiosamente y **no lo leía nadie**. Su
    /// > única consumidora era `ChannelMapView`, que lo recibía dentro de un
    /// > struct; al reescribirla, el contador se quedó sin suscriptores.
    /// >
    /// > Leerlo aquí hace que **usar el valor sea suscribirse**, sin que ninguna
    /// > vista tenga que acordarse de nada. Un contador de invalidación que hay
    /// > que recordar leer es un contador que alguien va a olvidar.
    ///
    /// **Lo que esto no arregla, y conviene que esté escrito:** un cambio que
    /// venga del hardware —el tempo de un maestro externo, un Start del
    /// BeatStep— sigue sin invalidar nada, porque nadie incrementa el contador
    /// desde el hilo de recepción. Eso necesita un aviso desde ese hilo y es otro
    /// trabajo; tres intentos de resolverlo de paso dejaron la app peor.
    var followsExternalClock: Bool {
        _ = clockRevision
        return transport?.clockSource == .external
    }

    /// Qué está pasando con el reloj externo, en una línea. `nil` con reloj
    /// interno, que no tiene nada que contar.
    ///
    /// En inglés y sin traducir, como el resto del vocabulario de interfaz.
    var clockStatus: String? {
        _ = clockRevision
        guard let transport else { return nil }

        // **La tabla la decide `MIDI`, con tests.** Aquí solo se leen los tres
        // estados del transporte y se pide el texto: qué mensaje va con qué
        // combinación es una regla, y una regla mal escrita en `App` no falla —
        // enseña el mensaje equivocado, que es peor.
        return ClockStatus(
            source: transport.clockSource,
            isPlaying: transport.isPlaying,
            hasDropped: transport.clockHasDropped(),
            isEstablished: transport.isFollowingEstablishedClock
        )?.description
    }

    /// Quién manda el tempo, con su nombre. El nombre lo pone `MIDI`.
    var clockSourceName: String {
        (followsExternalClock ? ClockSource.external : .internal).name
    }

    /// La marca de la barra: quién manda el tempo, en dos letras.
    var clockSourceMark: String { followsExternalClock ? "EXT" : "INT" }

    /// Elige quién manda el tempo.
    ///
    /// No toca lo que esté sonando: decide a quién se hace caso a partir de
    /// ahora.
    func setFollowsExternalClock(_ isExternal: Bool) {
        transport?.clockSource = isExternal ? .external : .internal
        clockRevision &+= 1
    }

    /// Fija el tempo de la app. Fuera del rango 20–300 no hace nada.
    func setTempo(_ beatsPerMinute: Double) {
        guard transport?.setTempo(beatsPerMinute: beatsPerMinute) == true else { return }
        clockRevision &+= 1
    }

    /// Cambia con cada gesto sobre el reloj.
    ///
    /// **Existe para que SwiftUI repinte.** El tempo y el estado se calculan al
    /// preguntar, así que no hay estado observable que cambie al tocarlos y la
    /// pantalla MIDI se quedaría con el valor viejo. Tocar esto es decirle a la
    /// vista que vuelva a preguntar, sin guardar una copia que mantener al día.
    private(set) var clockRevision: UInt64 = 0

    init() {
        autosave = Autosave(store: store)

        // **El disco se lee antes que nada** (FR20, FR23).
        //
        // `load()` no lanza nunca: si el fichero está corrupto o es de una
        // versión desconocida, se aparta con marca de tiempo y esto devuelve un
        // Project vacío diciendo qué se apartó. La app abre siempre.
        let restored = store.load()

        // **Disco vacío arranca con el material de siempre, no con silencio.**
        //
        // `load()` devuelve un Project vacío cuando no hay nada que leer, que es
        // correcto para el almacén: no se inventa material que nadie guardó. Lo
        // que decide con qué abre la app es esto, y `Project.initial` es el
        // requisito de que meter dos niveles no cambie lo que se oye — la app
        // abre con 16/5 sobre c3, como abría antes de la rebanada.
        //
        // Se descubrió mirando el simulador: la primera versión abría muda con
        // `pool empty`, y ningún test lo habría visto porque todos construyen el
        // Project que quieren probar.
        let loaded = restored.wasEmpty ? Project.initial : restored.project
        project = loaded
        rescuedFiles = restored.rescuedFiles
        let restoredPattern =
            loaded.bank(at: loaded.selectedBank)?
            .pattern(at: loaded.selectedPattern) ?? Pattern.initial
        pattern = restoredPattern
        selectedTrackIndex = loaded.selectedTrack

        // La entrada de control se construye primero y publica por el relevo:
        // así no depende de que el transporte exista, ni de que llegue a
        // existir.
        let relay = self.relay
        controlInput = ControlInput(
            // **Con el Pattern restaurado, no con `.initial`.**
            //
            // Arrancaba con `.initial` y el disco se leía después, así que la
            // entrada de control quedaba con material distinto del que enseñaba
            // la pantalla: **el primer giro de knob publicaba `.initial` y se
            // llevaba por delante lo restaurado**. Se descubrió persiguiendo por
            // qué el Bank decía «no patterns» con una pieza sonando.
            pattern: restoredPattern,
            publish: { [relay] updated in relay.publish(updated) },
            mix: { [relay] gesture in relay.apply(gesture) }
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
                tempo: Self.tempo, division: pattern.cycle(at: 0)!.shape.division)
            let createdTransport = Transport(
                configuration: SchedulerConfiguration(timeline: timeline),
                pattern: restoredPattern,
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
        let relay = self.relay
        do {
            let input = try CoreMIDIInput { [weak self, relay] message, hostTime in
                // **El reloj se atiende aquí mismo, sin saltar al principal.**
                // Un tick vive de cuándo llegó, y la cola del hilo principal
                // metería su propio retraso en la estimación del tempo. El
                // transporte dice si el mensaje era suyo; si lo era, no hay nada
                // más que hacer con él.
                if relay.receive(message, atHostTime: hostTime) { return }

                // El resto llega desde el hilo de recepción de CoreMIDI. El
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
        // **Reconectar suelta los modificadores** (FR8). Si el cable se fue con
        // un step button hundido, la soltada que lo levantaría ya no va a llegar
        // por ningún sitio y el modificador se quedaría pegado para siempre.
        controlInput.releaseModifiers()
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
        // El gesto de mezcla ya llegó al transporte por el relevo; lo que falta
        // es traerse la foto nueva para que la pantalla la dibuje.
        syncMix()

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
