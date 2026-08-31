import Engine
import XCTest

@testable import MIDI

/// Tests del desplazamiento temporal visto desde el scheduler.
///
/// Se testea sobre `TrackScheduler` y no sobre `SchedulerThread` por la misma
/// razón que el resto de `TrackSchedulerTests`: aquí el horizonte se le da a
/// mano, así que lo que se comprueba es un hecho y no una carrera contra el
/// reloj.
final class SchedulerShiftTests: XCTestCase {

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private let step: Int64 = 125_000_000

    private func track(timing: Int = 50, delay: Int = 0) -> Track {
        Track(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().toggling(Pitch(60)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: Timing(percent: timing)!,
                delay: Delay(percent: delay)!
            )
        )
    }

    /// Avanza una ventana y devuelve los pares (Step, offset emitido).
    private func emit(
        _ scheduler: inout TrackScheduler,
        toHorizon horizon: Int64,
        from handoff: TrackHandoff? = nil
    ) -> [(step: Int, offset: Int64)] {
        var emitted: [(step: Int, offset: Int64)] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) { step, _, _, offset in
            emitted.append((step, offset))
        }
        return emitted
    }

    // MARK: - La rejilla recta no se toca

    /// **La propiedad de la que depende la medición de regresión de la Fase 6.**
    /// Con el Groove default cada Step se emite en el offset que ya emitía antes
    /// de la rebanada 6 — el de `MusicalTimeline`, sin sumar ni restar nada.
    func testWithTheDefaultGrooveEveryStepKeepsItsGridOffset() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))

        for (step, offset) in emit(&scheduler, toHorizon: 8 * step) {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }

    /// El modo del arnés de medición tampoco se mueve: usa `Groove.default`, que
    /// es la rejilla recta.
    func testTheMeasurementModeStaysOnTheGrid() {
        var scheduler = TrackScheduler(timeline: timeline, material: .everyStep)

        for (step, offset) in emit(&scheduler, toHorizon: 8 * step) {
            XCTAssertEqual(offset, timeline.nanosecondOffset(forStep: step))
        }
    }

    // MARK: - El offset emitido lleva el desplazamiento

    func testTheEmittedOffsetIsTheGridPlusTheShift() {
        let swung = track(timing: 75, delay: 25)
        var scheduler = TrackScheduler(timeline: timeline, material: .track(swung))

        for (step, offset) in emit(&scheduler, toHorizon: 8 * self.step) {
            let expected =
                timeline.nanosecondOffset(forStep: step)
                + swung.groove.shiftNanoseconds(atStep: step, stepDurationNanoseconds: self.step)

            XCTAssertEqual(offset, expected, "el Step \(step) no llevó su desplazamiento")
        }
    }

    /// Al 75% los Steps impares caen medio Step tarde y los pares no se mueven:
    /// la rejilla emitida es no uniforme, que es lo que el swing significa.
    func testSwingProducesANonUniformEmittedGrid() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track(timing: 75)))
        let emitted = emit(&scheduler, toHorizon: 4 * step)

        XCTAssertEqual(emitted.map(\.offset), [0, step + step / 2, 2 * step, 3 * step + step / 2])
    }

    /// **Cada Step se sigue emitiendo exactamente una vez.** La invariante de
    /// `LookAheadScheduler` sobrevive al desplazamiento y a la ampliación del
    /// horizonte: los rangos siguen siendo contiguos y la marca de agua solo
    /// avanza.
    func testEveryStepIsStillEmittedExactlyOnceAcrossWindows() {
        var scheduler = TrackScheduler(
            timeline: timeline, material: .track(track(timing: 75, delay: -100)))

        var steps: [Int] = []
        for window in 1...8 {
            steps += emit(&scheduler, toHorizon: Int64(window) * 4 * step).map(\.step)
        }

        XCTAssertEqual(steps, Array(steps.sorted()), "los Steps salieron desordenados")
        XCTAssertEqual(steps.count, Set(steps).count, "algún Step se emitió dos veces")
    }

    // MARK: - El horizonte se amplía con el presupuesto

    /// **El caso que hace falta para que un evento adelantado no caiga en el
    /// pasado.** Con Delay −100% el Step tiene que calcularse un Step antes de
    /// su rejilla, así que entra en una ventana anterior a la que le tocaría.
    func testANegativeDelaySelectsStepsEarlier() {
        var straight = TrackScheduler(timeline: timeline, material: .track(track()))
        var advanced = TrackScheduler(timeline: timeline, material: .track(track(delay: -100)))

        let horizon = step / 2

        XCTAssertEqual(emit(&straight, toHorizon: horizon).map(\.step), [0])
        XCTAssertEqual(emit(&advanced, toHorizon: horizon).map(\.step), [0, 1])
    }

    /// **Con Delay ≥ 0 el horizonte es idéntico al de hoy.** Es la mitad del
    /// rango donde vive el default, y no puede pagar el coste de la otra mitad:
    /// ni look-ahead más largo ni respuesta de knob más lenta.
    func testANonNegativeDelaySelectsExactlyTheSameStepsAsBefore() {
        for percent in [0, 25, 50, 100] {
            var scheduler = TrackScheduler(
                timeline: timeline, material: .track(track(delay: percent)))

            XCTAssertEqual(
                emit(&scheduler, toHorizon: 4 * step).map(\.step),
                [0, 1, 2, 3],
                "Delay \(percent)% cambió qué Steps caen en la ventana"
            )
        }
    }

    /// El swing tampoco amplía el horizonte: solo atrasa, así que no necesita
    /// presupuesto.
    func testSwingDoesNotWidenTheHorizon() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track(timing: 75)))

        XCTAssertEqual(emit(&scheduler, toHorizon: 4 * step).map(\.step), [0, 1, 2, 3])
    }

    /// **El presupuesto se relee del snapshot, no se fija al construir.** Delay
    /// se puede girar mientras suena, y un presupuesto congelado dejaría de
    /// cubrir el adelanto en cuanto el knob se moviera.
    func testTheBudgetComesFromThePublishedSnapshotAndNotFromConstruction() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))
        let handoff = TrackHandoff(track())

        // Sin Delay: la ventana de medio Step solo alcanza al Step 0.
        XCTAssertEqual(emit(&scheduler, toHorizon: step / 2).map(\.step), [0])

        // Se publica un Delay negativo. La ventana siguiente llega justo al
        // borde del Step 1: sin presupuesto no emitiría nada —el horizonte es
        // exclusivo— y con él lo alcanza. Ese contraste es la señal.
        handoff.publish(Engine.Pattern().replacing(track(delay: -100), at: 0))
        XCTAssertEqual(
            emit(&scheduler, toHorizon: step, from: handoff).map(\.step),
            [1],
            "el presupuesto no se releyó del snapshot"
        )
    }

    /// La otra mitad del contraste anterior: sin Delay, esa misma ventana no
    /// alcanza al Step 1. Están separados para que el que falle diga cuál de las
    /// dos cosas se rompió.
    func testWithoutBudgetTheSameWindowReachesNothing() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))

        XCTAssertEqual(emit(&scheduler, toHorizon: step / 2).map(\.step), [0])
        XCTAssertEqual(emit(&scheduler, toHorizon: step).map(\.step), [])
    }

    /// El desplazamiento sale del **mismo** snapshot que la altura y el Groove:
    /// no son dos lecturas que puedan discrepar en el borde de una ventana.
    func testTheShiftComesFromTheSameSnapshotAsTheGroove() {
        var scheduler = TrackScheduler(timeline: timeline, material: .track(track()))
        let handoff = TrackHandoff(track())
        handoff.publish(Engine.Pattern().replacing(track(timing: 75, delay: 50), at: 0))

        var seen: [(groove: Groove, offset: Int64, step: Int)] = []
        scheduler.advance(toHorizon: 4 * step, refreshingFrom: handoff) { step, _, groove, offset in
            seen.append((groove, offset, step))
        }

        XCTAssertFalse(seen.isEmpty)
        for entry in seen {
            let expected =
                timeline.nanosecondOffset(forStep: entry.step)
                + entry.groove.shiftNanoseconds(
                    atStep: entry.step, stepDurationNanoseconds: step)

            XCTAssertEqual(entry.offset, expected)
        }
    }
}

