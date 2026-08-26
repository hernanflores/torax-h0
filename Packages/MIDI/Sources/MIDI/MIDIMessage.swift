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
}

/// Velocity MIDI, 0–127.
public struct MIDIVelocity: Equatable, Sendable {
    public let value: UInt8

    public init?(_ value: Int) {
        guard (0...127).contains(value) else { return nil }
        self.value = UInt8(value)
    }
}

/// Mensaje de canal MIDI 1.0.
///
/// El spike solo necesita note-on y note-off. El resto del vocabulario llegará
/// cuando lo pida el producto, no antes.
public enum MIDIMessage: Equatable, Sendable {
    case noteOn(channel: MIDIChannel, note: MIDINote, velocity: MIDIVelocity)
    case noteOff(channel: MIDIChannel, note: MIDINote, velocity: MIDIVelocity)

    /// Byte de status: nibble de tipo en la parte alta, canal en la baja.
    var statusByte: UInt8 {
        switch self {
        case let .noteOn(channel, _, _): 0x90 | channel.wireValue
        case let .noteOff(channel, _, _): 0x80 | channel.wireValue
        }
    }

    private var dataBytes: (UInt8, UInt8) {
        switch self {
        case let .noteOn(_, note, velocity): (note.value, velocity.value)
        case let .noteOff(_, note, velocity): (note.value, velocity.value)
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
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    func universalPacketWord(group: UInt8) -> UInt32 {
        let (data1, data2) = dataBytes
        return (UInt32(0x2) << 28)
            | (UInt32(group & 0x0F) << 24)
            | (UInt32(statusByte) << 16)
            | (UInt32(data1) << 8)
            | UInt32(data2)
    }
}
