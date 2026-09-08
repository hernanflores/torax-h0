import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de la modulación en el camino de emisión (FR4, FR8).
///
/// **La fase sale de `cycleStep`, el índice dentro de la vuelta**, no del Step
/// absoluto de la línea de tiempo. Es lo que hace que el ciclo de modulación
/// dure exactamente una vuelta del anillo y que dos vueltas seguidas emitan la
/// misma serie de velocities.
///
/// **El LFO corre sobre los Steps, suenen o no.** Un Step que Probability apaga,
/// o que no es pulso euclidiano, consume igualmente su posición del ciclo: la
/// fase depende del índice y nunca de si hubo nota. Lo contrario ataría la fase
/// a una tirada aleatoria y «un ciclo por vuelta» dejaría de ser cierto.
///
/// **Con `accent = 0` la secuencia emitida es idéntica a la de antes de la
/// rebanada** — instantes, velocities y consumo de aleatoriedad. Es el criterio
/// 1, y se queda dentro de la suite.
final class ModulationInSchedulerTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000
    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private func pool() -> PitchPool {
        var pool = PitchPool()
        for value in [60, 64, 67] { pool = pool.toggling(Pitch(value)!) }
        return pool
    }

    private func cycle(
        steps: Int = 16,
        pulses: Int = 16,
        velocity: Int = 100,
        probability: Int = 100,
        waveform: Waveform = .triangle,
        accent: Int = 0
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!),
            pool: pool(),
            groove: Groove(
                velocity: Velocity(velocity)!,
                sustain: .default,
                probability: Probability(percent: probability)!
            ),
            modulation: Modulation(waveform: waveform, accent: Accent(percent: accent)!)
        )
    }

    /// Lo que se emitió durante `rounds` vueltas: el Step, y la velocity con la
    /// que salió.
    private func emitted(
        _ cycle: Cycle,
        rounds: Int = 1,
        steps: Int = 16,
        seed: UInt64 = SeededRandom.defaultSeed
    ) -> [(step: Int, velocity: Int)] {
        var scheduler = TrackScheduler(timeline: timeline, material: .cycle(cycle), seed: seed)
        var result: [(Int, Int)] = []
        scheduler.advance(
            toHorizon: Int64(steps * rounds) * stepNanoseconds,
            refreshingFrom: nil
        ) { _, step, _, groove, _ in result.append((step, groove.velocity.value)) }
        return result
    }

    private func velocities(_ cycle: Cycle, rounds: Int = 1, steps: Int = 16) -> [Int] {
        emitted(cycle, rounds: rounds, steps: steps).map(\.velocity)
    }

    // MARK: - El criterio 1: con accent 0 nada cambia

    /// Con `accent = 0` todos los Steps salen a la Velocity del Cycle, para las
    /// cuatro formas. Es la no regresión de la rebanada.
    func testWithoutAccentEveryStepKeepsTheCycleVelocity() {
        for waveform in Waveform.allCases {
            XCTAssertEqual(
                velocities(cycle(waveform: waveform, accent: 0)),
                Array(repeating: 100, count: 16),
                "\(waveform)"
            )
        }
    }

    /// **Ni los instantes ni el consumo de aleatoriedad cambian.** Un Cycle sin
    /// modulación emite exactamente lo mismo que el mismo Cycle construido sin
    /// tocar el campo — que es como lo construye todo el código anterior a la
    /// rebanada.
    func testWithoutAccentTheWholeSequenceIsIdenticalToTheOneBefore() {
        let before = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: pool(),
            groove: Groove(
                velocity: Velocity(100)!,
                sustain: .default,
                probability: Probability(percent: 50)!
            )
        )
        let after = before.with(modulation: Modulation(waveform: .saw, accent: Accent(percent: 0)!))

        let a = emitted(before, rounds: 4)
        let b = emitted(after, rounds: 4)

        XCTAssertEqual(a.map(\.step), b.map(\.step))
        XCTAssertEqual(a.map(\.velocity), b.map(\.velocity))
    }

    // MARK: - La forma se oye

    /// Con `triangle` y `accent = +100`, la velocity sigue la onda: sube al
    /// cuarto de vuelta, vuelve a la base a media vuelta y baja simétricamente
    /// (criterio 3). Con base 100 la primera mitad recorta contra 127.
    func testTriangleWithFullAccentFollowsTheShape() {
        XCTAssertEqual(
            velocities(cycle(waveform: .triangle, accent: 100)),
            [100, 115, 127, 127, 127, 127, 127, 115, 100, 85, 69, 53, 37, 53, 69, 85]
        )
    }

    /// Desde el centro del rango la onda se ve entera, sin recorte.
    func testFromTheCentreTheWholeWaveIsAudible() {
        XCTAssertEqual(
            velocities(cycle(velocity: 64, waveform: .triangle, accent: 100)),
            [64, 79, 95, 111, 127, 111, 95, 79, 64, 49, 33, 17, 1, 17, 33, 49]
        )
    }

    /// **El Step 0 de cada vuelta vuelve a la base** (criterio 6): es lo que
    /// significa que la fase salga del índice dentro de la vuelta.
    func testTheFirstStepOfEveryTurnIsBackAtTheBaseVelocity() {
        let sequence = emitted(cycle(velocity: 64, waveform: .sine, accent: 100), rounds: 4)
        for turn in 0..<4 {
            XCTAssertEqual(sequence[turn * 16].velocity, 64, "vuelta \(turn)")
        }
    }

    /// **La fase usa `cycleStep`, no el Step absoluto**: dos vueltas seguidas
    /// emiten la misma serie de velocities.
    func testTwoConsecutiveTurnsEmitTheSameSeries() {
        let sequence = velocities(cycle(velocity: 64, waveform: .saw, accent: 80), rounds: 2)
        XCTAssertEqual(Array(sequence[0..<16]), Array(sequence[16..<32]))
    }

    /// `pulse` acentúa media vuelta entera y deja la otra media por debajo
    /// (criterio 7): exactamente dos valores.
    func testPulseAccentsHalfTheTurn() {
        let sequence = velocities(cycle(velocity: 64, waveform: .pulse, accent: 100))
        XCTAssertEqual(Set(sequence).count, 2)
        XCTAssertEqual(Array(sequence[0..<8]), Array(repeating: 127, count: 8))
        XCTAssertEqual(Array(sequence[8..<16]), Array(repeating: 1, count: 8))
    }

    /// `accent` negativo es el complemento del positivo respecto de la base,
    /// donde el acotado no muerde (criterio 4).
    func testNegativeAccentIsTheMirrorOfPositive() {
        let up = velocities(cycle(velocity: 64, waveform: .triangle, accent: 60))
        let down = velocities(cycle(velocity: 64, waveform: .triangle, accent: -60))
        for step in 0..<16 {
            XCTAssertEqual(up[step] - 64, 64 - down[step], "step \(step)")
        }
    }

    // MARK: - La fase no depende de si sonó

    /// **Un Step apagado por Probability no desplaza la fase** (FR8, criterio
    /// 8): los que sí suenan valen lo mismo que si hubiera sonado todo.
    func testAStepSilencedByProbabilityDoesNotShiftThePhase() {
        let all = emitted(cycle(velocity: 64, waveform: .triangle, accent: 100), rounds: 2)
        let some = emitted(
            cycle(velocity: 64, probability: 50, waveform: .triangle, accent: 100), rounds: 2)

        XCTAssertFalse(some.isEmpty)
        XCTAssertLessThan(some.count, all.count, "Probability 50 tenía que callar algo")

        let reference = Dictionary(uniqueKeysWithValues: all.map { ($0.step, $0.velocity) })
        for event in some {
            XCTAssertEqual(event.velocity, reference[event.step], "step \(event.step)")
        }
    }

    /// **Un Step que no es pulso euclidiano tampoco la desplaza.** Con 5 Pulses
    /// sobre 16 Steps solo suenan cinco posiciones, y cada una vale lo que
    /// valdría si sonaran las dieciséis.
    func testANonPulseStepDoesNotShiftThePhaseEither() {
        let dense = emitted(cycle(velocity: 64, waveform: .sine, accent: 100))
        let sparse = emitted(cycle(pulses: 5, velocity: 64, waveform: .sine, accent: 100))

        XCTAssertEqual(sparse.count, 5)
        let reference = Dictionary(uniqueKeysWithValues: dense.map { ($0.step, $0.velocity) })
        for event in sparse {
            XCTAssertEqual(event.velocity, reference[event.step], "step \(event.step)")
        }
    }

    // MARK: - El límite de vuelta

    /// **Al avanzar de Cycle, la modulación que se aplica es la del Cycle nuevo,
    /// desde su Step 0.** Un desarrollo A/B donde solo el B acentúa tiene que
    /// sonar plano la primera vuelta y con forma la segunda — que es la razón por
    /// la que la `Modulation` vive en el `Cycle` y no en el `Track`.
    func testTheNewCycleBringsItsOwnModulationFromItsFirstStep() {
        let flat = cycle(velocity: 64, accent: 0)
        let accented = cycle(velocity: 64, waveform: .triangle, accent: 100)

        var track = Track(flat).withActiveCount(2)
        track = track.replacing(flat, at: 0).replacing(accented, at: 1)
        let pattern = Pattern().replacing(track, at: 0)

        let scheduler = PatternScheduler(
            tempo: Tempo(beatsPerMinute: 120)!, pattern: pattern)
        var byStep: [Int: Int] = [:]
        scheduler.advance(
            toHorizon: 32 * stepNanoseconds,
            refreshingFrom: nil
        ) { trackIndex, _, step, _, groove, _ in
            guard trackIndex == 0 else { return }
            byStep[step] = groove.velocity.value
        }

        // Primera vuelta: el Cycle A no modula.
        for step in 0..<16 {
            XCTAssertEqual(byStep[step], 64, "vuelta A, step \(step)")
        }
        // Segunda vuelta: el B modula, y desde su propio Step 0.
        XCTAssertEqual(byStep[16], 64, "el Cycle nuevo no arrancó en su Step 0")
        XCTAssertEqual(byStep[20], 127, "el pico del Cycle nuevo no cayó en su cuarto de vuelta")
        XCTAssertEqual(byStep[28], 1, "el valle del Cycle nuevo no cayó en sus tres cuartos")
    }

    // MARK: - Cada Track con su anillo

    /// **Dos Cycles con Steps distintos completan su ciclo en vueltas
    /// distintas** (FR4): la modulación va atada al material del Track, no a un
    /// reloj común. Con 8 Steps el pico cae en el Step 2; con 16, en el 4.
    func testEachRingCompletesItsCycleAtItsOwnLength() {
        let short = velocities(cycle(steps: 8, pulses: 8, velocity: 64, accent: 100), steps: 8)
        let long = velocities(cycle(velocity: 64, accent: 100))

        XCTAssertEqual(short.count, 8)
        XCTAssertEqual(long.count, 16)
        XCTAssertEqual(short.firstIndex(of: short.max()!), 2)
        XCTAssertEqual(long.firstIndex(of: long.max()!), 4)
        // Y las dos vuelven a la base en su Step 0.
        XCTAssertEqual(short[0], 64)
        XCTAssertEqual(long[0], 64)
    }

    /// Un anillo de 9 Steps modula sobre nueve posiciones, no sobre dieciséis.
    func testANineStepRingModulatesOverNinePositions() {
        let sequence = velocities(
            cycle(steps: 9, pulses: 9, velocity: 64, accent: 100), rounds: 2, steps: 9)
        XCTAssertEqual(sequence.count, 18)
        XCTAssertEqual(Array(sequence[0..<9]), Array(sequence[9..<18]))
        XCTAssertEqual(sequence[0], 64)
    }

    // MARK: - Doce a la vez

    /// **Dos Tracks con Steps distintos sonando juntos completan su ciclo en
    /// vueltas distintas** (FR4), cada uno con el suyo. El LFO está atado al
    /// material del Track y no a un reloj común, así que el desfase entre los dos
    /// es la función y no un defecto.
    func testTwoTracksOfDifferentLengthsModulateAtTheirOwnRate() {
        let long = cycle(velocity: 64, accent: 100)
        let short = cycle(steps: 8, pulses: 8, velocity: 64, accent: 100)
        let pattern = Pattern()
            .replacing(Track(long), at: 0)
            .replacing(Track(short), at: 1)

        let byTrack = run(pattern, upToStep: 16)

        // El de dieciséis recorre su onda una vez: pico en el 4, valle en el 12.
        XCTAssertEqual(byTrack[0]?[4], 127)
        XCTAssertEqual(byTrack[0]?[12], 1)
        XCTAssertEqual(byTrack[0]?[0], 64)
        // El de ocho la recorre dos veces en el mismo tiempo: dos picos y dos
        // valles, y vuelve a la base en el 0 y en el 8.
        XCTAssertEqual(byTrack[1]?[2], 127)
        XCTAssertEqual(byTrack[1]?[6], 1)
        XCTAssertEqual(byTrack[1]?[10], 127)
        XCTAssertEqual(byTrack[1]?[14], 1)
        XCTAssertEqual(byTrack[1]?[0], 64)
        XCTAssertEqual(byTrack[1]?[8], 64)
    }

    /// **Un Track muteado sigue avanzando su fase.** La rejilla del muteado
    /// corre —es un mute de mixer y no un stop— y la modulación va con ella: al
    /// quitar el mute cae en la misma velocity que el vecino que nunca calló.
    func testAMutedTrackKeepsAdvancingItsPhase() {
        let modulated = cycle(velocity: 64, accent: 100)
        let pattern = Pattern()
            .replacing(Track(modulated), at: 0)
            .replacing(Track(modulated), at: 1)

        let mutes = MuteMask()
        var scheduler = PatternScheduler(tempo: tempo, pattern: pattern, mutes: mutes)

        mutes.toggleMute(0)
        _ = collect(&scheduler, upToStep: 8)
        mutes.toggleMute(0)

        let byTrack = collect(&scheduler, upToStep: 16)

        // Vuelve por donde iba, no por el principio: los Steps 8–15 del muteado
        // valen lo mismo que los del vecino.
        XCTAssertEqual(byTrack[0], byTrack[1])
        XCTAssertFalse(byTrack[0]?.isEmpty ?? true, "el Track no volvió a sonar")
        XCTAssertEqual(byTrack[0]?[12], 1, "la fase del muteado no había avanzado")
    }

    // MARK: - Ayuda para el Pattern entero

    private func run(_ pattern: Pattern, upToStep stepIndex: Int) -> [Int: [Int: Int]] {
        var scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        return collect(&scheduler, upToStep: stepIndex)
    }

    /// Por Track, la velocity con la que salió cada Step.
    private func collect(
        _ scheduler: inout PatternScheduler, upToStep stepIndex: Int
    ) -> [Int: [Int: Int]] {
        var byTrack: [Int: [Int: Int]] = [:]
        scheduler.advance(
            toHorizon: Int64(stepIndex) * stepNanoseconds,
            refreshingFrom: nil
        ) { track, _, step, _, groove, _ in
            byTrack[track, default: [:]][step] = groove.velocity.value
        }
        return byTrack
    }
}
