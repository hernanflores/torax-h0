import Engine
import XCTest

@testable import MIDI

/// Tests de los mensajes de System Real-Time entrantes.
///
/// El parseo descartaba todo lo que no fuera UMP de tipo `0x2` —voz de canal—, y
/// clock, start y stop son de tipo `0x1`. Aquí se verifica que el tipo nuevo
/// entra **sin que el viejo pierda nada**: son dos espacios distintos y el
/// primer error probable es que uno se coma al otro.
final class SystemRealTimeParsingTests: XCTestCase {

    /// Empaqueta un byte de status de sistema como UMP de tipo `0x1`.
    private func systemWord(_ status: UInt8, group: UInt8 = 0) -> UInt32 {
        (UInt32(0x1) << 28) | (UInt32(group & 0x0F) << 24) | (UInt32(status) << 16)
    }

    // MARK: - Los tres que se entienden

    func testTimingClockIsParsed() {
        XCTAssertEqual(MIDIMessage(universalPacketWord: systemWord(0xF8)), .timingClock)
    }

    func testStartIsParsed() {
        XCTAssertEqual(MIDIMessage(universalPacketWord: systemWord(0xFA)), .start)
    }

    func testStopIsParsed() {
        XCTAssertEqual(MIDIMessage(universalPacketWord: systemWord(0xFC)), .stop)
    }

    /// Llegan por cualquier grupo, como el resto del vocabulario.
    func testTheGroupDoesNotChangeTheMeaning() {
        for group in UInt8(0)...15 {
            XCTAssertEqual(
                MIDIMessage(universalPacketWord: systemWord(0xF8, group: group)), .timingClock)
        }
    }

    // MARK: - Los que se declaran y se descartan

    /// Continue, Active Sensing y Reset **no** se interpretan: la app arranca
    /// siempre desde el paso 0 y no vigila la presencia del cable con
    /// mensajes. Descartarlos es la decisión, no el olvido.
    func testDeclaredButUnusedSystemMessagesAreDiscarded() {
        for status: UInt8 in [0xFB, 0xFE, 0xFF] {
            XCTAssertNil(
                MIDIMessage(universalPacketWord: systemWord(status)),
                "El status \(String(status, radix: 16)) no debería interpretarse")
        }
    }

    /// Y los status de sistema sin significado asignado, tampoco.
    func testUndefinedSystemStatusesAreDiscarded() {
        for status: UInt8 in [0xF9, 0xFD] {
            XCTAssertNil(MIDIMessage(universalPacketWord: systemWord(status)))
        }
    }

    // MARK: - El tipo nuevo no roba nada al viejo

    /// Un mensaje de canal sigue parseándose igual: mismo status, distinto tipo
    /// de UMP, distinto significado.
    func testChannelMessagesStillParse() throws {
        let channel = try XCTUnwrap(MIDIChannel(3))
        let note = try XCTUnwrap(MIDINote(60))
        let velocity = try XCTUnwrap(MIDIVelocity(100))
        let message = MIDIMessage.noteOn(channel: channel, note: note, velocity: velocity)

        let word = message.universalPacketWord(group: 0)
        XCTAssertEqual(MIDIMessage(universalPacketWord: word), message)
    }

    /// El byte 0xF8 dentro de un paquete de **voz de canal** no es un clock: el
    /// tipo manda sobre el status.
    func testTheTypeDecidesBeforeTheStatus() {
        let channelVoiceWord = (UInt32(0x2) << 28) | (UInt32(0xF8) << 16)
        XCTAssertNil(MIDIMessage(universalPacketWord: channelVoiceWord))
    }

    // MARK: - Ida y vuelta

    /// Los tres sobreviven al empaquetado, como el resto del vocabulario. Nada
    /// en el producto los emite —la app no es maestro de clock— pero el
    /// empaquetado tiene que ser total y coherente con el parseo.
    func testTheThreeSurviveARoundTrip() {
        for message in [MIDIMessage.timingClock, .start, .stop] {
            let word = message.universalPacketWord(group: 0)
            XCTAssertEqual(MIDIMessage(universalPacketWord: word), message, "\(message)")
        }
    }

    /// Se empaquetan como tipo `0x1`, no como voz de canal.
    func testTheyArePackedAsSystemRealTime() {
        XCTAssertEqual(MIDIMessage.timingClock.universalPacketWord(group: 0) >> 28, 0x1)
    }

    // MARK: - No son entrada de control

    /// El controlador manda clock por el mismo cable que los knobs, así que
    /// `ControlInput` los ve pasar. No mueven ningún parámetro.
    func testControlInputIgnoresThem() {
        let cycle = Pattern.initial.cycle(at: 0)!
        let input = ControlInput(track: cycle, publishingTo: PatternHandoff(cycle))

        for message in [MIDIMessage.timingClock, .start, .stop] {
            XCTAssertFalse(input.receive(message), "\(message) no es entrada de control")
        }
    }
}
