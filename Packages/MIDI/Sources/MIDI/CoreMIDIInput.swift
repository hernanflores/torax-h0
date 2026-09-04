import CoreMIDI
import Foundation

public enum MIDIInputError: Error, Equatable {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
}

/// Entrada MIDI por CoreMIDI.
///
/// Es el espejo de `CoreMIDIOutput`: enumera las fuentes del sistema, se conecta
/// a una y entrega los mensajes que llegan ya parseados.
///
/// **Cierre explícito desde el primer commit.** `CoreMIDIOutput` destruye sus
/// recursos en `deinit`, es decir, en el instante en que ARC decida liberar el
/// objeto, y el track `scheduler-lifecycle_20260826` documenta lo caro que sale
/// no controlar ese momento. Aquí hay un `close()` ordenado desde el principio
/// —desconectar, puerto, cliente— y `deinit` es solo la red de seguridad.
///
/// `@unchecked Sendable`: tras `init` los handles de CoreMIDI son de solo
/// lectura, y el único estado mutable —los callbacks— vive tras un lock.
public final class CoreMIDIInput: @unchecked Sendable {

    /// Se invoca por cada mensaje que llega, ya parseado y con el instante que
    /// trae el paquete.
    ///
    /// **Corre en el hilo de recepción de CoreMIDI**, no en el principal ni en
    /// el del scheduler. Quien lo implemente debe hacer poco y no bloquear.
    ///
    /// **El instante es el del paquete, no el de ahora.** Para los knobs da
    /// igual, pero el reloj de un maestro externo vive de cuándo llegó cada
    /// tick: preguntar la hora aquí metería en la estimación el retraso de
    /// llegar hasta aquí, y CoreMIDI ya trae el dato bueno.
    ///
    /// Un timestamp de cero significa «ahora» en CoreMIDI; se traduce antes de
    /// entregarlo para que quien lo reciba no tenga que conocer esa convención.
    public typealias ReceiveHandler = @Sendable (MIDIMessage, MIDITimeStamp) -> Void

    /// Contenedor del callback de notificaciones, igual que en la salida: el
    /// bloque llega desde el hilo de CoreMIDI, así que el acceso va con lock.
    /// No es código de tiempo real.
    private final class NotificationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (() -> Void)?

        var onSetupChanged: (() -> Void)? {
            get { lock.withLock { handler } }
            set { lock.withLock { handler = newValue } }
        }
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef?
    private let notifications = NotificationBox()
    private let closed = AtomicFlag(false)

    public var isClosed: Bool { closed.value }

    /// Se invoca cuando el conjunto de dispositivos MIDI cambia.
    ///
    /// Es el único mecanismo fiable para enterarse de que una fuente
    /// desapareció. Llega desde el hilo de CoreMIDI, no del principal.
    public var onSetupChanged: (() -> Void)? {
        get { notifications.onSetupChanged }
        set { notifications.onSetupChanged = newValue }
    }

    public init(clientName: String = "Torax H-0 Input", onReceive handler: @escaping ReceiveHandler)
        throws
    {
        let box = notifications
        let clientStatus = MIDIClientCreateWithBlock(clientName as CFString, &client) {
            notification in
            if notification.pointee.messageID == .msgSetupChanged {
                box.onSetupChanged?()
            }
        }
        guard clientStatus == noErr else {
            throw MIDIInputError.clientCreationFailed(clientStatus)
        }

        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "Input" as CFString, ._1_0, &inputPort
        ) { eventList, _ in
            // Se recorre sobre el puntero original y no sobre una copia por
            // valor: `MIDIEventList` solo lleva dentro el primer paquete, y los
            // siguientes viven en memoria de longitud variable detrás del
            // puntero. Mismo motivo que en `VirtualLoopback`.
            //
            // El `!` está justificado: `offset(of:)` solo devuelve `nil` para
            // propiedades sin dirección estable, y `MIDIEventList` es una
            // estructura de C con disposición fija.
            let numPackets = eventList.pointee.numPackets
            var packet = UnsafeMutableRawPointer(mutating: eventList)
                .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)

            for _ in 0..<numPackets {
                let wordCount = Int(packet.pointee.wordCount)
                let hostTime = HostClock.arrival(packet.pointee.timeStamp)
                withUnsafeBytes(of: packet.pointee.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    for index in 0..<min(wordCount, words.count) {
                        // Lo que no se entiende se descarta en silencio: por el
                        // cable llegan relojes y mensajes que no se usan.
                        if let message = MIDIMessage(universalPacketWord: words[index]) {
                            handler(message, hostTime)
                        }
                    }
                }
                packet = MIDIEventPacketNext(packet)
            }
        }

        guard portStatus == noErr else {
            MIDIClientDispose(client)
            throw MIDIInputError.portCreationFailed(portStatus)
        }
    }

    /// Fuentes MIDI presentes en el sistema.
    ///
    /// No es código de tiempo real: consultar nombres asigna memoria y se hace
    /// al poblar la interfaz.
    public func availableSources() -> [MIDIEndpointInfo] {
        guard !closed.value else { return [] }
        return (0..<MIDIGetNumberOfSources()).map { index in
            let endpoint = MIDIGetSource(index)
            return MIDIEndpointInfo(
                endpoint: endpoint,
                displayName: CoreMIDIOutput.displayName(of: endpoint)
            )
        }
    }

    /// Escucha una fuente, dejando de escuchar la anterior.
    ///
    /// Devuelve si se pudo conectar. Fallar no es excepcional: la fuente pudo
    /// desaparecer entre que se enumeró y que se eligió.
    @discardableResult
    public func connect(to source: MIDIEndpointRef) -> Bool {
        guard !closed.value else { return false }
        disconnect()

        guard MIDIPortConnectSource(inputPort, source, nil) == noErr else { return false }
        connectedSource = source
        return true
    }

    /// Deja de escuchar la fuente conectada, si hay alguna.
    public func disconnect() {
        guard let source = connectedSource else { return }
        MIDIPortDisconnectSource(inputPort, source)
        connectedSource = nil
    }

    /// Cierra la entrada en orden: desconectar la fuente, el puerto, el cliente.
    ///
    /// Idempotente. Ver la nota del tipo sobre por qué es explícito.
    public func close() {
        guard !closed.value else { return }
        closed.value = true

        notifications.onSetupChanged = nil
        disconnect()
        MIDIPortDispose(inputPort)
        MIDIClientDispose(client)
        inputPort = MIDIPortRef()
        client = MIDIClientRef()
    }

    /// Red de seguridad idempotente, no el mecanismo principal.
    deinit {
        close()
    }
}
