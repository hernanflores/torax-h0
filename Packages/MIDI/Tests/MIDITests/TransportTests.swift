import Engine
import Foundation
import XCTest
@testable import MIDI

/// Tests del transporte.
///
/// El envío se inyecta, así que play y stop se verifican sin sintetizador y sin
/// CoreMIDI: lo que importa aquí es qué mensajes salen y cuándo dejan de salir.
final class TransportTests: XCTestCase {

    /// Un pool de una altura: el «centro estable» de la Pre Spec, y lo que
    /// sonaba antes de que Tonal existiera.
    private let voicePool = PitchPool().inserting(Pitch(48)!)

    /// Recoge los mensajes que salen. El scheduler los emite desde su hilo, así
    /// que la recogida va con lock — es código de test, no del camino de timing.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock {
                messages.append(message)
                times.append(hostTime)
            }
        }

        private var times: [UInt64] = []
        var allTimes: [UInt64] { lock.withLock { times } }
        var all: [MIDIMessage] { lock.withLock { messages } }
        var noteOnCount: Int { all.filter { if case .noteOn = $0 { true } else { false } }.count }
        var noteOffCount: Int { all.filter { if case .noteOff = $0 { true } else { false } }.count }
    }

    /// 300 BPM con Division 1/16 da Steps de 50 ms. Anillo lleno para que cada
    /// Step dispare y el test no tenga que esperar al reparto euclidiano.
    private func makeTransport(_ recorder: Recorder) -> Transport {
        let steps = Steps(4)!
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth)
        return Transport(
            configuration: SchedulerConfiguration(
                timeline: timeline,
                lookAheadNanoseconds: 20_000_000
            ),
            // Con el pool vacío el Track dispara y no emite nada, que es
            // comportamiento correcto y no lo que estos tests miden.
            track: Track(shape: Shape(steps: steps, pulses: Pulses(4)!), pool: voicePool),
            emitter: NoteEmitter(
                channel: MIDIChannel(1)!,
                stepDurationNanoseconds: Int64(timeline.stepDurationNanoseconds)
            ),
            send: recorder.record
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    // MARK: - Play y stop

    func testTransportStartsStopped() {
        XCTAssertFalse(makeTransport(Recorder()).isPlaying)
    }

    func testStoppingWithoutHavingPlayedIsHarmlessAndSilent() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.stop()
        transport.stop()

        XCTAssertFalse(transport.isPlaying)
        XCTAssertTrue(recorder.all.isEmpty, "paró sin haber tocado y aun así emitió")
    }

    /// Ciclo completo del reloj en una sola reproducción.
    ///
    /// Play, play repetido, stop y stop repetido van juntos en un test —y no en
    /// cuatro— a propósito: cada reproducción arranca un hilo de prioridad
    /// máxima, y acumular ciclos de arranque y parada en un mismo proceso hace
    /// fallar la creación de clientes de CoreMIDI en las clases que sí la usan.
    /// Medido: nueve reproducciones en la suite dan 2 fallos de cada 8 pasadas;
    /// una sola, 0 de 8.
    ///
    /// La causa de fondo es el ciclo de vida de `stop()`/`start()`, que es el
    /// track `scheduler-lifecycle_20260826`. Este track no lo arregla, así que
    /// aquí solo se evita provocarlo.
    func testPlayAndStopDriveTheClock() {
        let transport = makeTransport(Recorder())

        transport.play()
        XCTAssertTrue(transport.isPlaying)

        transport.play()
        XCTAssertTrue(transport.isPlaying, "el segundo play no debería alterar nada")

        transport.stop()
        XCTAssertFalse(transport.isPlaying)

        transport.stop()
        XCTAssertFalse(transport.isPlaying, "el segundo stop no debería alterar nada")
    }

    // MARK: - Play produce sonido, y ninguna nota queda colgada

    func testPlayingEmitsMatchedNotePairs() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 4 }
        transport.stop()

        XCTAssertGreaterThanOrEqual(recorder.noteOnCount, 4, "el transporte no emitió notas")
        XCTAssertGreaterThanOrEqual(
            recorder.noteOffCount,
            recorder.noteOnCount,
            "quedaron notas sin apagar"
        )
    }

    // MARK: - Stop no deja notas colgadas

    /// Al parar se manda un note-off inmediato, además de los que ya iban
    /// sellados: si el usuario para justo entre el note-on y su note-off, la
    /// nota se queda sonando en el sintetizador hasta que alguien la apague, y
    /// el hilo que lo habría hecho es el que se acaba de detener.
    func testStoppingSilencesTheVoiceAndEmitsNothingMore() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }

        let before = recorder.all.count
        transport.stop()
        XCTAssertGreaterThan(recorder.all.count, before, "parar no mandó nada")

        guard case .noteOff(let channel, let note, _) = recorder.all.last else {
            return XCTFail("el último mensaje al parar debería ser note-off")
        }
        XCTAssertEqual(channel, MIDIChannel(1)!, "apagó otro canal")
        XCTAssertEqual(note, MIDINote(48)!, "apagó otra altura")

        let settled = recorder.all.count
        usleep(300_000)
        XCTAssertEqual(recorder.all.count, settled, "siguió emitiendo después de parar")
    }

    /// El note-off de parada va **sellado una ventana por delante**, no en
    /// «ahora».
    ///
    /// CoreMIDI emite en orden de timestamp: uno sellado a 0 saldría *antes* que
    /// cualquier note-on que el hilo moribundo ya hubiera programado con
    /// timestamp futuro — es decir, antes de la nota que este mensaje existe
    /// para apagar. Sellarlo por delante del look-ahead lo pone detrás de todo
    /// lo ya entregado.
    func testStopNoteOffIsStampedAheadOfAnythingAlreadyScheduled() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }

        let beforeStop = HostClock.now()
        transport.stop()

        guard let silenceAt = recorder.allTimes.last else {
            return XCTFail("parar no mandó nada")
        }
        XCTAssertGreaterThan(silenceAt, beforeStop, "el note-off de parada salió en «ahora»")

        // Una ventana es 20 ms; se admite algo menos por el tiempo transcurrido
        // entre tomar `beforeStop` y sellar el mensaje.
        let aheadNanoseconds = HostClock.nanoseconds(fromHostTicks: silenceAt &- beforeStop)
        XCTAssertGreaterThan(
            aheadNanoseconds,
            15_000_000,
            "el note-off de parada no cubre la ventana de look-ahead"
        )
    }

    // MARK: - Publicar mientras suena

    func testTrackCanBePublishedWhilePlaying() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        defer { transport.stop() }

        transport.play()
        waitUntil { recorder.noteOnCount >= 1 }

        let steps = Steps(8)!
        transport.publish(Track(shape: Shape(steps: steps, pulses: Pulses(1)!), pool: voicePool))

        let after = recorder.noteOnCount
        waitUntil { recorder.noteOnCount > after }
        XCTAssertGreaterThan(recorder.noteOnCount, after, "dejó de sonar tras publicar")
    }
}
