import Engine
import XCTest

@testable import MIDI

/// Tests del generador del pulso de clock.
///
/// El generador decide **cuándo** cae cada uno de los 24 pulsos por negra que la
/// app emite como maestro. Los dos fallos que arruinarían el track son los
/// mismos que vigila `LookAheadSchedulerTests` para los Steps —duplicar un tick
/// y omitirlo en el solape entre ventanas— con uno más que solo tiene el pulso:
/// **acumular deriva**, porque un tick dura 20,83 ms y no un número redondo de
/// nanosegundos, y un esclavo se separa con lo que se pierda por el camino.
final class ClockPulseSchedulerTests: XCTestCase {

    /// 120 BPM: la negra son 500 ms y el tick 500/24 ms.
    private func makeScheduler(beatsPerMinute: Double = 120) -> ClockPulseScheduler {
        ClockPulseScheduler(tempo: Tempo(beatsPerMinute: beatsPerMinute)!)
    }

    private let quarterNoteNanoseconds: Int64 = 500_000_000

    // MARK: - La rejilla del pulso

    /// 24 pulsos por negra: el tick 24 cae exactamente en la negra siguiente
    /// (FR1).
    func testTwentyFourTicksSpanExactlyOneQuarterNote() {
        let scheduler = makeScheduler()
        XCTAssertEqual(scheduler.nanosecondOffset(forTick: 24), quarterNoteNanoseconds)
    }

    func testFirstTickFallsAtTheOrigin() {
        let scheduler = makeScheduler()
        XCTAssertEqual(scheduler.nanosecondOffset(forTick: 0), 0)
    }

    /// A 120 BPM el tick dura 20 833 333,33 ns, y el offset se redondea al
    /// nanosegundo (FR2).
    func testTickDurationAtOneHundredTwentyBeatsPerMinute() {
        let scheduler = makeScheduler()
        XCTAssertEqual(scheduler.nanosecondOffset(forTick: 1), 20_833_333)
    }

    /// **La deriva es el fallo propio de este generador.** Multiplicar desde el
    /// origen mantiene el error acotado a un redondeo; acumular sumando la
    /// duración de tick separaría el pulso del maestro sin que ningún test de
    /// ventana lo notara.
    func testQuarterNotesNeverDriftOverALongRun() {
        let scheduler = makeScheduler()
        for quarter in 1...600 {
            XCTAssertEqual(
                scheduler.nanosecondOffset(forTick: 24 * quarter),
                Int64(quarter) * quarterNoteNanoseconds,
                "la negra \(quarter) se separó de la rejilla"
            )
        }
    }

    // MARK: - Ventana simple

    func testHorizonAtOriginYieldsNoTicks() {
        var scheduler = makeScheduler()
        XCTAssertTrue(scheduler.advance(toHorizon: 0).isEmpty)
    }

    /// El límite superior es exclusivo, igual que en `LookAheadScheduler`: un
    /// tick que caiga justo en el horizonte sale en la ventana siguiente y no
    /// dos veces.
    func testHorizonOfExactlyOneTickYieldsOnlyTickZero() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: 20_833_333), 0..<1)
    }

    func testHorizonOfOneQuarterNoteYieldsTwentyFourTicks() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)
    }

    /// Un horizonte que salta lejos entrega todos los intermedios, sin recorrer
    /// el hueco tick a tick dentro del hilo de tiempo real.
    func testLongJumpYieldsEveryTickInBetween() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: 10 * quarterNoteNanoseconds), 0..<240)
    }

    // MARK: - Solape entre ventanas

    /// Dos ventanas consecutivas entregan cada tick **exactamente una vez**
    /// (FR3): el segundo rango empieza donde acabó el primero.
    func testConsecutiveWindowsDeliverEachTickExactlyOnce() {
        var scheduler = makeScheduler()
        let first = scheduler.advance(toHorizon: 30_000_000)
        let second = scheduler.advance(toHorizon: quarterNoteNanoseconds)
        XCTAssertEqual(first, 0..<2)
        XCTAssertEqual(second, 2..<24)
    }

    func testRepeatedHorizonYieldsNothingTheSecondTime() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)
        XCTAssertTrue(scheduler.advance(toHorizon: quarterNoteNanoseconds).isEmpty)
    }

    func testHorizonGoingBackwardsYieldsNothing() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)
        XCTAssertTrue(scheduler.advance(toHorizon: 0).isEmpty)
    }

    /// Un horizonte negativo es el caso del presupuesto de adelanto de Delay:
    /// el origen de rejilla está por delante del arranque y todavía no hay nada
    /// que emitir.
    func testNegativeHorizonYieldsNothing() {
        var scheduler = makeScheduler()
        XCTAssertTrue(scheduler.advance(toHorizon: -5_000_000).isEmpty)
    }

    // MARK: - El tempo cambia mientras suena

    /// Reanclar conserva la marca de agua y el instante del tick aún no
    /// entregado: lo ya emitido salió sellado y no se reescribe (FR10).
    func testRebaseKeepsTheWatermarkAndTheAnchoredInstant() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)

        let anchored = scheduler.nanosecondOffset(forTick: 24)
        scheduler.rebase(to: Tempo(beatsPerMinute: 60)!)

        XCTAssertEqual(scheduler.nextTick, 24)
        XCTAssertEqual(scheduler.nanosecondOffset(forTick: 24), anchored)
    }

    /// A la mitad de tempo, los ticks siguientes se separan el doble — y no se
    /// recalcula el pasado.
    func testRebaseHalvesTheTempoForTheTicksAhead() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)
        scheduler.rebase(to: Tempo(beatsPerMinute: 60)!)

        let anchored = scheduler.nanosecondOffset(forTick: 24)
        XCTAssertEqual(
            scheduler.nanosecondOffset(forTick: 48) - anchored, 2 * quarterNoteNanoseconds)
    }

    /// Reanclar al mismo tempo no mueve nada, así que quien llama no tiene que
    /// acordarse de si ya reancló — el mismo contrato que
    /// `LookAheadScheduler.rebase`.
    func testRebaseToTheSameTempoMovesNothing() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: quarterNoteNanoseconds), 0..<24)

        let before = scheduler.nanosecondOffset(forTick: 30)
        scheduler.rebase(to: Tempo(beatsPerMinute: 120)!)
        XCTAssertEqual(scheduler.nanosecondOffset(forTick: 30), before)
    }

    /// Reanclado dos y tres veces seguidas, el error sigue acotado a un
    /// redondeo por ancla y no se acumula.
    func testRepeatedRebasesDoNotAccumulateDrift() {
        var scheduler = makeScheduler()
        var expected: Int64 = 0

        for tempo in [90.0, 140.0, 174.0] {
            let ticksBefore = scheduler.nextTick
            _ = scheduler.advance(toHorizon: scheduler.nanosecondOffset(forTick: ticksBefore + 24))
            scheduler.rebase(to: Tempo(beatsPerMinute: tempo)!)

            expected = scheduler.nanosecondOffset(forTick: scheduler.nextTick)
            let quarter = Int64((60.0 / tempo * 1_000_000_000.0).rounded())
            XCTAssertEqual(
                scheduler.nanosecondOffset(forTick: scheduler.nextTick + 24) - expected,
                quarter,
                "a \(tempo) BPM la negra dejó de medir lo que mide"
            )
        }
    }

    // MARK: - Tiempo real

    /// El generador es un valor trivial, como exige NFR1: se copia en el hilo
    /// del scheduler sin `retain`/`release`.
    func testSchedulerIsATrivialValue() {
        XCTAssertTrue(_isPOD(ClockPulseScheduler.self))
    }
}
