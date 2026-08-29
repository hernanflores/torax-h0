import Engine
import XCTest

@testable import MIDI

/// Tests de la Velocity que sale al MIDI.
///
/// Hasta Groove, `NoteEmitter` llevaba una velocity constante y su propia
/// documentación la declaraba provisional: «canal y velocity siguen siendo
/// constantes hasta que llegue Groove». Ahora llega en el Groove del Track, que
/// es lo que el hilo del scheduler lee del snapshot.
final class NoteEmitterGrooveTests: XCTestCase {

    private let emitter = NoteEmitter(channel: MIDIChannel(1)!)

    private func emit(
        pitch: Pitch?,
        groove: Groove
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        var sent: [(MIDIMessage, UInt64)] = []
        emitter.emit(pitch: pitch, groove: groove, atHostTime: 1_000) { message, time in
            sent.append((message, time))
        }
        return sent
    }

    private func groove(velocity: Int) -> Groove {
        Groove(velocity: Velocity(velocity)!, sustain: .default, probability: .default)
    }

    // MARK: - La Velocity sale del snapshot

    func testTheNoteOnCarriesTheGrooveVelocity() {
        for value in [1, 40, 100, 127] {
            let sent = emit(pitch: Pitch(60)!, groove: groove(velocity: value))
            guard case .noteOn(_, _, let velocity) = sent.first?.message else {
                return XCTFail("no salió un note-on")
            }
            XCTAssertEqual(Int(velocity.value), value)
        }
    }

    /// **Todo el rango del parámetro llega intacto al cable.** Velocity vive en
    /// la unidad MIDI justamente para que no haya conversión que perder por el
    /// camino.
    func testEveryVelocityOfTheRangeReachesTheWire() {
        for value in 1...127 {
            let sent = emit(pitch: Pitch(60)!, groove: groove(velocity: value))
            guard case .noteOn(_, _, let velocity) = sent.first?.message else {
                return XCTFail("no salió un note-on para velocity \(value)")
            }
            XCTAssertEqual(Int(velocity.value), value)
        }
    }

    // MARK: - El note-off no es un parámetro

    /// La velocity del note-off es 0 y **no** la del note-on: es la convención
    /// de apagado de MIDI 1.0, la que entienden todos los sintetizadores, y no
    /// algo que Groove pueda mover.
    func testTheNoteOffKeepsVelocityZeroWhateverTheGroove() {
        for value in [1, 64, 127] {
            let sent = emit(pitch: Pitch(60)!, groove: groove(velocity: value))
            guard case .noteOff(_, _, let velocity) = sent.last?.message else {
                return XCTFail("no salió un note-off")
            }
            XCTAssertEqual(velocity.value, 0)
        }
    }

    // MARK: - Lo que ya valía sigue valiendo

    func testWithoutAPitchNothingIsEmitted() {
        XCTAssertTrue(emit(pitch: nil, groove: .default).isEmpty)
    }

    func testEachPulseStillEmitsExactlyTwoMessages() {
        XCTAssertEqual(emit(pitch: Pitch(60)!, groove: .default).count, 2)
    }
}
