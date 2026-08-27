import CoreMIDI
import Foundation

/// Resultado de un intento de envío.
///
/// La desconexión de un dispositivo es un **estado esperado**, no un error
/// excepcional: en un secuenciador, desenchufar el cable a media sesión es algo
/// que pasa. Por eso el envío devuelve un resultado en vez de lanzar.
public enum MIDISendResult: Equatable, Sendable {
    /// Entregado a CoreMIDI para su emisión en el timestamp indicado.
    case sent
    /// El destino ya no existe: se desconectó o desapareció.
    case destinationUnavailable
    /// Fallo real de CoreMIDI, con su código.
    case failed(OSStatus)

    /// Traduce un `OSStatus` de CoreMIDI al resultado correspondiente.
    ///
    /// **No sirve para detectar desconexiones.** Medido en macOS: enviar a un
    /// endpoint inexistente devuelve `noErr` — CoreMIDI acepta el mensaje y lo
    /// descarta en silencio, sin validar el destino de forma síncrona. La
    /// desconexión se detecta por notificación (`onSetupChanged`), no por el
    /// resultado del envío.
    ///
    /// Esta clasificación sigue siendo útil para los casos en que CoreMIDI sí
    /// devuelve un código, pero no puede ser el mecanismo principal.
    static func classify(_ status: OSStatus) -> MIDISendResult {
        switch status {
        case noErr:
            .sent
        case kMIDIObjectNotFound, kMIDIInvalidClient, kMIDIInvalidPort, kMIDIUnknownEndpoint:
            .destinationUnavailable
        default:
            .failed(status)
        }
    }
}

public enum MIDIOutputError: Error, Equatable {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
}

/// Un destino MIDI disponible.
public struct MIDIDestination: Equatable, Sendable {
    public let endpoint: MIDIEndpointRef
    public let displayName: String
}

/// Salida MIDI por CoreMIDI.
///
/// Envía con `MIDISendEventList` y un **timestamp de entrega futuro**: CoreMIDI
/// se encarga de emitir el evento en ese instante exacto. Esa es la pieza que
/// hace que el jitter deje de depender de cuándo despierta el hilo del
/// scheduler (`conductor/tech-stack.md`).
/// `@unchecked Sendable`: tras `init` los dos handles de CoreMIDI son de solo
/// lectura, `MIDISendEventList` es seguro entre hilos, y el único estado mutable
/// —el callback de notificaciones— vive tras un lock.
public final class CoreMIDIOutput: @unchecked Sendable {

    /// Contenedor del callback de notificaciones.
    ///
    /// CoreMIDI invoca el bloque desde su propio hilo, así que el acceso va con
    /// lock. No es código de tiempo real —las notificaciones de conexión son
    /// esporádicas y no ocurren en el camino del scheduler—, por lo que el lock
    /// aquí no viola la regla de `swift.md`.
    private final class NotificationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (() -> Void)?

        var onSetupChanged: (() -> Void)? {
            get { lock.withLock { handler } }
            set { lock.withLock { handler = newValue } }
        }
    }

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private let notifications = NotificationBox()

    /// Si la salida ya se cerró.
    ///
    /// Va en una bandera atómica y no en un `Bool` porque `close()` se llama
    /// desde el hilo de control mientras `send(_:to:atHostTime:)` puede estar
    /// ejecutándose en el del scheduler. Leerla ahí es una carga atómica: sin
    /// lock y sin asignaciones, como exige el camino de tiempo real.
    private let closed = AtomicFlag(false)

    public var isClosed: Bool { closed.value }

    /// Se invoca cuando el conjunto de dispositivos MIDI cambia: conexión o
    /// desconexión.
    ///
    /// Es el único mecanismo fiable para enterarse de que un destino
    /// desapareció, porque el resultado del envío no lo reporta. Quien lo use
    /// debe volver a consultar `availableDestinations()`.
    ///
    /// El bloque llega desde el hilo de CoreMIDI, no desde el principal.
    public var onSetupChanged: (() -> Void)? {
        get { notifications.onSetupChanged }
        set { notifications.onSetupChanged = newValue }
    }

    public init(clientName: String = "Torax H-0") throws {
        let box = notifications
        let clientStatus = MIDIClientCreateWithBlock(clientName as CFString, &client) { notification in
            if notification.pointee.messageID == .msgSetupChanged {
                box.onSetupChanged?()
            }
        }
        guard clientStatus == noErr else {
            throw MIDIOutputError.clientCreationFailed(clientStatus)
        }

        let portStatus = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            throw MIDIOutputError.portCreationFailed(portStatus)
        }
    }

    /// Cierra la salida en orden: primero el puerto, después el cliente.
    ///
    /// **Por qué explícito y no en `deinit`.** `deinit` ocurre cuando ARC decide
    /// liberar el objeto, y ese instante puede caer dentro de la ventana en la
    /// que CoreMIDI todavía está emitiendo eventos ya sellados con timestamp
    /// futuro. Destruir el puerto ahí inutiliza la conexión MIDI del proceso:
    /// las siguientes llamadas a `MIDIClientCreateWithBlock` devuelven
    /// `paramErr`. Cerrar explícitamente devuelve ese momento a quien sí sabe
    /// cuándo es seguro.
    ///
    /// Es idempotente: cerrar dos veces no vuelve a destruir nada.
    ///
    /// No es código de tiempo real. Se llama desde el hilo de control.
    public func close() {
        guard !closed.value else { return }
        closed.value = true

        // Antes que nada, cortar el aviso: no pueden llegar notificaciones
        // sobre una salida que ya no existe.
        notifications.onSetupChanged = nil

        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
        outputPort = MIDIPortRef()
        client = MIDIClientRef()
    }

    /// Red de seguridad idempotente, no el mecanismo principal.
    deinit {
        close()
    }

    /// Destinos MIDI presentes en el sistema.
    ///
    /// No es código de tiempo real: consultar nombres asigna memoria y se hace
    /// solo al poblar la interfaz, nunca en el camino del scheduler.
    public func availableDestinations() -> [MIDIDestination] {
        (0..<MIDIGetNumberOfDestinations()).map { index in
            let endpoint = MIDIGetDestination(index)
            return MIDIDestination(endpoint: endpoint, displayName: Self.displayName(of: endpoint))
        }
    }

    private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        guard status == noErr, let name else { return "Unknown" }
        return name.takeRetainedValue() as String
    }

    /// Envía un mensaje para que se emita en `hostTime`.
    ///
    /// El `MIDIEventList` se construye en la pila y se rellena por puntero: no
    /// hay array intermedio ni asignación en el camino de envío.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    @discardableResult
    public func send(
        _ message: MIDIMessage,
        to destination: MIDIEndpointRef,
        atHostTime hostTime: MIDITimeStamp
    ) -> MIDISendResult {
        // Enviar por una salida cerrada es un estado esperado, no un error: el
        // destino ya no existe, igual que al desenchufar el cable.
        guard !closed.value else { return .destinationUnavailable }

        var eventList = MIDIEventList()
        var word = message.universalPacketWord(group: 0)

        var packet = MIDIEventListInit(&eventList, ._1_0)
        packet = MIDIEventListAdd(
            &eventList,
            MemoryLayout<MIDIEventList>.size,
            packet,
            hostTime,
            1,
            &word
        )

        return MIDISendResult.classify(MIDISendEventList(outputPort, destination, &eventList))
    }
}
