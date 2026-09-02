import Engine
import XCTest
@testable import MIDI

/// Tests del relevo de snapshot dentro del scheduler.
///
/// Se testea sobre `TrackScheduler` y no sobre `SchedulerThread` a propósito:
/// aquí el horizonte se le da a mano, así que «la ventana siguiente» es un
/// hecho comprobable y no una carrera contra el reloj. El hilo se limita a
/// calcular ese horizonte.
final class TrackSchedulerTests: XCTestCase {

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private var stepNanoseconds: Int64 { 125_000_000 }

    /// **Con pool desde la v2.** Un Track sin alturas no se programa —el coste
    /// crece con los Tracks que suenan, no con dieciséis siempre— así que un
    /// Track de prueba que quiera emitir necesita material.
    private func track(steps stepCount: Int, pulses pulseCount: Int, rotate amount: Int = 0)
        -> Track
    {
        let steps = Steps(stepCount)!
        return Track(
            shape: Shape(
                steps: steps,
                pulses: Pulses(pulseCount)!,
                rotate: Rotate(amount)
            ),
            pool: PitchPool().inserting(Pitch(60)!)
        )
    }

    /// Anillo lleno: todos los Steps disparan. Sirve para comprobar continuidad
    /// sin que el reparto euclidiano se mezcle en la cuenta.
    private func fullRing(_ stepCount: Int) -> Track {
        track(steps: stepCount, pulses: stepCount)
    }

    /// Avanza el scheduler una ventana y devuelve los Steps emitidos.
    private func emit(
        _ scheduler: inout TrackScheduler,
        upToStep stepIndex: Int,
        from handoff: PatternHandoff? = nil
    ) -> [Int] {
        var steps: [Int] = []
        scheduler.advance(
            toHorizon: Int64(stepIndex) * stepNanoseconds,
            refreshingFrom: handoff
        ) { step, _, _, _ in steps.append(step) }
        return steps
    }

    // MARK: - Solo se emiten los Steps que disparan

    func testOnlyTriggeringStepsAreEmitted() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))
        XCTAssertEqual(emit(&scheduler, upToStep: 16), [0, 4, 8, 12])
    }

    func testRotateShiftsWhichStepsAreEmitted() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4, rotate: 1)))
        XCTAssertEqual(emit(&scheduler, upToStep: 16), [1, 5, 9, 13])
    }

    /// El anillo se recorre sin fin: la segunda vuelta repite las posiciones con
    /// índices de Step más altos.
    func testRingRepeatsOnTheSecondLap() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))
        _ = emit(&scheduler, upToStep: 16)
        XCTAssertEqual(emit(&scheduler, upToStep: 32), [16, 20, 24, 28])
    }

    /// El offset que se entrega es el del Step, no el del horizonte.
    func testEmittedOffsetIsTheStepOffset() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))
        var offsets: [Int64] = []
        scheduler.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: nil) { _, _, _, offset in
            offsets.append(offset)
        }
        XCTAssertEqual(offsets, [0, 4, 8, 12].map { Int64($0) * stepNanoseconds })
    }

    // MARK: - Relevo del snapshot a media reproducción

    /// El test central de la fase: publicar mientras suena se recoge en la
    /// ventana siguiente, no en la actual ni tres ventanas después.
    func testSnapshotPublishedMidPlaybackIsPickedUpByTheNextWindow() {
        let handoff = PatternHandoff(track(steps: 16, pulses: 4))
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))

        XCTAssertEqual(emit(&scheduler, upToStep: 16, from: handoff), [0, 4, 8, 12])

        handoff.publish(Engine.Pattern().replacing(track(steps: 16, pulses: 4, rotate: 2), at: 0))

        // Segunda vuelta del anillo, ya con el Track nuevo: 2, 6, 10, 14.
        XCTAssertEqual(emit(&scheduler, upToStep: 32, from: handoff), [18, 22, 26, 30])
    }

    /// Sin publicar nada, el scheduler conserva el Track con el que arrancó.
    func testWithoutPublishingTheTrackIsUnchanged() {
        let handoff = PatternHandoff(track(steps: 16, pulses: 4))
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))
        for lap in 1...4 {
            let expected = [0, 4, 8, 12].map { $0 + (lap - 1) * 16 }
            XCTAssertEqual(emit(&scheduler, upToStep: lap * 16, from: handoff), expected)
        }
    }

    // MARK: - Ni duplicar ni omitir

    /// Cambiar de snapshot no puede duplicar ni perder un Step: sobre anillos
    /// llenos —donde todos disparan— la secuencia emitida tiene que ser los
    /// enteros consecutivos desde cero, sin huecos ni repeticiones.
    func testChangingSnapshotNeverDuplicatesOrDropsAStep() {
        let handoff = PatternHandoff(fullRing(16))
        var scheduler = TrackScheduler(timeline: timeline, material: .track(fullRing(16)))

        var emitted: [Int] = []
        for window in 1...40 {
            handoff.publish(Engine.Pattern().replacing(fullRing((window % 16) + 1), at: 0))
            emitted += emit(&scheduler, upToStep: window * 3, from: handoff)
        }

        XCTAssertEqual(emitted, Array(0..<(40 * 3)))
    }

    /// Lo mismo publicando a mitad de ventana en lugar de entre ventanas.
    func testStepSequenceStaysContiguousAcrossManySnapshotChanges() {
        let handoff = PatternHandoff(fullRing(8))
        var scheduler = TrackScheduler(timeline: timeline, material: .track(fullRing(8)))

        var emitted: [Int] = []
        for window in 1...60 {
            emitted += emit(&scheduler, upToStep: window * 2, from: handoff)
            handoff.publish(Engine.Pattern().replacing(fullRing((window % 8) + 1), at: 0))
        }

        XCTAssertEqual(emitted, Array(0..<(60 * 2)))
    }

    // MARK: - Lectura descartada

    /// Si la lectura del snapshot se descarta, el scheduler sigue con el Track
    /// que ya tenía en vez de emitir cualquier cosa.
    func testDiscardedSnapshotReadKeepsThePreviousTrack() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(steps: 16, pulses: 4)))
        // `nil` es exactamente lo que `PatternHandoff.load()` devuelve al
        // descartar, así que pasar nil reproduce ese caso.
        XCTAssertEqual(emit(&scheduler, upToStep: 16, from: nil), [0, 4, 8, 12])
        XCTAssertEqual(scheduler.material, .track(track(steps: 16, pulses: 4)))
    }

    // MARK: - Los dos significados no se confunden

    /// `.everyStep` es el modo del arnés: mide la rejilla, no el material.
    func testEveryStepMaterialEmitsAllSteps() {
        var scheduler = TrackScheduler(timeline: timeline, material: .everyStep)
        XCTAssertEqual(emit(&scheduler, upToStep: 5), [0, 1, 2, 3, 4])
    }

    /// El caso que motivó separar los dos significados: un descarte de lectura
    /// del handoff **no** puede convertirse en `.everyStep`. Antes esto era un
    /// `Track?` compartido con el `nil` de `load()`, y un descarte habría hecho
    /// sonar el anillo entero a densidad máxima.
    func testDiscardedReadCannotTurnIntoEveryStep() {
        let handoff = PatternHandoff(track(steps: 16, pulses: 4))
        var scheduler = TrackScheduler(
            timeline: timeline,
            material: .track(track(steps: 16, pulses: 4))
        )
        // `nil` es exactamente lo que `load()` devuelve al descartar.
        XCTAssertEqual(emit(&scheduler, upToStep: 16, from: nil), [0, 4, 8, 12])
        XCTAssertEqual(scheduler.material, .track(track(steps: 16, pulses: 4)))
        XCTAssertEqual(emit(&scheduler, upToStep: 32, from: handoff), [16, 20, 24, 28])
    }

    // MARK: - Horizonte

    func testHorizonThatDoesNotAdvanceEmitsNothing() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(fullRing(16)))
        XCTAssertEqual(emit(&scheduler, upToStep: 4), [0, 1, 2, 3])
        XCTAssertEqual(emit(&scheduler, upToStep: 4), [])
        XCTAssertEqual(emit(&scheduler, upToStep: 2), [])
    }
}