/// Recolector de eventos seguro entre hilos.
///
/// El handler del scheduler corre en su propio hilo, así que acumular en un
/// `var` capturado no compila —ni debería—. Esto es infraestructura de test, no
/// código de tiempo real: aquí un lock es exactamente lo correcto.
private final class EmittedEvents: @unchecked Sendable {

    private let lock = NSLock()
    private var times: [UInt64] = []
    private var steps: [Int] = []
    private var elapsed: [Int64?] = []

    /// La lectura del playhead se toma **dentro** del handler, mientras el
    /// transporte corre. Leerla después de `stop()` daría siempre `nil`: parar
    /// deja el reloj quieto, que es justo lo que `PlayheadClock` promete.
    func record(step: Int, hostTime: UInt64, playheadElapsed: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        times.append(hostTime)
        steps.append(step)
        elapsed.append(playheadElapsed)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return times.count
    }

    var snapshot: (times: [UInt64], steps: [Int], elapsed: [Int64?]) {
        lock.lock()
        defer { lock.unlock() }
        return (times, steps, elapsed)
    }
}

/// Tests del origen de la rejilla — la segunda pieza del presupuesto de
/// adelanto.
///
/// **Estos sí arrancan el bucle del scheduler**, y no hay forma de evitarlo: el
/// origen lo fija `SchedulerThread` al arrancar el hilo, así que dándole el
/// horizonte a mano no se puede observar. Es el punto que el plan de la rebanada
/// 6 anticipó, y la decisión ya está tomada —`midi-test-flake_20260826` queda
/// aplazado a después de la v2, por decisión del 2026-08-29—: se escriben los
/// tests y se convive con el ruido. Un fallo `clientCreationFailed(-50)` en
/// `VirtualLoopbackTests` se descarta comparando 3–4 pasadas contra `main`.
final class SchedulerOriginTests: XCTestCase {

