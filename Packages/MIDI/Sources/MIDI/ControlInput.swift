import Engine

/// Un gesto de mezcla pedido desde el controlador.
///
/// **No es un cambio de Track y por eso no viaja con ellos.** Mute y solo viven
/// por encima del Pattern —ver la nota del 2026-09-02 en la Pre Spec—, así que
/// meterlos en el snapshot publicado sería justo el error que esa nota evita.
/// Salen por su propia puerta y los aplica quien tiene el transporte.
public enum MixGesture: Equatable, Sendable {
    case mute(Int)
    case solo(Int)
}

/// Convierte los mensajes de un controlador en Tracks publicados.
///
/// Es la pieza que cierra la cadena del track: decodifica el giro, lo traduce al
/// parámetro que le toca, se lo aplica al Shape vigente y publica el `Cycle`
/// resultante por el `PatternHandoff` que la rebanada 1 dejó probado. Girar un
/// knob y publicar un snapshot son, a partir de aquí, la misma cosa.
///
/// **Corre en el hilo de control, nunca en el del scheduler.** Recibir un
/// mensaje asigna memoria —construir un Shape reparte los Pulses— y eso está
/// prohibido en el camino de timing. La separación es la misma que ya usa
/// `PatternHandoff`: un solo escritor publica, el scheduler solo lee.
public final class ControlInput: @unchecked Sendable {

    /// Los dieciséis Tracks, con los giros ya aplicados.
    ///
    /// Se guardan aquí y no se releen del handoff porque `load()` puede
    /// descartar una lectura, y perder un giro por eso sería un knob que no
    /// responde.
    public private(set) var pattern: Pattern

    /// El Cycle que los knobs y los pads editan.
    ///
    /// **Editar es siempre editar el seleccionado.** Los otros quince Tracks
    /// siguen donde estaban: seleccionar no es un modo, es elegir a quién
    /// escuchan los controles.
    ///
    /// **Y dentro de ese Track, es el Cycle en edición y no el que suena**
    /// (FR8). Con un solo Cycle activo son el mismo, así que nada cambia para
    /// quien no use Cycles.
    public var track: Cycle { pattern.editingCycle(at: selectedTrackIndex)! }

    /// La superficie de pads vigente: qué altura tiene cada uno de los
    /// dieciséis.
    ///
    /// **Es lo que sustituye al filtro cromático.** Hasta la rebanada 7 el
    /// número de nota entrante era la altura y el marco decidía si pasaba;
    /// ahora el número solo dice qué pad se pulsó y la altura sale de aquí.
    ///
    /// **Se calcula, no se guarda** (v2). El marco y el registro son del Track
    /// seleccionado, así que guardarla aparte sería un segundo sitio donde
    /// pueden discrepar: cambiar de Track dejaría la superficie del anterior.
    public var surface: PadSurface {
        PadSurface(frame: track.frame, octaveShift: track.padOctaveShift)
    }

    /// El marco tonal del Track seleccionado: de qué escala salen los grados de
    /// sus pads.
    ///
    /// Se puede cambiar en caliente porque Scale y Root son configuración
    /// táctil, y cambiarlas **reencuadra el pool** en vez de vaciarlo. **Es del
    /// Track** desde la v2: dos Tracks pueden estar en tonalidades distintas.
    public var frame: TonalFrame { track.frame }

    /// Qué Track está seleccionado, 0 el primero.
    ///
    /// **La semántica final es la de v2** —el step button N selecciona el
    /// Track N— y se implementa entera aquí, con un solo Track detrás en v1.
    /// Es lo que evita que el preset haya que reescribirlo cuando los haya: los
    /// números del controlador ya significan lo correcto.
    public private(set) var selectedTrackIndex = 0

    /// Cuántos Tracks hay detrás de los step buttons. **Uno en v1.**
    ///
    /// Es la costura por donde entra v2: los step buttons sin Track detrás se
    /// ignoran en silencio, con el mismo criterio que un CC sin asignar.
    private let trackCount: Int

    private let publish: @Sendable (Pattern) -> Void
    private let mapping: ControlMapping
    private let encoding: RelativeEncoding

    /// Dónde van los gestos de mezcla, si alguien los recoge.
    private let mix: (@Sendable (MixGesture) -> Void)?