/// Comprobación de extremo a extremo sobre el hilo real.
///
/// `TrackSchedulerTests` verifica el relevo de forma determinista dándole el
/// horizonte a mano. Esto verifica lo otro: que el hilo lo consulta de verdad,
/// que es donde tiene que ocurrir en producto.
final class SchedulerThreadSnapshotTests: XCTestCase {

    /// 300 BPM con Division 1/16 da un Step de 50 ms, así que un anillo 16/4
    /// dispara cada 200 ms. Es el tempo más alto que admite `Tempo`, elegido
    /// para que el test no tarde: no hay nada musical en ese número.
    private func configuration() -> SchedulerConfiguration {
        SchedulerConfiguration(
            timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth),
            lookAheadNanoseconds: 20_000_000
        )
    }

    /// Con pool: desde la v2 un Track sin alturas no se programa.
    private func track(rotate amount: Int) -> Track {
        let steps = Steps(16)!
        return Track(
            shape: Shape(steps: steps, pulses: Pulses(4)!, rotate: Rotate(amount)),
            pool: PitchPool().inserting(Pitch(60)!)
        )
    }

    func testRunningSchedulerPicksUpAPublishedTrack() {
        let handoff = PatternHandoff(track(rotate: 0))
        let emitted = AtomicCounter()
        let unexpectedPosition = AtomicFlag(false)
        // El Rotate que el handler espera ver. Lo cambia el test al publicar.
        let expectedOffset = AtomicCounter(0)

        let thread = SchedulerThread(
            configuration: configuration(),
            material: .track(track(rotate: 0)),
            handoff: handoff
        ) { _, _, step, _, _, _ in
            if UInt64(step % 4) != expectedOffset.value { unexpectedPosition.value = true }
            emitted.increment()
        }

        thread.start()
        defer { thread.stop() }

        // Primera fase: sin publicar, solo disparan los Steps múltiplos de 4.
        waitFor(emitted, toReach: 3, timeout: 4)
        XCTAssertFalse(unexpectedPosition.value, "emitió fuera de las posiciones de 16/4")

        // Se publica un giro de dos Steps a media reproducción.
        handoff.publish(Engine.Pattern().replacing(track(rotate: 2), at: 0))

        // Margen para que el relevo se consuma: el Track viejo puede tener Steps
        // ya entregados dentro de la ventana en curso.
        usleep(300_000)
        expectedOffset.value = 2
        unexpectedPosition.value = false

        let before = emitted.value
        waitFor(emitted, toReach: before + 3, timeout: 4)
        XCTAssertFalse(unexpectedPosition.value, "no recogió el Track publicado")
    }

    private func waitFor(_ counter: AtomicCounter, toReach target: UInt64, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while counter.value < target && Date() < deadline { usleep(5_000) }
        XCTAssertGreaterThanOrEqual(counter.value, target, "el scheduler no emitió a tiempo")
    }
}
