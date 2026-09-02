import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del avance de Cycle en el límite de vuelta.
///
/// **Es la fase que hace que Cycles se oiga**, y la que toca el hilo de tiempo
/// real. Se testea sobre `PatternScheduler` y no sobre `SchedulerThread` por la
/// misma razón que el resto del scheduling: aquí el horizonte se da a mano, así
/// que «la vuelta siguiente» es un hecho comprobable y no una carrera contra el
/// reloj.
final class CycleAdvanceTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step dura 125 ms a 120 BPM con Division 1/16.
    private let stepNanoseconds: Int64 = 125_000_000

    /// Un Cycle que dispara en todos sus Steps, reconocible por su altura.
    ///
    /// La altura es lo que identifica al Cycle en lo emitido: es el dato que
    /// llega hasta el emisor, así que un test que la mire está comprobando lo
    /// que de verdad sonaría.
    private func cycle(steps: Int = 16, pitch: Int, division: Division = .sixteenth) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(steps)!, pulses: Pulses(steps)!, division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Un Track con N Cycles activos, cada uno con su altura.
    private func track(_ pitches: [Int], steps: Int = 16, division: Division = .sixteenth)
        -> Track
    {
        var track = Track(cycle(steps: steps, pitch: pitches[0], division: division))
        track = track.withActiveCount(pitches.count)
        for (index, pitch) in pitches.enumerated() {
            track = track.replacing(
                cycle(steps: steps, pitch: pitch, division: division), at: index)
        }
        return track
    }

    private func pattern(_ tracks: [Int: Track]) -> Pattern {
        tracks.reduce(into: Pattern()) { $0 = $0.replacing($1.value, at: $1.key) }
    }

    /// Lo emitido por un Track: el Step y la altura, que es quien delata el
    /// Cycle vigente.
    private func emitted(
        _ scheduler: PatternScheduler,
        upToStep stepIndex: Int,
        track wanted: Int = 0
    ) -> [(step: Int, pitch: Int?)] {
        var events: [(step: Int, pitch: Int?)] = []
        scheduler.advance(
            toHorizon: Int64(stepIndex) * stepNanoseconds,
            refreshingFrom: nil
        ) { track, _, step, pitch, _, _ in
            guard track == wanted else { return }
            events.append((step, pitch?.value))
        }
        return events
    }

    // MARK: - La vuelta propia

    /// **FR5 — el cambio ocurre en el Step 0 de la vuelta siguiente.** Se
    /// comprueba sobre el índice de Step y no de oído: un Track de 16 Steps con
    /// dos Cycles suena el primero en los Steps 0–15 y el segundo desde el 16.
    func testTheCycleChangesAtStepZeroOfTheNextTurn() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60])]))
        let events = emitted(scheduler, upToStep: 32)

        for event in events {
            let expected = (event.step / 16) % 2 == 0 ? 48 : 60
            XCTAssertEqual(event.pitch, expected, "Step \(event.step)")
        }
        XCTAssertEqual(events.count, 32, "faltan Steps")
    }

    /// Y vuelve al primero al cerrar la segunda vuelta: es un recorrido, no un
    /// cambio de una vez.
    func testTheTraversalWrapsBackToTheFirstCycle() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let events = emitted(scheduler, upToStep: 64)

        let byTurn = (0..<4).map { turn in events.filter { $0.step / 16 == turn }.map(\.pitch) }
        XCTAssertEqual(byTurn[0], Array(repeating: 48, count: 16))
        XCTAssertEqual(byTurn[1], Array(repeating: 60, count: 16))
        XCTAssertEqual(byTurn[2], Array(repeating: 72, count: 16))
        XCTAssertEqual(byTurn[3], Array(repeating: 48, count: 16), "no volvió al primero")
    }

    /// **FR4 — dos Tracks de longitudes distintas no cambian de Cycle a la vez.**
    /// Uno de 16 Steps cambia en el 16; uno de 12, en el 12. Ese desfase es la
    /// función, no un defecto.
    func testTwoTracksOfDifferentLengthsDoNotChangeCycleTogether() {
        let scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track([48, 60], steps: 16),
                1: track([36, 38], steps: 12),
            ])
        )

        var first: [(step: Int, pitch: Int?)] = []
        var second: [(step: Int, pitch: Int?)] = []
        scheduler.advance(toHorizon: 24 * stepNanoseconds, refreshingFrom: nil) {
            track, _, step, pitch, _, _ in
            if track == 0 { first.append((step, pitch?.value)) }
            if track == 1 { second.append((step, pitch?.value)) }
        }

        XCTAssertEqual(first.first(where: { $0.pitch == 60 })?.step, 16)
        XCTAssertEqual(second.first(where: { $0.pitch == 38 })?.step, 12)
    }

    /// Con Divisions distintas cada uno avanza según **su** vuelta, no según el
    /// tiempo del otro: un Track en 1/8 cierra su anillo en el doble de tiempo
    /// que uno en 1/16, y su Cycle cambia ahí.
    func testWithDifferentDivisionsEachAdvancesOnItsOwnTurn() {
        let scheduler = PatternScheduler(
            tempo: tempo,
            pattern: pattern([
                0: track([48, 60], division: .sixteenth),
                1: track([36, 38], division: .eighth),
            ])
        )

        var changedAt: [Int: Int64] = [:]
        scheduler.advance(toHorizon: 40 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, pitch, _, offset in
            let second = track == 0 ? 60 : 38
            if pitch?.value == second, changedAt[track] == nil { changedAt[track] = offset }
        }

        // El de 1/16 cierra su anillo de 16 Steps en 16 × 125 ms = 2 s; el de
        // 1/8, en 16 × 250 ms = 4 s. El segundo cambia al doble de tiempo.
        XCTAssertEqual(changedAt[0], 2_000_000_000)
        XCTAssertEqual(changedAt[1], 4_000_000_000)
    }

    // MARK: - Sin deriva

    /// **Mil vueltas, no dos compases.** Es como se ven los fallos de fase: un
    /// error de un Step por vuelta es inaudible al principio y evidente al cabo
    /// de un minuto.
    func testAThousandTurnsWithoutDrift() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let events = emitted(scheduler, upToStep: 16 * 1_000)

        XCTAssertEqual(events.count, 16_000)
        for event in events {
            let expected = [48, 60, 72][(event.step / 16) % 3]
            XCTAssertEqual(event.pitch, expected, "derivó en el Step \(event.step)")
        }
    }

    /// Y no depende de cómo se trocee el tiempo: pedir el mismo material en
    /// ventanas pequeñas da lo mismo que pedirlo de una vez. Sin esto, el avance
    /// podría estar contando ventanas en vez de vueltas.
    func testTheResultDoesNotDependOnHowTheHorizonIsChopped() {
        let whole = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        let expected = emitted(whole, upToStep: 96)

        let chopped = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48, 60, 72])]))
        var events: [(step: Int, pitch: Int?)] = []
        for window in 1...96 {
            chopped.advance(toHorizon: Int64(window) * stepNanoseconds, refreshingFrom: nil) {
                track, _, step, pitch, _, _ in
                guard track == 0 else { return }
                events.append((step, pitch?.value))
            }
        }

        XCTAssertEqual(events.map(\.pitch), expected.map(\.pitch))
    }

    // MARK: - No regresión

    /// **FR10 — con un Cycle activo no hay avance y nada cambia.** Es la
    /// condición de no regresión de la rebanada, comprobada donde importa: en lo
    /// que sale del scheduler.
    func testWithASingleActiveCycleNothingChanges() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern([0: track([48])]))
        let events = emitted(scheduler, upToStep: 64)

        XCTAssertEqual(events.count, 64)
        XCTAssertTrue(events.allSatisfy { $0.pitch == 48 }, "cambió algo con un solo Cycle")
    }

    /// Un Track sin Cycles que suenen no rompe el recorrido de los demás: el
    /// coste sigue creciendo con lo que suena (NFR3 de la rebanada 1).
    func testATrackWithNoMaterialDoesNotBreakTheOthers() {
        let silent = Track(
            Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
        ).withActiveCount(3)
        let scheduler = PatternScheduler(
            tempo: tempo, pattern: pattern([0: track([48, 60]), 3: silent]))

        var heard: [Int: Int] = [:]
        scheduler.advance(toHorizon: 32 * stepNanoseconds, refreshingFrom: nil) {
            track, _, _, _, _, _ in
            heard[track, default: 0] += 1
        }

        XCTAssertEqual(heard[0], 32)
        XCTAssertNil(heard[3], "un Track sin material emitió")
    }
}