    /// **Qué step buttons son modificadores: el 16 para mute, el 15 para solo.**
    ///
    /// Están aquí y no en `ControlMapping` a propósito. La tabla describe el
    /// hardware —dieciséis step buttons contiguos desde un CC— y quien acota
    /// qué significan es el consumidor, con el mismo criterio que ya rige para
    /// los índices sin Track detrás desde `ui-declutter`.
    ///
    /// Los dos quedaron libres al bajar el Pattern a doce Tracks: el gesto no le
    /// quita nada a la selección.
    static let muteModifierIndex = ControlMapping.controlsPerFamily - 1
    static let soloModifierIndex = ControlMapping.controlsPerFamily - 2

    /// Si los modificadores están hundidos ahora mismo.
    ///
    /// **Es estado de mensajes, no un temporizador.** El controlador manda 127
    /// al pulsar y 0 al soltar, así que «mantenido» se sabe sin diferir nada ni
    /// medir cuánto duró una pulsación.
    private var holdingMuteModifier = false
    private var holdingSoloModifier = false

    /// - Parameter publish: dónde van los dieciséis Tracks resultantes de cada
    ///   giro.
    ///
    ///   Es un cierre y no un `PatternHandoff` porque quien publica en producto es
    ///   el transporte, que tiene el suyo propio: pasarle otro haría que el
    ///   scheduler leyera de un sitio y los knobs escribieran en otro.
    public init(
        pattern: Pattern,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publish: @escaping @Sendable (Pattern) -> Void,
        mapping: ControlMapping = .beatStepPro,
        encoding: RelativeEncoding = .twosComplement,
        trackCount: Int = Pattern.trackCount,
        mix: (@Sendable (MixGesture) -> Void)? = nil
    ) {
        // El marco llega por parámetro para no romper a quien construye con uno
        // suelto, y se reparte a los dieciséis: a partir de aquí cada Track
        // lleva el suyo.
        var seeded = pattern
        for index in 0..<Pattern.trackCount {
            seeded = seeded.replacing(seeded.cycle(at: index)!.with(frame: frame), at: index)
        }
        self.pattern = seeded
        self.publish = publish
        self.mapping = mapping
        self.encoding = encoding
        self.trackCount = trackCount
        self.mix = mix
    }

    /// Atajo para quien todavía piensa en un Track: lo pone en la primera
    /// posición y deja los otros quince vacíos.
    ///
    /// Vive para los tests que miden un Track suelto —siguen siendo la mayoría—
    /// y no para el producto, que publica el Pattern entero.
    public convenience init(
        track: Cycle,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publish: @escaping @Sendable (Pattern) -> Void,
        mapping: ControlMapping = .beatStepPro,
        encoding: RelativeEncoding = .twosComplement,
        trackCount: Int = Pattern.trackCount,
        mix: (@Sendable (MixGesture) -> Void)? = nil
    ) {
        self.init(
            pattern: Pattern().replacing(track, at: 0),
            frame: frame,
            publish: publish,
            mapping: mapping,
            encoding: encoding,
            trackCount: trackCount,
            mix: mix
        )
    }

    /// Publica directamente en un handoff. Atajo para tests y para quien no
    /// tenga un transporte de por medio.
    /// Atajo para quien todavía piensa en un Track: lo pone en la primera
    /// posición.
    public convenience init(
        track: Cycle,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publishingTo handoff: PatternHandoff,
        mapping: ControlMapping = .beatStepPro,
        encoding: RelativeEncoding = .twosComplement,
        trackCount: Int = Pattern.trackCount
    ) {
        self.init(
            pattern: Pattern().replacing(track, at: 0),
            frame: frame,
            publishingTo: handoff,
            mapping: mapping,
            encoding: encoding,
            trackCount: trackCount
        )
    }

    /// Publica los dieciséis directamente en un handoff.
    public convenience init(
        pattern: Pattern,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publishingTo handoff: PatternHandoff,
        mapping: ControlMapping = .beatStepPro,
        encoding: RelativeEncoding = .twosComplement,
        trackCount: Int = Pattern.trackCount
    ) {
        self.init(
            pattern: pattern,
            frame: frame,
            publish: { handoff.publish($0) },
            mapping: mapping,
            encoding: encoding,
            trackCount: trackCount
        )
    }

