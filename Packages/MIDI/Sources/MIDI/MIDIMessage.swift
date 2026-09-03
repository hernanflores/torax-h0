import Engine
/// Canal MIDI, 1–16.
///
/// Se presenta 1-indexado, como en el hardware y en la Pre Spec, aunque en el
/// cable viaje 0-indexado. La conversión ocurre en un solo sitio: `statusByte`.
public struct MIDIChannel: Equatable, Sendable {
    public let number: Int

    public init?(_ number: Int) {
        guard (1...16).contains(number) else { return nil }
        self.number = number
    }

    /// El canal del dominio, traído al protocolo.
    ///
    /// **La conversión vive aquí, en la capa que conoce los dos tipos.** `Engine`
    /// tiene su propio `Channel` porque no importa nada de plataforma —la misma
    /// frontera que ya se pagó con `Pitch`— y los dos comparten el rango 1–16 por
    /// construcción, así que no puede fallar.
    public init(_ channel: Channel) {
        number = channel.number
    }

    /// Vía interna para valores que son literales conocidos, como los del
    /// arnés de medición. Igual que en `Division`: evita forzar el
    /// desempaquetado del inicializador validador, que `swift.md` prohíbe
    /// fuera de tests.
    init(unchecked number: Int) {
        self.number = number
    }

    /// Valor 0-indexado que viaja en el nibble bajo del status.
    var wireValue: UInt8 { UInt8(number - 1) }
}

/// Altura MIDI, 0–127.
public struct MIDINote: Equatable, Sendable {
    public let value: UInt8

    public init?(_ value: Int) {
        guard (0...127).contains(value) else { return nil }
        self.value = UInt8(value)
    }

    /// Vía interna para literales conocidos. Ver `MIDIChannel.init(unchecked:)`.
    init(unchecked value: UInt8) {
        self.value = value
    }
}

/// Velocity MIDI, 0–127.
public struct MIDIVelocity: Equatable, Sendable {
    public let value: UInt8

    public init?(_ value: Int) {
        guard (0...127).contains(value) else { return nil }
        self.value = UInt8(value)
    }

    /// Vía interna para literales conocidos. Ver `MIDIChannel.init(unchecked:)`.
    init(unchecked value: UInt8) {
        self.value = value
    }
}

/// Número de controlador MIDI, 0–127.
public struct MIDIController: Hashable, Sendable {
    public let number: Int

    public init?(_ number: Int) {
        guard (0...127).contains(number) else { return nil }
        self.number = number
    }

    /// Vía interna para números ya conocidos y válidos, como los de la sección
    /// de Channel Mode de MIDI 1.0.
    init(unchecked number: Int) {
        self.number = number
    }

    /// All Notes Off — mensaje de Channel Mode de MIDI 1.0.
    ///
    /// **No es un parámetro: es una parada de emergencia.** El transporte lo
    /// manda al parar, para apagar lo que su barrido de note-offs no conoce
    /// —una altura que sonaba y ya salió del pool—. No todos los sintetizadores
    /// lo honran, así que se manda *además* del barrido y no en su lugar.
    ///
    /// 123 es un literal dentro del rango 0–127, así que no puede fallar.
    public static let allNotesOff = MIDIController(unchecked: 123)

    var wireValue: UInt8 { UInt8(number) }
}

/// Un mensaje MIDI 1.0 que el producto entiende: de canal o de sistema.
///
/// El spike solo necesita note-on y note-off. El resto del vocabulario llega
/// cuando lo pide el producto, no antes — los tres de System Real-Time entran
/// con el reloj externo (track `external-clock_20260903`).
public enum MIDIMessage: Equatable, Sendable {
    case noteOn(channel: MIDIChannel, note: MIDINote, velocity: MIDIVelocity)
    case noteOff(channel: MIDIChannel, note: MIDINote, velocity: MIDIVelocity)

    /// Cambio de control.
    ///
    /// El valor va como `UInt8` desnudo y no como un tipo del dominio a
    /// propósito: en modo relativo **no es una cantidad**, es un desplazamiento
    /// codificado, y quien sabe interpretarlo es `RelativeEncoding`. Darle aquí
    /// un tipo con rango sugeriría una semántica de posición que el producto no
    /// usa.
    case controlChange(channel: MIDIChannel, controller: MIDIController, value: UInt8)

    /// Pulso del reloj de un maestro externo. Veinticuatro por negra.
    ///
    /// **No lleva canal**, y ninguno de los tres de abajo tampoco: son mensajes
    /// de sistema y van a todo el que escuche. Meterlos en el `MIDIChannel` que
    /// el resto exige sería mentir sobre el protocolo.
    case timingClock

    /// El maestro arranca. La rejilla empieza en el paso 0.
    case start

    /// El maestro para.
    case stop

