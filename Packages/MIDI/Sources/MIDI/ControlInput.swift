import Engine

/// Convierte los mensajes de un controlador en Tracks publicados.
///
/// Es la pieza que cierra la cadena del track: decodifica el giro, lo traduce al
/// parámetro que le toca, se lo aplica al Shape vigente y publica el `Track`
/// resultante por el `TrackHandoff` que la rebanada 1 dejó probado. Girar un
/// knob y publicar un snapshot son, a partir de aquí, la misma cosa.
///
/// **Corre en el hilo de control, nunca en el del scheduler.** Recibir un
/// mensaje asigna memoria —construir un Shape reparte los Pulses— y eso está
/// prohibido en el camino de timing. La separación es la misma que ya usa
/// `TrackHandoff`: un solo escritor publica, el scheduler solo lee.
public final class ControlInput: @unchecked Sendable {

    /// Track vigente, con los giros ya aplicados.
    ///
    /// Se guarda aquí y no se relee del handoff porque `load()` puede descartar
    /// una lectura, y perder un giro por eso sería un knob que no responde.
    public private(set) var track: Track

    /// La superficie de pads vigente: qué altura tiene cada uno de los
    /// dieciséis.
    ///
    /// **Es lo que sustituye al filtro cromático.** Hasta la rebanada 7 el
    /// número de nota entrante era la altura y el marco decidía si pasaba;
    /// ahora el número solo dice qué pad se pulsó y la altura sale de aquí.
    public private(set) var surface: PadSurface

    /// El marco tonal vigente: de qué escala salen los grados de los pads.
    ///
    /// Se puede cambiar en caliente porque Scale y Root son configuración
    /// táctil, y cambiarlas **reencuadra el pool** en vez de vaciarlo.
    public var frame: TonalFrame { surface.frame }

    private let publish: @Sendable (Track) -> Void
    private let mapping: ControlMapping
    private let encoding: RelativeEncoding

    /// - Parameter publish: dónde va el Track resultante de cada giro.
    ///
    ///   Es un cierre y no un `TrackHandoff` porque quien publica en producto es
    ///   el transporte, que tiene el suyo propio: pasarle otro haría que el
    ///   scheduler leyera de un sitio y los knobs escribieran en otro.
    public init(
        track: Track,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publish: @escaping @Sendable (Track) -> Void,
        mapping: ControlMapping = .provisional,
        encoding: RelativeEncoding = .twosComplement
    ) {
        self.track = track
        self.surface = PadSurface(frame: frame)
        self.publish = publish
        self.mapping = mapping
        self.encoding = encoding
    }

    /// Publica directamente en un handoff. Atajo para tests y para quien no
    /// tenga un transporte de por medio.
    public convenience init(
        track: Track,
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publishingTo handoff: TrackHandoff,
        mapping: ControlMapping = .provisional,
        encoding: RelativeEncoding = .twosComplement
    ) {
        self.init(
            track: track,
            frame: frame,
            publish: { handoff.publish($0) },
            mapping: mapping,
            encoding: encoding
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

        track = adjusted
        publish(track)
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

        track = Track(shape: track.shape, pool: adjusted)
        publish(track)
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

        surface = moved
        publish(track)
        return true
    }

    /// Cambia el marco tonal y reencuadra el pool.
    ///
    /// **Reencuadra, no vacía** (`product-guidelines.md`). Publicar solo si algo
    /// cambió evita mandar un snapshot idéntico cuando el pool ya estaba dentro
    /// del marco nuevo.
    @discardableResult
    public func setFrame(_ frame: TonalFrame) -> Bool {
        surface = PadSurface(frame: frame, octaveShift: surface.octaveShift)

        let adjusted = track.pool.reframed(to: frame)
        guard adjusted != track.pool else { return false }

        track = Track(shape: track.shape, pool: adjusted)
        publish(track)
        return true
    }
}
