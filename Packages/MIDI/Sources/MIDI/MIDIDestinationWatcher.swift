import Foundation

/// Mantiene la lista de destinos al día ante los cambios del sistema.
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
public final class MIDIDestinationWatcher: @unchecked Sendable {

    /// Estado vigente de la salida.
    public private(set) var selection: MIDIDestinationSelection

    /// Se invoca cuando la lista o la elección cambian de verdad.
    ///
    /// No se invoca por notificaciones que no cambian nada: CoreMIDI emite
    /// `msgSetupChanged` por cambios que no afectan a los destinos, y agitar la
    /// interfaz con ellos sería ruido.
    public var onChange: ((MIDIDestinationSelection) -> Void)?

    private let enumerate: () -> [MIDIDestination]
    private let deliver: (@escaping () -> Void) -> Void

    /// - Parameters:
    ///   - enumerating: enumera los destinos del sistema. En producto,
    ///     `CoreMIDIOutput.availableDestinations`.
    ///   - delivering: dónde se aplica el cambio de estado. Por defecto el hilo
    ///     principal, porque la notificación de CoreMIDI llega desde el suyo y
    ///     el estado lo lee la interfaz.
    public init(
        enumerating: @escaping () -> [MIDIDestination],
        delivering: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.enumerate = enumerating
        self.deliver = delivering
        self.selection = MIDIDestinationSelection(discovering: enumerating())
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
        let refreshed = selection.refreshed(with: enumerate())
        guard refreshed != selection else { return }

        deliver { [weak self] in
            guard let self else { return }
            selection = refreshed
            onChange?(refreshed)
        }
    }
}