    /// Procesa un mensaje entrante.
    ///
    /// Devuelve si el mensaje cambió algo y por tanto se publicó. **No publicar
    /// no es un fallo:** llegan mensajes que no son de control, controladores
    /// sin mapear y giros nulos, y ninguno de los tres es un error del que haya
    /// que informar. Publicar sin cambio, en cambio, sí sería trabajo y ruido
    /// para nada.
    ///
    /// Processes a MIDI message and publishes the resulting track when it changes.
    /// - Parameter message: The MIDI message to process.
    /// - Returns: `true` if the message changes and publishes the track, `false` otherwise.
    @discardableResult
    public func receive(_ message: MIDIMessage) -> Bool {
        switch message {
        case .controlChange(_, let controller, let value):
            // Un step button no es un knob: se despacha antes, y su soltada
            // —valor cero— no hace nada, igual que el note-off de un pad.
            if let index = mapping.stepButtonIndex(for: controller) {
                return stepButton(index, value: value)
            }
            return turn(controller, by: value)
        case .noteOn(_, let note, let velocity):
            // Velocity cero es la convención de apagado de muchos
            // controladores. Alternar en la pulsación **y** en la soltada sería
            // no alternar: cada pad dejaría el pool como estaba.
            guard velocity.value > 0 else { return false }
            return press(note)
        case .noteOff:
            return false
        }
    }

    /// Qué hace un step button: seleccionar, modificar, o pedir un gesto de
    /// mezcla.
    ///
    /// **El orden importa.** Primero se atiende a los modificadores —que no
    /// hacen nada por sí solos— y solo después se mira si hay uno mantenido. Un
    /// modificador que además seleccionara sería un modificador que se dispara
    /// sin querer.
    ///
    /// **Con los dos mantenidos manda el de mute.** Cuál gane da igual mientras
    /// gane siempre el mismo: un gesto que a veces mutea y a veces solea es peor
    /// que cualquiera de las dos respuestas.
    ///
    /// **La soltada del step button no repite nada**, con el mismo criterio que
    /// el note-off de un pad: alternar en la pulsación *y* en la soltada sería
    /// no alternar.
    private func stepButton(_ index: Int, value: UInt8) -> Bool {
        if index == Self.muteModifierIndex {
            holdingMuteModifier = value > 0
            return false
        }
        if index == Self.soloModifierIndex {
            holdingSoloModifier = value > 0
            return false
        }

        guard value > 0 else { return false }

        if holdingMuteModifier || holdingSoloModifier {
            // Sin Track detrás no hay nada que mutear, con el mismo criterio que
            // rige para la selección desde `ui-declutter`.
            guard index < trackCount else { return false }
            // **No se cae de vuelta a seleccionar si nadie recoge el gesto.**
            // Con el modificador hundido, el usuario no está pidiendo cambiar de
            // Track: que la falta de oyente moviera la selección sería la peor
            // forma de fallar.
            guard let mix else { return false }
            mix(holdingMuteModifier ? .mute(index) : .solo(index))
            return true
        }

        return selectTrack(index)
    }

    /// Da por soltados los modificadores.
    ///
    /// **Lo llama quien reconecta la entrada** (FR8): un cable desenchufado con
    /// el botón hundido dejaría el modificador pegado para siempre, porque la
    /// soltada que lo levantaría ya no va a llegar por ningún sitio.
    public func releaseModifiers() {
        holdingMuteModifier = false
        holdingSoloModifier = false
    }

    /// Un giro de knob mueve un parámetro del Track, sea de la familia que sea.
    ///
    /// **Aquí ya no se sabe a qué familia pertenece, y es el objetivo.** Hasta
    /// la rebanada 5 esto llamaba a `Shape.applying(_:to:)` y por tanto solo
    /// podía mover Shape; con Groove en el snapshot, el despacho lo hace
    /// `Track.applying(_:to:)`, que es quien conoce las dos. Añadir Timing y
    /// Applies a MIDI controller adjustment to the corresponding track parameter.
    /// - Parameters:
    ///   - controller: The MIDI controller whose mapped parameter should change.
    ///   - value: The controller value used to calculate the parameter adjustment.
    /// - Returns: `true` if the track changed and was published, `false` otherwise.
    private func turn(_ controller: MIDIController, by value: UInt8) -> Bool {
        // El knob del Cycle se despacha antes: no mueve un parámetro del Cycle
        // sino a cuál de ellos apuntan los demás.
        if controller == mapping.editingCycleController {
            return moveEditingCycle(by: encoding.delta(from: value))
        }

        guard let parameter = mapping.parameter(for: controller) else { return false }

        let delta = encoding.delta(from: value)
        guard delta != 0 else { return false }

        // **El resto del Track se conserva.** Shape, pool y Groove son partes
        // del mismo valor: reconstruirlo sin alguna de ellas borraría material
        // al girar un knob, que es exactamente la destrucción que
        // `product-guidelines.md` prohíbe. `Track.applying(_:to:)` lo garantiza.
        let adjusted = track.applying(delta, to: parameter)

        // Girar contra un extremo no mueve nada: el valor ya estaba ahí.
        guard adjusted != track else { return false }

        pattern = pattern.replacing(adjusted, at: selectedTrackIndex)
        publish(pattern)
        return true
    }