/// Tests de qué decide el Cycle vigente cuando la vuelta cambia.
///
/// **El Cycle es el juego completo de ajustes, no una parte.** Que cambien a la
/// vez Shape, pool, marco tonal, Groove y canal es lo que separa un Cycle de
/// «unos cuantos parámetros con automatización»: si cambiara la mitad de uno y
/// la mitad de otro, el desarrollo dejaría de ser reproducible y no habría forma
/// de razonar sobre lo que suena.
final class CurrentCycleDecidesEverythingTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000

    private func pattern(_ track: Track) -> Pattern {
        Pattern().replacing(track, at: 0)
    }

    /// Dos Cycles que difieren en **las cinco familias a la vez**. Si el cambio
    /// fuera parcial, alguna de las cinco aserciones se quedaría en el valor del
    /// Cycle anterior.
    private func contrastingTrack() -> Track {
        let first = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: Velocity(40)!, sustain: Sustain(percent: 50)!,
                probability: Probability(percent: 100)!),
            channel: Channel(3)!,
            frame: TonalFrame(scale: .minor, root: .c)
        )
        let second = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(8)!),
            pool: PitchPool().inserting(Pitch(72)!),
            groove: Groove(
                velocity: Velocity(110)!, sustain: Sustain(percent: 150)!,
                probability: Probability(percent: 100)!),
            channel: Channel(9)!,
            frame: TonalFrame(scale: .major, root: Root(7)!)
        )
        return Track(first).withActiveCount(2).replacing(second, at: 1)
    }

    /// Al cruzar el límite cambia el Cycle **entero**: no la mitad de uno y la
    /// mitad de otro.
    func testCrossingTheBoundaryChangesEveryFamilyAtOnce() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(contrastingTrack()))

        var sources: [Int: Cycle] = [:]
        scheduler.advance(toHorizon: 32 * stepNanoseconds, refreshingFrom: nil) {
            _, source, step, _, _, _ in
            sources[step] = source
        }

        let before = sources[15]
        let after = sources[16]
        XCTAssertEqual(before?.shape.pulses.count, 16)
        XCTAssertEqual(before?.channel, Channel(3)!)
        XCTAssertEqual(before?.groove.velocity, Velocity(40)!)
        XCTAssertEqual(before?.frame, TonalFrame(scale: .minor, root: .c))
        XCTAssertEqual(before?.pool.pitch(at: 0), Pitch(48)!)

        XCTAssertEqual(after?.shape.pulses.count, 8)
        XCTAssertEqual(after?.channel, Channel(9)!)
        XCTAssertEqual(after?.groove.velocity, Velocity(110)!)
        XCTAssertEqual(after?.frame, TonalFrame(scale: .major, root: Root(7)!))
        XCTAssertEqual(after?.pool.pitch(at: 0), Pitch(72)!)
    }

    /// Y el Groove con que sale cada nota es el del mismo Cycle que la produjo,
    /// no el de otro: es lo que sella el par de mensajes.
    func testTheGrooveOfEachNoteIsTheOneOfItsOwnCycle() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(contrastingTrack()))

        var mismatched = 0
        scheduler.advance(toHorizon: 64 * stepNanoseconds, refreshingFrom: nil) {
            _, source, _, _, groove, _ in
            if groove != source.groove { mismatched += 1 }
        }

        XCTAssertEqual(mismatched, 0, "una nota salió con el Groove de otro Cycle")
    }

    /// **El Cycle vigente se lee una sola vez al cruzar el límite, no por
    /// evento.** Dentro de una vuelta todos los eventos llevan el mismo Cycle, y
    /// el número de cambios es exactamente el de límites cruzados.
    func testTheCycleChangesOncePerBoundaryAndNotOncePerEvent() {
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(contrastingTrack()))

        var sources: [Cycle] = []
        scheduler.advance(toHorizon: 64 * stepNanoseconds, refreshingFrom: nil) {
            _, source, _, _, _, _ in
            sources.append(source)
        }

        let changes = zip(sources, sources.dropFirst()).filter { $0 != $1 }.count
        XCTAssertEqual(changes, 3, "cuatro vueltas son tres cambios, no \(changes)")
    }

    // MARK: - Un Cycle mudo

    /// **Un Cycle con el pool vacío no emite y no rompe el recorrido.** La
    /// vuelta se cuenta igual y el siguiente sí suena: el coste crece con lo que
    /// suena, no con lo que existe (NFR3 de la rebanada 1).
    func testASilentCycleStillCountsItsTurn() {
        let voiced = { (pitch: Int) in
            Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
                pool: PitchPool().inserting(Pitch(pitch)!)
            )
        }
        let silent = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!))
        let track =
            Track(voiced(48))
            .withActiveCount(3)
            .replacing(silent, at: 1)
            .replacing(voiced(72), at: 2)

        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(track))
        var byTurn: [Int: [Int?]] = [:]
        scheduler.advance(toHorizon: 64 * stepNanoseconds, refreshingFrom: nil) {
            _, _, step, pitch, _, _ in
            byTurn[step / 16, default: []].append(pitch?.value)
        }

        XCTAssertEqual(byTurn[0], Array(repeating: 48, count: 16))
        XCTAssertNil(byTurn[1], "el Cycle mudo emitió")
        XCTAssertEqual(byTurn[2], Array(repeating: 72, count: 16), "la vuelta muda descontó")
        XCTAssertEqual(byTurn[3], Array(repeating: 48, count: 16))
    }

    /// Y un Track que arranca mudo y deja de serlo al cambiar de Cycle empieza a
    /// sonar en esa vuelta: la decisión de emitir no puede estar tomada de
    /// antemano para toda la ventana.
    func testATrackThatStartsSilentSoundsWhenItsSecondCycleArrives() {
        let silent = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!))
        let voiced = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: PitchPool().inserting(Pitch(60)!)
        )
        let track = Track(silent).withActiveCount(2).replacing(voiced, at: 1)

        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern(track))
        var heard: [Int] = []
        // Una sola ventana que cruza el límite: si la decisión de emitir se
        // tomara una vez por ventana, esto no sonaría.
        scheduler.advance(toHorizon: 32 * stepNanoseconds, refreshingFrom: nil) {
            _, _, step, pitch, _, _ in
            if pitch != nil { heard.append(step) }
        }

        XCTAssertEqual(heard, Array(16..<32), "el Cycle con material no llegó a sonar")
    }
}

