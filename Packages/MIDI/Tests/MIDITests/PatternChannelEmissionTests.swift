import Engine
import XCTest
@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de por dónde sale lo que emite cada Track.
///
/// **Cada Track en su canal.** Sin esto los doce sonarían al
/// mismo instrumento, y no habría forma de juzgar nada en dispositivo.
final class PatternChannelEmissionTests: XCTestCase {

    private let emitter = NoteEmitter()

    /// Lo que el emisor entrega, con el canal de cada mensaje.
    private func channels(of track: Cycle, pitch: Pitch = Pitch(60)!) -> [Int] {
        var seen: [Int] = []
        emitter.emit(
            pitch: pitch,
            groove: track.groove,
            on: MIDIChannel(track.channel),
            stepDurationNanoseconds: 25_000_000,
            atHostTime: 1_000
        ) { message, _ in
            switch message {
            case .noteOn(let channel, _, _): seen.append(channel.number)
            case .noteOff(let channel, _, _): seen.append(channel.number)
            case .controlChange(let channel, _, _): seen.append(channel.number)
            }
        }
        return seen
    }

    /// El note-on y el note-off del mismo pulso salen por el mismo canal: un
    /// note-off por otro canal dejaría la nota sonando para siempre.
    func testBothMessagesOfAPulseShareTheChannel() {
        let track = Pattern().cycle(at: 4)!
        XCTAssertEqual(channels(of: track), [5, 5])
    }

    /// Los mensajes de un Track llevan **su** canal, sobre los doce.
    func testEachTrackEmitsOnItsOwnChannel() {
        let pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                channels(of: pattern.cycle(at: index)!), [index + 1, index + 1],
                "Track \(index + 1)")
        }
    }

    /// Cambiar el canal cambia lo que sale.
    func testChangingTheChannelChangesWhatGoesOut() {
        let moved = Pattern().cycle(at: 0)!.on(Channel(11)!)
        XCTAssertEqual(channels(of: moved), [11, 11])
    }

    /// La conversión entre el canal del dominio y el del protocolo no pierde
    /// nada: los dieciséis van y vuelven.
    func testTheConversionKeepsTheSixteenChannels() {
        for number in 1...16 {
            let domain = Channel(number)!
            XCTAssertEqual(MIDIChannel(domain).number, number)
        }
    }
}