    /// Un pad alterna la pertenencia de su altura al pool.
    ///
    /// **El número de nota solo dice qué pad se pulsó.** La altura la pone la
    /// superficie, así que ya no hay nada que filtrar: todo lo que un pad puede
    /// meter en el pool sale de la escala por construcción.
    ///
    /// Se ignoran en silencio, con el mismo criterio que un CC sin asignar: una
    /// nota fuera del bloque de pads, un pad sin grado —los que sobran cuando la
    /// escala tiene menos de siete— y los pads de octava, que desplazan en vez
    /// de sonar. Ninguno es un error: en una sesión real llegan mensajes de todo
    /// tipo.
    private func press(_ note: MIDINote) -> Bool {
        guard let index = mapping.padIndex(for: note) else { return false }

        // Los dos pads de octava se despachan antes de llegar al pool: mueven la
        // superficie, no el material.
        switch index {
        case PadSurface.octaveDownIndex: return shift { $0.shiftedDown() }
        case PadSurface.octaveUpIndex: return shift { $0.shiftedUp() }
        default: break
        }

        guard let pitch = surface.pitch(at: index) else { return false }

        let adjusted = track.pool.toggling(pitch)
        // El pool lleno rechaza la novena: no cambió nada que publicar.
        guard adjusted != track.pool else { return false }

        pattern = pattern.replacing(track.with(pool: adjusted), at: selectedTrackIndex)
        publish(pattern)
        return true
    }

    /// Un step button selecciona el Track de su posición.
    ///
    /// **En v1 solo el primero tiene Track detrás**; los otros quince se ignoran
    /// en silencio, con el mismo criterio que un CC sin asignar. Seleccionar el
    /// que ya estaba tampoco publica: es una operación sin efecto, no un
    /// reinicio.
    /// Es público porque la pantalla selecciona igual que el step button: sin
    /// controlador conectado es la única vía, y con controlador las dos tienen
    /// que llevar al mismo sitio o la pantalla mentiría.
    @discardableResult
    public func selectTrack(_ index: Int) -> Bool {
        guard index < trackCount, index != selectedTrackIndex else { return false }

        selectedTrackIndex = index
        publish(pattern)
        return true
    }

    /// Los pads 8 y 16 mueven el registro **sin tocar el pool**.
    ///
    /// Las alturas ya metidas se quedan donde estaban: `product-guidelines.md`
    /// dice que cambiar un parámetro nunca destruye material, y transponer el
    /// pool bajo los pies de quien lo construyó es exactamente eso. Lo que
    /// cambia es qué altura mete el pad siguiente, y por eso la superficie es un
    /// teclado de registro móvil: se baja, se meten dos graves, se sube y se
    /// meten dos agudas.
    ///
    /// En el tope no pasa nada y no se publica: mandar un snapshot idéntico es
    /// trabajo y ruido para nada. Lo que sí tiene que enterarse es la pantalla,
    /// que es donde se lee que no se puede seguir.
    private func shift(_ move: (PadSurface) -> PadSurface) -> Bool {
        let moved = move(surface)
        guard moved != surface else { return false }

        pattern = pattern.replacing(
            track.with(padOctaveShift: moved.octaveShift), at: selectedTrackIndex)
        publish(pattern)
        return true
    }

    /// Mueve el Cycle en edición del Track seleccionado.
    ///
    /// **Mueve el cursor de edición y nada más** (FR7): ni el de reproducción,
    /// que es del scheduler, ni una sola nota de material. Se acota al rango
    /// activo, no a los dieciséis: no se edita un Cycle que no se recorre.
    ///
    /// Girar contra un extremo no publica, por la misma razón que Steps o
    /// Division: mandar un snapshot idéntico es trabajo y ruido para nada.
    private func moveEditingCycle(by delta: Int) -> Bool {
        guard delta != 0, let current = pattern.track(at: selectedTrackIndex) else {
            return false
        }

        let moved = current.withEditing(current.editing + delta)
        guard moved != current else { return false }

        pattern = pattern.replacing(moved, at: selectedTrackIndex)
        publish(pattern)
        return true
    }

