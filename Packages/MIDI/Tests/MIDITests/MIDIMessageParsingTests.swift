import XCTest
@testable import MIDI

/// Tests del parseo de paquetes entrantes.
///
/// La salida ya sabía **empaquetar** un `MIDIMessage` como Universal MIDI
/// Packet; la entrada necesita lo contrario. Se testea sobre las palabras de 32
/// bits directamente, sin CoreMIDI de por medio: lo que hay que verificar es la
/// aritmética de bits, no que el sistema entregue nada.
final class MIDIMessageParsingTests: XCTestCase {

    // MARK: - Ida y vuelta

    /// Lo empaquetado se vuelve a leer igual. Es la propiedad que importa: si
    /// alguien cambia el empaquetado, esto lo detecta.
    func testEveryMessageSurvivesARoundTrip() throws {
        let channel = try XCTUnwrap(MIDIChannel(3))
        let messages: [MIDIMessage] = [
            .noteOn(channel: channel, note: try XCTUnwrap(MIDINote(60)), velocity: try XCTUnwrap(MIDIVelocity(100))),
            .noteOff(channel: channel, note: try XCTUnwrap(MIDINote(60)), velocity: try XCTUnwrap(MIDIVelocity(0))),
            .controlChange(channel: channel, controller: try XCTUnwrap(MIDIController(70)), value: 0x7F),
        ]

        for message in messages {
            let word = message.universalPacketWord(group: 0)
            XCTAssertEqual(MIDIMessage(universalPacketWord: word), message, "\(message)")
        }
    }

    /// Sobre todo el espacio de canales y controladores, que es por donde entra
    /// el hardware real.
    func testControlChangeRoundTripsOverTheWholeSpace() throws {
        for channelNumber in 1...16 {
            let channel = try XCTUnwrap(MIDIChannel(channelNumber))
            for controllerNumber in stride(from: 0, through: 127, by: 17) {
                let controller = try XCTUnwrap(MIDIController(controllerNumber))
                for value in [UInt8(0x00), 0x01, 0x3F, 0x40, 0x41, 0x7F] {
                    let message = MIDIMessage.controlChange(
                        channel: channel, controller: controller, value: value
                    )
                    XCTAssertEqual(
                        MIDIMessage(universalPacketWord: message.universalPacketWord(group: 0)),
                        message
                    )
                }
            }
        }
    }

    // MARK: - Lo que no se entiende se descarta

    /// Un paquete que no es un mensaje de canal MIDI 1.0 devuelve `nil`.
    ///
    /// No es un error: por el cable llegan relojes, SysEx y mensajes de tipos
    /// que este producto no usa, y descartarlos es el comportamiento correcto.
    func testNonChannelVoicePacketsAreDiscarded() {
        // Tipo 0x0 (utilidad) y 0x1 (tiempo real del sistema), no 0x2.
        XCTAssertNil(MIDIMessage(universalPacketWord: 0x0000_0000))
        XCTAssertNil(MIDIMessage(universalPacketWord: 0x1000_0000))
    }

    /// Dentro de los mensajes de canal, los que el producto no usa también se
    /// descartan: program change, pitch bend, aftertouch.
    func testUnsupportedChannelMessagesAreDiscarded() {
        for status: UInt32 in [0xA0, 0xC0, 0xD0, 0xE0] {
            let word = (UInt32(0x2) << 28) | (status << 16) | (0x40 << 8) | 0x40
            XCTAssertNil(MIDIMessage(universalPacketWord: word), "status 0x\(String(status, radix: 16))")
        }
    }

    // MARK: - El canal se lee 1-indexado

    /// En el cable el canal viaja 0-indexado; se presenta 1-indexado, como en el
    /// hardware y en la Pre Spec.
    func testChannelIsPresentedOneIndexed() {
        let word = (UInt32(0x2) << 28) | (UInt32(0xB0) << 16) | (70 << 8) | 0x01
        guard case let .controlChange(channel, _, _) = MIDIMessage(universalPacketWord: word) else {
            return XCTFail("no se parseó el control change")
        }
        XCTAssertEqual(channel.number, 1, "el canal 0 del cable es el 1 del producto")
    }

    func testHighestChannelIsSixteen() {
        let word = (UInt32(0x2) << 28) | (UInt32(0xBF) << 16) | (70 << 8) | 0x01
        guard case let .controlChange(channel, _, _) = MIDIMessage(universalPacketWord: word) else {
            return XCTFail("no se parseó el control change")
        }
        XCTAssertEqual(channel.number, 16)
    }
}
