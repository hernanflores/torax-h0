import CoreMIDI
import Foundation

/// Destino MIDI virtual que devuelve a la app lo que ella misma envía.
///
/// **Solo instrumentación.** Existe para medir jitter: la app se envía a sí
/// misma y compara cuándo pidió que sonara un evento con cuándo llegó de
/// verdad. `tech-stack.md` (enmienda del 2026-08-26) admite endpoints virtuales
/// con este alcance y no como funcionalidad de producto: este endpoint no debe
/// ofrecerse nunca como destino elegible por el usuario.
///
/// **Qué mide y qué no.** Valida el scheduler y la entrega de CoreMIDI. **No**
/// cruza el cable USB, así que la latencia y el jitter del interfaz MIDI quedan
/// fuera de la medición.
/// `@unchecked Sendable`: tras `init` el endpoint es de solo lectura y no hay
/// estado mutable compartido.
public final class VirtualLoopback: @unchecked Sendable {

    /// Se invoca por cada paquete recibido, con el instante que se programó y
    /// el instante real de recepción, ambos en ticks de host.
    ///
    /// **Corre en el hilo de alta prioridad de CoreMIDI.** Quien lo implemente
    /// hereda las reglas de tiempo real: sin asignaciones, sin locks, sin
    /// logging. Cualquier trabajo pesado degrada justo lo que se está midiendo.
    public typealias ReceiveHandler = @Sendable (_ scheduledHostTime: UInt64, _ actualHostTime: UInt64) -> Void

    private var client = MIDIClientRef()
    private var destination = MIDIEndpointRef()

    /// Endpoint al que hay que enviar para cerrar el bucle.
    public var endpoint: MIDIEndpointRef { destination }

    /// Si el loopback ya se cerró.
    ///
    /// Bandera atómica porque el callback de recepción corre en el hilo de alta
    /// prioridad de CoreMIDI mientras `close()` se llama desde el de control.
    private let closed = AtomicFlag(false)

    public var isClosed: Bool { closed.value }

    public init(name: String = "Torax H-0 Loopback", onReceive handler: @escaping ReceiveHandler) throws {
        let clientStatus = MIDIClientCreateWithBlock(name as CFString, &client, nil)
        guard clientStatus == noErr else {
            throw MIDIOutputError.clientCreationFailed(clientStatus)
        }

        let destinationStatus = MIDIDestinationCreateWithProtocol(
            client,
            name as CFString,
            ._1_0,
            &destination
        ) { [closed] eventList, _ in
            // CoreMIDI puede tener una entrega en vuelo en el momento de
            // cerrar. Descartarla aquí es lo que hace que `close()` signifique
            // "no llegan más callbacks" y no solo "ya no escucho".
            guard !closed.value else { return }

            // Se toma el instante ANTES de hacer nada más: cualquier trabajo
            // previo se contabilizaria como jitter que no existe.
            let actual = HostClock.now()

            // Se recorre sobre el puntero original, nunca sobre una copia por
            // valor de la lista: `MIDIEventList` solo lleva dentro el primer
            // paquete, y los siguientes viven en memoria de longitud variable
            // detrás del puntero. Copiar la estructura y avanzar con
            // `MIDIEventPacketNext` leería fuera de la copia a partir del
            // segundo paquete.
            //
            // El `!` está justificado: `offset(of:)` solo devuelve `nil` para
            // propiedades sin dirección estable, y `MIDIEventList` es una
            // estructura de C con disposición fija.
            let numPackets = eventList.pointee.numPackets
            var packet = UnsafeMutableRawPointer(mutating: eventList)
                .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            for _ in 0..<numPackets {
                handler(packet.pointee.timeStamp, actual)
                packet = MIDIEventPacketNext(packet)
            }
        }

        guard destinationStatus == noErr else {
            MIDIClientDispose(client)
            throw MIDIOutputError.portCreationFailed(destinationStatus)
        }
    }

    /// Cierra el loopback en orden: primero el endpoint, después el cliente.
    ///
    /// El orden importa y viene del problema: destruir el cliente antes deja el
    /// endpoint huérfano, y es en ese estado donde el proceso pierde la
    /// capacidad de crear clientes nuevos.
    ///
    /// Es idempotente. No es código de tiempo real: se llama desde el hilo de
    /// control, nunca desde el callback de recepción.
    public func close() {
        guard !closed.value else { return }
        closed.value = true

        MIDIEndpointDispose(destination)
        MIDIClientDispose(client)
        destination = MIDIEndpointRef()
        client = MIDIClientRef()
    }

    /// Red de seguridad idempotente, no el mecanismo principal.
    deinit {
        close()
    }
}