    /// Cambia el canal por el que emite el Track seleccionado.
    ///
    /// **Se edita en pantalla y no con un knob**: es configuración, no material
    /// generativo, y `product-guidelines.md` pone esa frontera del lado táctil,
    /// donde ya están Scale y Root. Ningún CC llega hasta aquí.
    ///
    /// Publica porque el scheduler lee el canal del snapshot en cada evento: sin
    /// publicar, el cambio no se oiría hasta el giro siguiente de cualquier
    /// knob.
    @discardableResult
    public func setChannel(_ channel: Channel) -> Bool {
        setChannel(channel, forTrack: selectedTrackIndex)
    }

    /// Cambia el canal de **cualquier** Track, sin seleccionarlo antes.
    ///
    /// **Es lo que necesita la pantalla MIDI** (FR6), que enseña el ruteo de los
    /// doce a la vez. Pasar por la selección para ajustar un canal movería
    /// también a dónde apuntan los knobs y los pads, que es un efecto que nadie
    /// pidió: elegir instrumento y elegir a quién se edita son dos cosas
    /// distintas y esta pantalla solo hace la primera.
    ///
    /// Un índice fuera de los doce no publica y no es un error — mismo criterio
    /// que un CC sin asignar o un step button sin Track detrás.
    ///
    /// Publica porque el scheduler lee el canal del snapshot en cada evento: sin
    /// publicar, el cambio no se oiría hasta el giro siguiente de cualquier
    /// knob.
    @discardableResult
    public func setChannel(_ channel: Channel, forTrack index: Int) -> Bool {
        guard let cycle = pattern.editingCycle(at: index), channel != cycle.channel else {
            return false
        }

        pattern = pattern.replacing(cycle.on(channel), at: index)
        publish(pattern)
        return true
    }

    /// Cambia cuántos Cycles recorre el Track seleccionado, de 1 a 16.
    ///
    /// **Se ajusta en pantalla y no con un knob**: es configuración, no material
    /// generativo, y `product-guidelines.md` pone esa frontera del lado táctil,
    /// donde ya están Scale, Root y el canal. Ningún CC llega hasta aquí, y hay
    /// un test que barre los 128 para vigilarlo.
    ///
    /// La Pre Spec lo ponía en un gesto de CTRL sobre el knob de Cycles y el
    /// BeatStep Pro no tiene CTRL; la nota fechada del 2026-09-02 en la Pre Spec
    /// explica por qué la frontera correcta no es la del hardware.
    ///
    /// Subir el número entrega un Cycle copiado del que se está editando y no
    /// uno vacío (FR3); bajar descarta por el final y acota el Cycle en edición,
    /// sin tocar el de reproducción (FR9). Las tres reglas viven en `Track`, que
    /// es donde se testean sin controlador de por medio.
    ///
    /// Publica porque el scheduler lee cuántos hay activos del snapshot: sin
    /// publicar, el cambio no llegaría hasta el giro siguiente de cualquier knob.
    @discardableResult
    public func setActiveCycleCount(_ count: Int) -> Bool {
        guard let current = pattern.track(at: selectedTrackIndex) else { return false }

        let adjusted = current.withActiveCount(count)
        guard adjusted != current else { return false }

        pattern = pattern.replacing(adjusted, at: selectedTrackIndex)
        publish(pattern)
        return true
    }

    /// Cambia el marco tonal y reencuadra el pool.
    ///
    /// **Reencuadra, no vacía** (`product-guidelines.md`). Publicar solo si algo
    /// cambió evita mandar un snapshot idéntico cuando el pool ya estaba dentro
    /// del marco nuevo.
    @discardableResult
    public func setFrame(_ frame: TonalFrame) -> Bool {
        // El marco es del Track seleccionado, y el registro de sus pads se
        // conserva: cambiar de escala no mueve a nadie de octava.
        let reframed = track.with(pool: track.pool.reframed(to: frame)).with(frame: frame)
        guard reframed != track else { return false }

        pattern = pattern.replacing(reframed, at: selectedTrackIndex)
        publish(pattern)
        return true
    }
}
