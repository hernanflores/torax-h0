import Engine
import XCTest
@testable import MIDI

/// Tests de la altura que sale al MIDI.
///
/// Hasta Tonal, `NoteEmitter` llevaba una altura constante y su propia
/// documentación la declaraba provisional: vivía ahí, y no en `Track`, «para que
/// nada consolide la idea de una nota fija por paso». Ahora la altura llega por
/// parámetro y sale del pool.
final class NoteEmitterPitchTests: XCTestCase {

    private let emitter = NoteEmitter()

    // MARK: - Emitir con la altura que le pasan

    func testTheNoteOnCarriesTheGivenPitch() {
        let messages = emit(pitch: Pitch(67)!)
        guard case .noteOn(_, let note, _) = messages.first?.message else {
            return XCTFail("no salió un note-on")
        }
        XCTAssertEqual(note.value, 67)
    }

    /// **El note-off tiene que apagar la nota que se encendió.** Si llevara otra
    /// altura, la primera quedaría colgada en el sintetizador — que es el
    /// problema que `NoteEmitter` existe para evitar.
    func testTheNoteOffSilencesTheSamePitch() {
        let messages = emit(pitch: Pitch(43)!)
        XCTAssertEqual(messages.count, 2)
        guard case .noteOn(_, let on, _) = messages[0].message,
            case .noteOff(_, let off, _) = messages[1].message
        else { return XCTFail("no salieron note-on y note-off") }
        XCTAssertEqual(on, off)
    }

    func testEveryPitchOfTheMidiRangeCanBeEmitted() {
        for value in Pitch.validRange {
            let messages = emit(pitch: Pitch(value)!)
            guard case .noteOn(_, let note, _) = messages.first?.message else {
                return XCTFail("altura \(value)")
            }
            XCTAssertEqual(Int(note.value), value)
        }
    }

    // MARK: - Sin altura no se emite nada

    /// **Un pool vacío no suena, y no suena del todo.** Ni un note-on huérfano
    /// ni un note-off suelto: el Track dispara sus Pulses y no tiene material.
    /// Es un estado previsto, no un error.
    func testNoPitchEmitsNothing() {
        XCTAssertTrue(emit(pitch: nil).isEmpty)
    }

    // MARK: - Lo que no cambia

    /// El note-off sigue yendo sellado un gate más tarde. El gate ya no es una
    /// constante: con el Groove por defecto —Sustain 100%— dura exactamente un
    /// Step, que aquí son los 25 ms con los que se construye el emisor.
    func testTheNoteOffIsStillStampedAGateLater() {
        let messages = emit(pitch: Pitch(60)!, atHostTime: 1_000)
        let gate = HostClock.hostTicks(fromNanoseconds: 25_000_000)
        XCTAssertEqual(messages[1].hostTime, 1_000 &+ gate)
    }

    func testEmissionIsStillDeterministic() {
        let first = emit(pitch: Pitch(72)!, atHostTime: 500)
        let second = emit(pitch: Pitch(72)!, atHostTime: 500)
        XCTAssertEqual(first.map(\.hostTime), second.map(\.hostTime))
    }

    // MARK: - Helper

    private func emit(
        pitch: Pitch?,
        atHostTime hostTime: UInt64 = 0
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        var captured: [(message: MIDIMessage, hostTime: UInt64)] = []
        emitter.emit(
            pitch: pitch, groove: .default, on: MIDIChannel(1)!,
            stepDurationNanoseconds: 25_000_000, atHostTime: hostTime
        ) { message, time in
            captured.append((message, time))
        }
        return captured
    }
}
