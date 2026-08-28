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

    private let handoff: TrackHandoff
    private let mapping: ControlMapping
    private let encoding: RelativeEncoding

    public init(
        track: Track,
        publishingTo handoff: TrackHandoff,
        mapping: ControlMapping = .provisional,
        encoding: RelativeEncoding = .twosComplement
    ) {
        self.track = track
        self.handoff = handoff
        self.mapping = mapping
        self.encoding = encoding
    }

    /// Procesa un mensaje entrante.
    ///
    /// Devuelve si el mensaje cambió algo y por tanto se publicó. **No publicar
    /// no es un fallo:** llegan mensajes que no son de control, controladores
    /// sin mapear y giros nulos, y ninguno de los tres es un error del que haya
    /// que informar. Publicar sin cambio, en cambio, sí sería trabajo y ruido
    /// para nada.
    ///
    /// No es código de tiempo real. Se llama desde el hilo de control.
    @discardableResult
    public func receive(_ message: MIDIMessage) -> Bool {
        guard case let .controlChange(_, controller, value) = message,
              let parameter = mapping.parameter(for: controller)
        else { return false }

        let delta = encoding.delta(from: value)
        guard delta != 0 else { return false }

        let adjusted = track.shape.applying(delta, to: parameter)
        // Girar contra un extremo no mueve nada: el valor ya estaba ahí.
        guard adjusted != track.shape else { return false }

        track = Track(shape: adjusted)
        handoff.publish(track)
        return true
    }
}
