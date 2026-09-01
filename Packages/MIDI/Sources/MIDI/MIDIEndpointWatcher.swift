import Foundation

/// Mantiene la lista de endpoints al día ante los cambios del sistema.
///
/// Sirve tanto para destinos como para fuentes: el papel decide qué es elegible
/// y cómo se dice que no hay ninguno, y el resto —enumerar, comparar, avisar—
/// es idéntico.
///
/// **Por qué existe.** La desconexión no se puede detectar por el resultado del
/// envío: está medido que CoreMIDI acepta el mensaje para un endpoint
/// inexistente y lo descarta en silencio, devolviendo `noErr` (ver
/// `MIDISendResult.classify`). El único mecanismo fiable es la notificación
/// `onSetupChanged`, y este tipo es lo que la convierte en una reconsulta.
///
/// **Dependencias inyectadas.** Recibe la enumeración y la entrega como
/// cierres, en vez de hablar con CoreMIDI directamente. No es abstracción por
/// gusto: permite testear la desconexión sin desenchufar nada, que es la única
/// forma de tenerla cubierta en una máquina sin sintetizadores.
public final class MIDIEndpointWatcher: @unchecked Sendable {

    /// Estado vigente de la salida.
    public private(set) var selection: MIDIEndpointSelection

    /// Se invoca cuando la lista o la elección cambian de verdad.
    ///
    /// No se invoca por notificaciones que no cambian nada: CoreMIDI emite
    /// `msgSetupChanged` por cambios que no afectan a los destinos, y agitar la
    /// interfaz con ellos sería ruido.
    public var onChange: ((MIDIEndpointSelection) -> Void)?

    private let enumerate: () -> [MIDIEndpointInfo]
    private let deliver: (@escaping () -> Void) -> Void

    /// Lo último **calculado**, esté entregado o no.
    ///
    /// **No es lo mismo que `selection`, y esa diferencia es el defecto que
    /// arregla.** La notificación llega del hilo de CoreMIDI y el cambio se
    /// aplica donde diga `delivering` —el principal, en producto—, así que entre
    /// las dos cosas hay un hueco. Comparando contra `selection` dentro de ese
    /// hueco, dos avisos seguidos —desenchufar y volver a enchufar, o un reset
    /// del bus— se calculan los dos contra el estado viejo: el segundo parece
    /// «nada que hacer» y la vuelta del dispositivo se pierde. La app se queda
    /// muda con el cable puesto y sin nada que la despierte hasta el aviso
    /// siguiente.
    ///
    /// Comparar contra esto encadena los avisos: cada uno parte de lo que dejó
    /// el anterior.
    private var latest: MIDIEndpointSelection

    /// Protege `latest`, que se toca desde el hilo de CoreMIDI.
    ///
    /// No es código de tiempo real —las notificaciones de conexión son
    /// esporádicas y no ocurren en el camino del scheduler—, así que el lock
    /// aquí no viola la regla de `swift.md`.
    private let lock = NSLock()

    /// - Parameters:
    ///   - role: si son destinos de salida o fuentes de entrada.
    ///   - enumerating: enumera los endpoints del sistema. En producto,
    ///     `CoreMIDIOutput.availableDestinations` o `CoreMIDIInput.availableSources`.
    ///   - delivering: dónde se aplica el cambio de estado. Por defecto el hilo
    ///     principal, porque la notificación de CoreMIDI llega desde el suyo y
    ///     el estado lo lee la interfaz.
    public init(
        _ role: MIDIEndpointRole,
        enumerating: @escaping () -> [MIDIEndpointInfo],
        delivering: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.enumerate = enumerating
        self.deliver = delivering
        let discovered = MIDIEndpointSelection(role, discovering: enumerating())
        self.selection = discovered
        self.latest = discovered
    }

    /// Reacciona a un cambio en el conjunto de dispositivos MIDI.
    ///
    /// Es lo que hay que conectar a `CoreMIDIOutput.onSetupChanged`. Llega desde
    /// el hilo de CoreMIDI, así que el cambio de estado se entrega donde diga
    /// `delivering`.
    ///
    /// No es código de tiempo real: enumerar destinos consulta nombres y asigna
    /// memoria. Las notificaciones de conexión son esporádicas y no ocurren en
    /// el camino del scheduler.
    public func setupChanged() {
        // La reconsulta y la comparación van juntas bajo el lock: separarlas
        // dejaría que dos avisos calcularan sobre el mismo punto de partida,
        // que es justo lo que `latest` existe para evitar.
        let refreshed: MIDIEndpointSelection? = lock.withLock {
            let updated = latest.refreshed(with: enumerate())
            guard updated != latest else { return nil }
            latest = updated
            return updated
        }
        guard let refreshed else { return }

        deliver { [weak self] in
            guard let self else { return }
            selection = refreshed
            onChange?(refreshed)
        }
    }
}
