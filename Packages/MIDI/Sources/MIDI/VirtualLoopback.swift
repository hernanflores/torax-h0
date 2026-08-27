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
        ) { eventList, _ in
            // Se toma el instante ANTES de hacer nada más: cualquier trabajo
            // previo se contabilizaria como jitter que no existe.
            let actual = HostClock.now()

            let list = eventList.pointee
            var packet = withUnsafePointer(to: list.packet) { UnsafeMutablePointer(mutating: $0) }
            for _ in 0..<list.numPackets {
                handler(packet.pointee.timeStamp, actual)
                packet = MIDIEventPacketNext(packet)
            }
        }

        guard destinationStatus == noErr else {
            MIDIClientDispose(client)
            throw MIDIOutputError.portCreationFailed(destinationStatus)
        }
    }

    deinit {
        MIDIEndpointDispose(destination)
        MIDIClientDispose(client)
    }
}