    /// Byte de status: nibble de tipo en la parte alta, canal en la baja.
    var statusByte: UInt8 {
        switch self {
        case .noteOn(let channel, _, _): 0x90 | channel.wireValue
        case .noteOff(let channel, _, _): 0x80 | channel.wireValue
        case .controlChange(let channel, _, _): 0xB0 | channel.wireValue
        case .timingClock: 0xF8
        case .start: 0xFA
        case .stop: 0xFC
        }
    }

    /// Si el mensaje es de sistema, y por tanto no lleva canal ni datos.
    ///
    /// Decide el tipo de Universal MIDI Packet con el que viaja: `0x1` los de
    /// sistema, `0x2` los de canal.
    var isSystemRealTime: Bool {
        switch self {
        case .timingClock, .start, .stop: true
        case .noteOn, .noteOff, .controlChange: false
        }
    }

    private var dataBytes: (UInt8, UInt8) {
        switch self {
        case .noteOn(_, let note, let velocity): (note.value, velocity.value)
        case .noteOff(_, let note, let velocity): (note.value, velocity.value)
        case .controlChange(_, let controller, let value): (controller.wireValue, value)
        case .timingClock, .start, .stop: (0, 0)
        }
    }

    /// Empaqueta el mensaje como Universal MIDI Packet de 32 bits.
    ///
    /// `MIDISendEventList` trabaja con UMP, no con los bytes sueltos del MIDI
    /// 1.0 clásico. Un mensaje de canal MIDI 1.0 es el tipo `0x2`:
    ///
    /// ```text
    ///  31..28   27..24   23..16   15..8   7..0
    ///  0x2      group    status   data1   data2
    /// ```
    ///
    /// Los de System Real-Time viajan igual pero como tipo `0x1`, con los dos
    /// bytes de datos a cero. **Nada del producto los emite** —la app no es
    /// maestro de clock— pero el empaquetado tiene que ser total y coherente con
    /// el parseo, que es lo que hace verificable la ida y vuelta.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func universalPacketWord(group: UInt8) -> UInt32 {
        let (data1, data2) = dataBytes
        let type: UInt32 = isSystemRealTime ? 0x1 : 0x2
        return (type << 28)
            | (UInt32(group & 0x0F) << 24)
            | (UInt32(statusByte) << 16)
            | (UInt32(data1) << 8)
            | UInt32(data2)
    }
}

extension MIDIMessage {

    /// Reconstruye un mensaje a partir de un Universal MIDI Packet de 32 bits.
    ///
    /// Es lo contrario de `universalPacketWord(group:)`, y hace falta porque la
    /// entrada recibe lo que la salida emite: CoreMIDI entrega UMP, no los bytes
    /// sueltos del MIDI 1.0 clásico.
    ///
    /// **Devuelve `nil` para todo lo que este producto no usa, y eso no es un
    /// error.** Por el cable llegan SysEx, program change y mensajes de tipos que
    /// la app no interpreta; descartarlos en silencio es el comportamiento
    /// correcto, no un fallo del que informar.
    ///
    /// Se interpretan dos tipos de UMP: `0x2`, voz de canal, y `0x1`, System
    /// Real-Time, que es por donde llega el reloj del maestro externo.
    ///
    /// No es código de tiempo real: se llama desde el callback de recepción de
    /// CoreMIDI, no desde el hilo del scheduler.
    init?(universalPacketWord word: UInt32) {
        let type = (word >> 28) & 0xF
        let status = UInt8((word >> 16) & 0xFF)

        // Tipo 0x1: System Real-Time. No lleva canal ni datos, así que el status
        // es el mensaje entero.
        if type == 0x1 {
            switch status {
            case 0xF8: self = .timingClock
            case 0xFA: self = .start
            case 0xFC: self = .stop

            // Continue (0xFB) reanudaría a mitad de compás, y la app arranca
            // siempre desde el paso 0; Active Sensing (0xFE) y Reset (0xFF) no
            // se usan. Declarados y descartados, no olvidados.
            default: return nil
            }
            return
        }

        // Tipo 0x2: mensaje de canal MIDI 1.0. El resto no se interpreta.
        guard type == 0x2 else { return nil }

        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        // El canal viaja 0-indexado en el nibble bajo del status y se presenta
        // 1-indexado, como en el hardware y en la Pre Spec.
        guard let channel = MIDIChannel(Int(status & 0x0F) + 1) else { return nil }

        switch status & 0xF0 {
        case 0x90:
            guard let note = MIDINote(Int(data1)), let velocity = MIDIVelocity(Int(data2))
            else { return nil }
            self = .noteOn(channel: channel, note: note, velocity: velocity)

        case 0x80:
            guard let note = MIDINote(Int(data1)), let velocity = MIDIVelocity(Int(data2))
            else { return nil }
            self = .noteOff(channel: channel, note: note, velocity: velocity)

        case 0xB0:
            guard let controller = MIDIController(Int(data1)) else { return nil }
            self = .controlChange(channel: channel, controller: controller, value: data2)

        default:
            return nil
        }
    }
}