/// Qué parámetros cambian de verdad al cambiar de Cycle, y cuál no.
///
/// **Los tests de aquí no describen un ideal sino lo que pasa.** Uno de los ocho
/// parámetros —Division— no cambia, y esto lo deja fijado con un número en vez de
/// dejarlo como una sorpresa que alguien encuentre en el iPad. El porqué está en
/// *Known Limitations* del `spec.md`.
final class WhatChangesWithTheCycleTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000

    /// Dos Cycles y lo emitido en las dos primeras vueltas.
    private func turns(
        _ first: Cycle, _ second: Cycle, upToStep stepIndex: Int = 32
    ) -> [(step: Int, pitch: Int?, source: Cycle, offset: Int64)] {
        let track = Track(first).withActiveCount(2).replacing(second, at: 1)
        let scheduler = PatternScheduler(tempo: tempo, pattern: Pattern().replacing(track, at: 0))

        var events: [(step: Int, pitch: Int?, source: Cycle, offset: Int64)] = []
        scheduler.advance(toHorizon: Int64(stepIndex) * stepNanoseconds, refreshingFrom: nil) {
            track, source, step, pitch, _, offset in
            guard track == 0 else { return }
            events.append((step, pitch?.value, source, offset))
        }
        return events
    }

    private func cycle(
        steps: Int = 16, pulses: Int = 16, rotate: Int = 0, pitch: Int = 48,
        division: Division = .sixteenth
    ) -> Cycle {
        Cycle(
            shape: Shape(
                steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate),
                division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    // MARK: - Lo que sí cambia

    /// Pulses cambia el reparto euclidiano de la vuelta nueva.
    func testPulsesChangeWithTheCycle() {
        let events = turns(cycle(pulses: 16), cycle(pulses: 4))

        XCTAssertEqual(events.filter { $0.step < 16 }.count, 16)
        XCTAssertEqual(events.filter { $0.step >= 16 }.count, 4)
    }

    /// Steps cambia la longitud del anillo, y con ella la de la vuelta: el
    /// tercer cambio de Cycle cae donde diga el Cycle que esté sonando.
    func testStepsChangeWithTheCycleAndSoDoesTheTurnLength() {
        let events = turns(cycle(steps: 16, pitch: 48), cycle(steps: 8, pitch: 72), upToStep: 32)

        // El primero ocupa los Steps 0–15; el segundo entra en el 16 y cierra su
        // vuelta ocho Steps después, en el 24.
        XCTAssertEqual(events.first(where: { $0.pitch == 72 })?.step, 16)
        XCTAssertEqual(events.first(where: { $0.step > 16 && $0.pitch == 48 })?.step, 24)
    }

    /// Rotate cambia dónde caen los Pulses de la vuelta nueva.
    func testRotateChangesWithTheCycle() {
        let events = turns(cycle(pulses: 4, rotate: 0), cycle(pulses: 4, rotate: 1))

        let firstTurn = events.filter { $0.step < 16 }.map { $0.step }
        let secondTurn = events.filter { $0.step >= 16 }.map { $0.step - 16 }
        XCTAssertNotEqual(firstTurn, secondTurn, "Rotate no cambió el reparto")
        XCTAssertEqual(secondTurn, firstTurn.map { ($0 + 1) % 16 }.sorted())
    }

    /// El pool, el marco tonal, el Groove y el canal cambian con el Cycle: lo
    /// comprueba `CurrentCycleDecidesEverythingTests` sobre las cinco familias a
    /// la vez. Aquí solo se fija que la altura emitida sale del pool nuevo, que
    /// es lo que llega al sintetizador.
    func testThePoolChangesWithTheCycle() {
        let events = turns(cycle(pitch: 48), cycle(pitch: 72))

        XCTAssertTrue(events.filter { $0.step < 16 }.allSatisfy { $0.pitch == 48 })
        XCTAssertTrue(events.filter { $0.step >= 16 }.allSatisfy { $0.pitch == 72 })
    }

    // MARK: - Lo que no cambia: Division

    /// **Division NO cambia de Cycle a Cycle. Decidido el 2026-09-02, con este
    /// test delante.**
    ///
    /// La rejilla temporal de un Track la fija la `MusicalTimeline` con la que se
    /// construye su scheduler, en Play, y no se vuelve a leer. Cambiar la
    /// Division a mitad de reproducción reubicaría todos los Steps futuros
    /// respecto a un origen que ya pasó, y hacerlo bien exigiría rebasar la línea
    /// de tiempo por Track — es decir, romper el invariante que mantiene en fase
    /// a los dieciséis sin sincronización posterior: **todas las rejillas se
    /// miden contra el mismo origen**.
    ///
    /// Así que se acota: el segundo Cycle suena, con todo lo demás suyo, sobre la
    /// rejilla del Cycle que estaba vigente al pulsar Play. Está escrito en
    /// *Known Limitations* del `spec.md`.
    func testTheDivisionOfLaterCyclesIsIgnoredAndTheGridStays() {
        let events = turns(
            cycle(pitch: 48, division: .sixteenth),
            cycle(pitch: 72, division: .quarter)
        )

        // El material del segundo Cycle sí entra: la altura es la suya.
        XCTAssertEqual(events.first(where: { $0.step == 16 })?.pitch, 72)
        // Pero cae sobre la rejilla de 1/16 —125 ms por Step— y no sobre la de
        // 1/4, que serían 500 ms.
        XCTAssertEqual(events.first(where: { $0.step == 16 })?.offset, 16 * stepNanoseconds)
        XCTAssertEqual(events.first(where: { $0.step == 17 })?.offset, 17 * stepNanoseconds)
    }

    /// Y la Division del Cycle 1 sí manda, porque es la que había al construir:
    /// la limitación es «no cambia», no «se ignora siempre».
    func testTheDivisionOfTheFirstCycleDoesSetTheGrid() {
        let events = turns(
            cycle(pitch: 48, division: .eighth),
            cycle(pitch: 72, division: .eighth)
        )

        XCTAssertEqual(events.first(where: { $0.step == 1 })?.offset, 2 * stepNanoseconds)
    }
}
