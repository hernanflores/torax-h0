import XCTest
@testable import MIDI

/// Tests del empaquetado de mensajes MIDI.
///
/// `MIDISendEventList` trabaja con Universal MIDI Packets (UMP): palabras de
/// 32 bits, no con los bytes sueltos del MIDI 1.0 clásico. El empaquetado es
/// pura aritmética de bits, así que se puede verificar entero sin hardware —
/// que es justo lo que interesa, porque un bit mal colocado aquí se
/// manifestaría como una nota equivocada difícil de diagnosticar en el iPad.
final class MIDIMessageTests: XCTestCase {

    // MARK: - Validación de rangos

    func testChannelAcceptsOneThroughSixteen() {
        XCTAssertNotNil(MIDIChannel(1))
        XCTAssertNotNil(MIDIChannel(16))
        XCTAssertNil(MIDIChannel(0))
        XCTAssertNil(MIDIChannel(17))
    }

    func testNoteAndVelocityAcceptSevenBitRange() {
        XCTAssertNotNil(MIDINote(0))
        XCTAssertNotNil(MIDINote(127))
        XCTAssertNil(MIDINote(128))
        XCTAssertNil(MIDINote(-1))

        XCTAssertNotNil(MIDIVelocity(0))
        XCTAssertNotNil(MIDIVelocity(127))
        XCTAssertNil(MIDIVelocity(128))
    }

    // MARK: - Status

    func testNoteOnStatusIsNineOnChannelOne() {
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(100)!)
        XCTAssertEqual(message.statusByte, 0x90)
    }

    func testNoteOffStatusIsEightOnChannelOne() {
        let message = MIDIMessage.noteOff(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(0)!)
        XCTAssertEqual(message.statusByte, 0x80)
    }

    /// El canal viaja en el nibble bajo del status, y es 0-indexado en el cable
    /// aunque se presente 1-indexado al usuario.
    func testChannelSixteenOccupiesTheLowNibble() {
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(16)!, note: MIDINote(60)!, velocity: MIDIVelocity(1)!)
        XCTAssertEqual(message.statusByte, 0x9F)
    }

    // MARK: - Universal MIDI Packet

    /// Un mensaje de canal MIDI 1.0 en UMP es tipo 0x2, con el grupo en el
    /// segundo nibble, el status completo en el tercer byte y los dos bytes de
    /// datos al final.
    func testUniversalPacketLayoutForNoteOn() {
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(100)!)
        let word = message.universalPacketWord(group: 0)

        XCTAssertEqual(word, 0x2090_3C64)
        XCTAssertEqual((word >> 28) & 0xF, 0x2, "Message type debe ser 0x2")
        XCTAssertEqual((word >> 24) & 0xF, 0x0, "Group")
        XCTAssertEqual((word >> 16) & 0xFF, 0x90, "Status")
        XCTAssertEqual((word >> 8) & 0xFF, 60, "Nota")
        XCTAssertEqual(word & 0xFF, 100, "Velocity")
    }

    func testUniversalPacketLayoutForNoteOff() {
        let message = MIDIMessage.noteOff(
            channel: MIDIChannel(10)!, note: MIDINote(36)!, velocity: MIDIVelocity(0)!)
        let word = message.universalPacketWord(group: 0)

        XCTAssertEqual((word >> 16) & 0xFF, 0x89, "Status note-off en canal 10")
        XCTAssertEqual((word >> 8) & 0xFF, 36)
        XCTAssertEqual(word & 0xFF, 0)
    }

    func testGroupIsCarriedInTheSecondNibble() {
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(1)!)
        XCTAssertEqual((message.universalPacketWord(group: 5) >> 24) & 0xF, 5)
    }

    /// Ningún byte de datos puede desbordar a los vecinos: con todos los
    /// valores al máximo, cada campo debe seguir en su sitio.
    func testMaximumValuesDoNotBleedBetweenFields() {
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(16)!, note: MIDINote(127)!, velocity: MIDIVelocity(127)!)
        let word = message.universalPacketWord(group: 15)
        XCTAssertEqual(word, 0x2F9F_7F7F)
    }
}
