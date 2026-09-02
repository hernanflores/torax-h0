import Engine
import XCTest
@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del gate: el Track inaudible no emite, **pero su rejilla avanza**
/// (FR3).
///
/// **Las dos mitades importan lo mismo.** Que no emita es lo obvio; que la
/// rejilla siga corriendo es lo que hace de esto un mute de mixer y no un stop
/// del Track. Quitar el mute tiene que devolverlo donde iba, no al principio, y
/// eso solo se ve dejando pasar tiempo con el Track callado.
///
/// Se testea sobre `PatternScheduler` y no sobre `SchedulerThread` por la misma
/// razón que el resto de la suite: el horizonte se da a mano, así que «dos
/// vueltas después» es un hecho comprobable y no una carrera contra el reloj.
final class MuteGateTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000

    // MARK: - No emitir

    /// Un Track muteado no emite; los demás siguen exactamente igual.
    func testAMutedTrackEmitsNothingAndTheOthersAreUntouched() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(
            tracks: [0: pulsingTrack(pitch: 60), 5: pulsingTrack(pitch: 72)], mutes: mutes)

        mutes.toggleMute(0)
        let events = emit(&scheduler, upToStep: 16)

        XCTAssertTrue(events.filter { $0.track == 0 }.isEmpty)
        XCTAssertEqual(events.filter { $0.track == 5 }.map(\.step), [0, 4, 8, 12])
    }

    /// Sin máscara —la vía del arnés de medición— suenan todos: el gate no
    /// existe para quien no lo pide.
    func testWithoutAMaskEverythingSounds() {
        var scheduler = makeScheduler(tracks: [0: pulsingTrack()], mutes: nil)

        XCTAssertEqual(emit(&scheduler, upToStep: 16).map(\.step), [0, 4, 8, 12])
    }

    /// Mutear a mitad de ventana no reescribe el pasado: lo ya emitido se queda.
    func testMutingBetweenWindowsOnlyAffectsWhatComesAfter() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(tracks: [0: pulsingTrack()], mutes: mutes)

        let before = emit(&scheduler, upToStep: 8)
        mutes.toggleMute(0)
        let after = emit(&scheduler, upToStep: 16)

        XCTAssertEqual(before.map(\.step), [0, 4])
        XCTAssertTrue(after.isEmpty)
    }

    // MARK: - La rejilla sigue

    /// **La prueba de la fase.** Mutear, dejar pasar el tiempo y desmutear
    /// devuelve el Track a la posición que le tocaba —Steps 8 y 12— y no al
    /// principio del anillo. Si el mute parase el Track, aquí saldría `[0, 4]`.
    func testUnmutingReturnsTheTrackInPhaseAndNotFromTheStart() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(tracks: [0: pulsingTrack()], mutes: mutes)

        mutes.toggleMute(0)
        XCTAssertTrue(emit(&scheduler, upToStep: 6).isEmpty)

        mutes.toggleMute(0)
        XCTAssertEqual(emit(&scheduler, upToStep: 16).map(\.step), [8, 12])
    }

    /// Y con un vecino sonando al lado, para que se vea que los dos comparten
    /// rejilla: al volver, el muteado cae en los mismos Steps que el que nunca
    /// calló.
    func testTheUnmutedTrackLandsOnTheSameStepsAsTheOneThatNeverStopped() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(
            tracks: [0: pulsingTrack(pitch: 60), 1: pulsingTrack(pitch: 72)], mutes: mutes)

        mutes.toggleMute(0)
        _ = emit(&scheduler, upToStep: 6)
        mutes.toggleMute(0)

        let events = emit(&scheduler, upToStep: 16)
        XCTAssertEqual(
            events.filter { $0.track == 0 }.map(\.step),
            events.filter { $0.track == 1 }.map(\.step)
        )
    }

    // MARK: - Solo

    /// Un solo calla a los otros once sin tocar sus rejillas.
    func testASoloSilencesTheOthersWithoutTouchingTheirGrids() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(
            tracks: [0: pulsingTrack(pitch: 60), 2: pulsingTrack(pitch: 72)], mutes: mutes)

        mutes.toggleSolo(2)
        let soloed = emit(&scheduler, upToStep: 6)
        XCTAssertEqual(soloed.map(\.track), [2, 2])

        mutes.toggleSolo(2)
        let back = emit(&scheduler, upToStep: 16)
        XCTAssertEqual(back.filter { $0.track == 0 }.map(\.step), [8, 12])
    }

    /// Un Track soleado **y** muteado no emite: la regla de audibilidad manda
    /// también aquí, y no solo en su propia suite.
    func testASoloedAndMutedTrackStillEmitsNothing() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(tracks: [0: pulsingTrack()], mutes: mutes)

        mutes.toggleSolo(0)
        mutes.toggleMute(0)

        XCTAssertTrue(emit(&scheduler, upToStep: 16).isEmpty)
    }

    // MARK: - Una lectura por ventana

    /// **La máscara se lee una vez por ventana, no una por evento.** Dos
    /// lecturas dentro de la misma ventana podrían caer a ambos lados de un
    /// gesto y partirla: unos Steps del Track sonarían y otros no, sin que nadie
    /// haya pedido eso. Se comprueba cambiando la máscara *desde dentro* del
    /// cierre de emisión: lo que se decidió al empezar la ventana es lo que rige
    /// hasta el final.
    func testTheMaskIsReadOncePerWindow() {
        let mutes = MuteMask()
        var scheduler = makeScheduler(tracks: [0: pulsingTrack()], mutes: mutes)

        var steps: [Int] = []
        scheduler.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: nil) {
            _, _, step, _, _, _ in
            steps.append(step)
            mutes.toggleMute(0)
        }

        XCTAssertEqual(steps, [0, 4, 8, 12], "la ventana se partió a mitad")
    }

    // MARK: - El hilo de verdad

    /// **El cableado, extremo a extremo.** Las pruebas de arriba dan el
    /// horizonte a mano; ésta arranca el hilo real y comprueba que la máscara
    /// llega hasta él: mientras suena, mutear detiene la emisión.
    ///
    /// No mide *cuándo* deja de emitir —eso es una carrera contra el reloj— sino
    /// que **deja de emitir y no vuelve**: se toma la cuenta tras dejarla
    /// asentar y se comprueba que no crece.
    func testMutingReachesTheRunningSchedulerThread() {
        let emitted = AtomicCounter()
        let mutes = MuteMask()
        let pattern = Pattern().replacing(pulsingTrack(), at: 0)

        let thread = SchedulerThread(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: tempo, division: .sixteenth)),
            pattern: pattern,
            mutes: mutes
        ) { _, _, _, _, _, _ in
            emitted.increment()
        }

        thread.start()
        defer { thread.stop() }

        let deadline = Date().addingTimeInterval(2)
        while emitted.value < 4 && Date() < deadline { usleep(5_000) }
        XCTAssertGreaterThanOrEqual(emitted.value, 4, "el hilo no llegó a emitir")

        mutes.toggleMute(0)

        // Que se asiente: la ventana en curso puede llevar eventos ya decididos.
        usleep(120_000)
        let settled = emitted.value
        usleep(400_000)

        XCTAssertEqual(emitted.value, settled, "siguió emitiendo con el Track muteado")
    }

    // MARK: - Helpers

    /// Un Track de 16 Steps con 4 Pulses: dispara en 0, 4, 8 y 12.
    private func pulsingTrack(pitch: Int = 60) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!, division: .sixteenth),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    private func makeScheduler(tracks: [Int: Cycle], mutes: MuteMask?) -> PatternScheduler {
        let pattern = tracks.reduce(into: Pattern()) { $0 = $0.replacing($1.value, at: $1.key) }
        return PatternScheduler(tempo: tempo, pattern: pattern, mutes: mutes)
    }

    private func emit(
        _ scheduler: inout PatternScheduler, upToStep stepIndex: Int
    ) -> [(track: Int, step: Int)] {
        var events: [(track: Int, step: Int)] = []
        scheduler.advance(toHorizon: Int64(stepIndex) * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, _, _, _ in
            events.append((track, step))
        }
        return events
    }
}
