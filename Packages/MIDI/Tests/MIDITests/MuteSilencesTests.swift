import Engine
import XCTest
@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de que **volverse inaudible apaga** (FR4).
///
/// **El apagado va con la transición, no con el estado.** Lo que dispara el
/// barrido es pasar de audible a inaudible: mutear a quien suena, o soltar un
/// solo que deja fuera a otros. Volverse audible no apaga nada, y tocar un Track
/// que ya estaba callado tampoco — barrer por estado mandaría mensajes cada vez
/// que alguien roza un botón.
///
/// Sin esto, un Sustain al 200% sobre una Division larga dejaría la nota colgada
/// en el sintetizador durante segundos después de pulsar M: el modo de fallo
/// caro de esta feature.
final class MuteSilencesTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, at hostTime: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            messages.append(message)
        }

        var captured: [MIDIMessage] {
            lock.lock()
            defer { lock.unlock() }
            return messages
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            messages.removeAll()
        }
    }

    // MARK: - Mute

    /// Mutear un Track que suena apaga lo suyo.
    func testMutingASoundingTrackSilencesIt() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        recorder.clear()
        transport.toggleMute(2)

        XCTAssertEqual(allNotesOffChannels(in: recorder.captured), [3])
    }

    /// **Desmutear no apaga nada.** No hay ninguna nota que cerrar: el Track
    /// estaba callado.
    func testUnmutingSilencesNothing() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        transport.toggleMute(2)
        recorder.clear()
        transport.toggleMute(2)

        XCTAssertTrue(allNotesOffChannels(in: recorder.captured).isEmpty)
    }

    /// **Un Track que ya era inaudible no se vuelve a barrer.** Mutear a quien
    /// ya callaba por el solo de otro no manda nada: el apagado va con la
    /// transición, no con el estado.
    func testMutingAnAlreadyInaudibleTrackSendsNothing() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        transport.toggleSolo(0)
        recorder.clear()
        transport.toggleMute(5)

        XCTAssertTrue(allNotesOffChannels(in: recorder.captured).isEmpty)
    }

    // MARK: - Solo

    /// **Poner un solo apaga a los que deja fuera**, que son once de doce, y no
    /// al soleado.
    func testSettingASoloSilencesEverybodyElse() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        recorder.clear()
        transport.toggleSolo(0)

        var expected = Set(1...Pattern.trackCount)
        expected.remove(1)
        XCTAssertEqual(allNotesOffChannels(in: recorder.captured), expected)
    }

    /// **Añadir un segundo solo apaga solo a quien seguía sonando y ya no.** Los
    /// otros diez ya estaban callados: barrerlos otra vez sería ruido.
    func testAddingASecondSoloSilencesNobodyNew() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        transport.toggleSolo(0)
        recorder.clear()
        transport.toggleSolo(3)

        XCTAssertTrue(
            allNotesOffChannels(in: recorder.captured).isEmpty,
            "el Track 4 pasó a audible, no al revés")
    }

    /// **Soltar el último solo no apaga a nadie:** los once vuelven a ser
    /// audibles, y volver a sonar no exige apagar antes.
    func testReleasingTheLastSoloSilencesNobody() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        transport.toggleSolo(0)
        recorder.clear()
        transport.toggleSolo(0)

        XCTAssertTrue(allNotesOffChannels(in: recorder.captured).isEmpty)
    }

    /// **Soltar uno de dos solos apaga al que se queda fuera.** Es la transición
    /// que se olvida: el Track 4 sonaba y deja de sonar sin que nadie lo mutee.
    func testReleasingOneOfTwoSolosSilencesTheOneLeftOut() {
        let (transport, recorder) = playing()
        defer { transport.stop() }

        transport.toggleSolo(0)
        transport.toggleSolo(3)
        recorder.clear()
        transport.toggleSolo(3)

        XCTAssertEqual(allNotesOffChannels(in: recorder.captured), [4])
    }

    // MARK: - Parado

    /// **Con el transporte parado no se manda nada.** No hay nada sonando que
    /// apagar, y un `all notes off` por cada toque de un botón sería ruido en el
    /// cable.
    func testWithTheTransportStoppedNothingIsSent() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.publish(everyTrack())

        transport.toggleMute(0)
        transport.toggleSolo(1)

        XCTAssertTrue(recorder.captured.isEmpty)
    }

    /// Y el estado sí cambia aunque no se mande nada: al arrancar, el Track
    /// muteado no suena.
    func testTheStateChangesEvenWhenStopped() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.publish(everyTrack())

        transport.toggleMute(0)

        XCTAssertTrue(transport.mix.isMuted(0))
        XCTAssertFalse(transport.mix.isAudible(0))
    }

    // MARK: - La mezcla sobrevive

    /// **Stop no limpia la mezcla** (FR10): es mezcla, no transporte.
    func testStoppingKeepsTheMix() {
        let (transport, _) = playing()

        transport.toggleMute(4)
        transport.toggleSolo(7)
        transport.stop()

        XCTAssertTrue(transport.mix.isMuted(4))
        XCTAssertTrue(transport.mix.isSoloed(7))
    }

    // MARK: - Helpers

    private func allNotesOffChannels(in messages: [MIDIMessage]) -> Set<Int> {
        var channels: Set<Int> = []
        for case .controlChange(let channel, let controller, _) in messages
        where controller == MIDIController.allNotesOff {
            channels.insert(channel.number)
        }
        return channels
    }

    private func everyTrack() -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            let cycle = Cycle(
                shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48 + index)!),
                channel: Channel(index + 1)!
            )
            pattern = pattern.replacing(Track(cycle), at: index)
        }
        return pattern
    }

    private func makeTransport(_ recorder: Recorder) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            track: Cycle(shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!)),
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }

    /// Un transporte con los doce sonando, ya arrancado.
    private func playing() -> (Transport, Recorder) {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.publish(everyTrack())
        transport.play()

        let deadline = Date().addingTimeInterval(4)
        while recorder.captured.count < 16 && Date() < deadline { usleep(5_000) }

        return (transport, recorder)
    }
}
