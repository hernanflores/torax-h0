import Engine
import XCTest
@testable import MIDI

/// Tests de la emisión de notas por pulso.
///
/// Un pulso no es una nota: es una posición del anillo que dispara. Convertirlo
/// en sonido exige **dos** mensajes, note-on y note-off, y el segundo tiene que
/// ir sellado con su propio instante futuro. Sin note-off la nota queda colgada
/// en el sintetizador; con un temporizador o un sleep para enviarlo se
/// reintroduciría justo el jitter que la arquitectura evita.
final class NoteEmitterTests: XCTestCase {

    private func emitter(gateNanoseconds: Int64 = NoteEmitter.provisionalGateNanoseconds)
        -> NoteEmitter
    {
        NoteEmitter(channel: MIDIChannel(1)!, gateNanoseconds: gateNanoseconds)
    }

    /// Recoge lo que el emisor entregaría al camino de envío.
    private func emitted(
        from emitter: NoteEmitter,
        atHostTime hostTime: UInt64
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        var sent: [(MIDIMessage, UInt64)] = []
        // La altura llega por parámetro desde Tonal y el Groove desde esta
        // rebanada; estos tests miden el par de mensajes y su sellado, así que
        // cualquiera de los dos sirve.
        emitter.emit(pitch: Pitch(48)!, groove: .default, atHostTime: hostTime) { message, time in
            sent.append((message, time))
        }
        return sent
    }

    // MARK: - El par

    func testEachPulseEmitsExactlyTwoMessages() {
        XCTAssertEqual(emitted(from: emitter(), atHostTime: 1_000).count, 2)
    }

    func testFirstMessageIsNoteOnAtThePulseInstant() {
        let sent = emitted(from: emitter(), atHostTime: 5_000)
        XCTAssertEqual(
            sent[0].message,
            .noteOn(channel: MIDIChannel(1)!, note: MIDINote(48)!, velocity: MIDIVelocity(100)!)
        )
        XCTAssertEqual(sent[0].hostTime, 5_000)
    }

    /// El note-off lleva su propio timestamp futuro: se entrega en la misma
    /// llamada que el note-on, no más tarde.
    func testSecondMessageIsNoteOffStampedAGateLater() {
        let gate: Int64 = 25_000_000
        let sent = emitted(from: emitter(gateNanoseconds: gate), atHostTime: 5_000)

        guard case .noteOff = sent[1].message else {
            return XCTFail("el segundo mensaje debería ser note-off, fue \(sent[1].message)")
        }
        XCTAssertEqual(
            sent[1].hostTime,
            5_000 &+ HostClock.hostTicks(fromNanoseconds: UInt64(gate))
        )
    }

    func testNoteOffMatchesTheNoteOnChannelAndNote() {
        let sent = emitted(from: emitter(), atHostTime: 0)
        guard
            case .noteOn(let onChannel, let onNote, _) = sent[0].message,
            case .noteOff(let offChannel, let offNote, _) = sent[1].message
        else { return XCTFail("no se emitió el par note-on/note-off") }

        XCTAssertEqual(onChannel, offChannel)
        XCTAssertEqual(onNote, offNote)
    }

    /// El note-off va siempre por delante en el tiempo, nunca antes ni a la vez:
    /// un note-off con el mismo timestamp que su note-on es una nota de duración
    /// cero, que muchos sintetizadores se comen.
    func testNoteOffIsStrictlyAfterNoteOn() {
        let sent = emitted(from: emitter(), atHostTime: 9_999)
        XCTAssertGreaterThan(sent[1].hostTime, sent[0].hostTime)
    }

    // MARK: - El gate provisional

    /// El gate tiene que caber dentro del Step más corto que el producto puede
    /// producir, o el note-off de un pulso llegaría después del note-on del
    /// siguiente y se solaparían en la misma altura.
    ///
    /// **Los dos extremos se leen del dominio, no se escriben aquí.** Si algún
    /// día se añade una Division más rápida o sube el tempo máximo, este test
    /// falla en vez de dejar que las notas empiecen a solaparse en silencio.
    func testProvisionalGateFitsInsideTheShortestPossibleStep() throws {
        let fastestDivision = try XCTUnwrap(Division.fastest)
        let highestTempo = try XCTUnwrap(Tempo(beatsPerMinute: Tempo.validRange.upperBound))
        let shortestStep = MusicalTimeline(tempo: highestTempo, division: fastestDivision)

        XCTAssertLessThan(
            Double(NoteEmitter.provisionalGateNanoseconds),
            shortestStep.stepDurationNanoseconds,
            """
            El gate (\(NoteEmitter.provisionalGateNanoseconds / 1_000_000) ms) no cabe en el \
            Step más corto: \(fastestDivision) a \(Tempo.validRange.upperBound) BPM dura \
            \(Int(shortestStep.stepDurationNanoseconds / 1_000_000)) ms. Las notas se solaparían.
            """
        )
    }

    /// El emisor no consulta el reloj: dado el mismo instante de pulso, produce
    /// siempre exactamente los mismos dos mensajes.
    func testEmissionIsDeterministic() {
        let emitter = emitter()
        let first = emitted(from: emitter, atHostTime: 7_777)
        for _ in 0..<100 {
            let again = emitted(from: emitter, atHostTime: 7_777)
            XCTAssertEqual(again[0].message, first[0].message)
            XCTAssertEqual(again[0].hostTime, first[0].hostTime)
            XCTAssertEqual(again[1].message, first[1].message)
            XCTAssertEqual(again[1].hostTime, first[1].hostTime)
        }
    }
}