    private let stepDuration: Int64 = 125_000_000

    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private var configuration: SchedulerConfiguration {
        SchedulerConfiguration(timeline: timeline, lookAheadNanoseconds: 20_000_000)
    }

    private func track(timing: Int = 50, delay: Int = 0) -> Track {
        Track(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().toggling(Pitch(60)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: Timing(percent: timing)!,
                delay: Delay(percent: delay)!
            )
        )
    }

    /// Corre el hilo hasta reunir `count` eventos y devuelve sus instantes de
    /// emisión, junto al instante en que se pidió arrancar.
    private func run(
        untilEmitted count: Int,
        material track: Track,
        playhead: PlayheadClock? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (start: UInt64, times: [UInt64], steps: [Int], elapsed: [Int64?]) {
        let events = EmittedEvents()

        let thread = SchedulerThread(
            configuration: configuration,
            material: .track(track),
            playhead: playhead
        ) { step, _, _, hostTime in
            events.record(
                step: step,
                hostTime: hostTime,
                playheadElapsed: playhead?.elapsedNanoseconds(now: hostTime)
            )
        }

        let start = HostClock.now()
        thread.start()
        let deadline = Date().addingTimeInterval(3)
        while events.count < count && Date() < deadline { usleep(2_000) }
        thread.stop()

        let collected = events.snapshot
        XCTAssertGreaterThanOrEqual(
            collected.times.count, count, "el hilo no emitió lo suficiente", file: file, line: line)
        return (start, collected.times, collected.steps, collected.elapsed)
    }

    /// **El criterio de aceptación FR4, visto desde el hilo.** Con Delay −100%
    /// ningún evento se pide para un instante anterior al arranque del
    /// transporte: el origen de la rejilla es `Play + presupuesto`, así que el
    /// Step 0 adelantado un Step entero cae justo en el arranque y no antes.
    ///
    /// **Y la comprobación que de verdad distingue, en la misma pasada.**
    /// «Ningún evento antes del arranque» lo cumple también un recorte al
    /// presente —`max(0, offset)`—, que no adelanta nada: **aplasta** contra el
    /// instante de Play todos los eventos que debían sonar antes, y dos Steps
    /// distintos acaban pidiéndose para el mismo instante. Con el origen
    /// desplazado no se aplasta ninguno: los instantes son estrictamente
    /// crecientes y separados por una Division, exactamente como sin Delay. Lo
    /// que el parámetro mueve es la voz entera, no la distancia entre sus notas.
    ///
    /// **Las dos comprobaciones comparten pasada a propósito.** Son el mismo
    /// escenario, y cada arranque del bucle del scheduler es presión añadida
    /// sobre `midi-test-flake_20260826`: partirlas costaría un hilo más a
    /// prioridad máxima sin decir nada que esto no diga.
    func testAFullyNegativeDelayLandsOnTheStartInsteadOfBeforeIt() {
        let result = run(untilEmitted: 8, material: track(delay: -100))

        for (index, hostTime) in result.times.enumerated() {
            XCTAssertGreaterThanOrEqual(
                hostTime, result.start,
                "el evento \(index) se pidió para un instante anterior al arranque"
            )
        }

        for (previous, current) in zip(result.times, result.times.dropFirst()) {
            XCTAssertGreaterThan(
                current, previous,
                "dos Steps se pidieron para el mismo instante: se recortaron al presente"
            )
            let gap = Int64(HostClock.nanoseconds(fromHostTicks: current &- previous))
            XCTAssertEqual(gap, stepDuration, accuracy: 1_000_000)
        }
    }

    /// El swing no adelanta nada —solo atrasa— así que sumarlo al Delay más
    /// negativo tampoco puede sacar ningún evento del arranque.
    func testWithMaximumSwingNoEventIsScheduledBeforeTheTransportStarted() {
        let result = run(untilEmitted: 8, material: track(timing: 75, delay: -100))

        for hostTime in result.times {
            XCTAssertGreaterThanOrEqual(hostTime, result.start)
        }

        for (previous, current) in zip(result.times, result.times.dropFirst()) {
            XCTAssertGreaterThan(current, previous)
        }
    }

    /// **Con Delay ≥ 0 el origen es el instante de Play, sin latencia añadida.**
    /// El Step 0 cae prácticamente en el arranque; con presupuesto se habría
    /// retrasado un Step entero, que a 1/16 y 120 BPM son 125 ms — muy por
    /// encima de la tolerancia de este test.
    func testWithANonNegativeDelayTheOriginIsPlayItself() {
        let result = run(untilEmitted: 4, material: track())

        guard let first = result.times.first, result.steps.first == 0 else {
            return XCTFail("no se emitió el Step 0")
        }
        let latency = Int64(HostClock.nanoseconds(fromHostTicks: first &- result.start))

        XCTAssertLessThan(
            latency, 20_000_000,
            "el arranque se retrasó sin que ningún Delay negativo lo pidiera"
        )
    }

    /// **El playhead usa el mismo origen que sella los timestamps.** Si fueran
    /// dos, el anillo y lo que suena discreparían —es lo que `SchedulerThread` ya
    /// documenta—, y ahora que el origen se desplaza hay una forma de romperlo
    /// que antes no existía.
    ///
    /// Se comprueba con swing, que es el caso donde el instante de emisión y el
    /// de rejilla difieren: el tiempo que el playhead lleva contando en el
    /// instante de cada evento es el offset **desplazado** de ese Step.
    func testThePlayheadSharesTheOriginThatStampsTheTimestamps() {
        let swung = track(timing: 75)
        let result = run(untilEmitted: 6, material: swung, playhead: PlayheadClock())

        for (reading, index) in zip(result.elapsed, result.steps) {
            guard let elapsed = reading else {
                return XCTFail("el playhead no estaba corriendo")
            }
            let expected =
                timeline.nanosecondOffset(forStep: index)
                + swung.groove.shiftNanoseconds(
                    atStep: index, stepDurationNanoseconds: stepDuration)

            XCTAssertEqual(
                elapsed, expected, accuracy: 1_000_000,
                "el playhead y el timestamp no comparten origen en el Step \(index)"
            )
        }
    }
}
