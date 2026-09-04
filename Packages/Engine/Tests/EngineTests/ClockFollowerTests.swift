import XCTest

@testable import Engine

/// Tests del seguidor de reloj externo.
///
/// El estimador es la única pieza que decide a qué velocidad corre la app
/// cuando manda un maestro externo. Si aquí la aritmética falla, el look-ahead
/// sella la ventana entera con un periodo equivocado y no hay corrección de
/// fase que lo arregle: se oye como que la app se va de tempo.
final class ClockFollowerTests: XCTestCase {

    /// Intervalo entre ticks, en nanosegundos, para un tempo dado.
    ///
    /// Una negra son 24 ticks, así que el tick dura la veinticuatroava parte de
    /// lo que dura la negra.
    private func tickInterval(beatsPerMinute: Double) -> Double {
        60.0 / beatsPerMinute * 1_000_000_000.0 / Double(ClockFollower.ticksPerQuarterNote)
    }

    /// Alimenta `count` ticks equiespaciados y devuelve el instante del último.
    @discardableResult
    private func feed(
        _ follower: inout ClockFollower,
        ticks count: Int,
        beatsPerMinute: Double,
        from start: Int64 = 0
    ) -> Int64 {
        let interval = tickInterval(beatsPerMinute: beatsPerMinute)
        var instant = start
        for index in 1...count {
            instant = start + Int64((interval * Double(index)).rounded())
            _ = follower.receive(tickAtNanoseconds: instant)
        }
        return instant
    }

    // MARK: - Tempo establecido

    /// El caso de referencia: a 120 BPM la negra dura 500 ms y el tick 20,83 ms.
    func testTwentyFourEvenTicksEstablish120BPM() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        feed(&follower, ticks: 24, beatsPerMinute: 120)

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 0.01)
    }

    /// Los dos extremos del rango del tipo `Tempo`, que son los que revelan
    /// errores de redondeo en el periodo.
    func testExtremesOfTheValidRangeAreEstimatedWithinTolerance() {
        for beatsPerMinute in [20.0, 300.0] {
            var follower = ClockFollower()
            _ = follower.receive(tickAtNanoseconds: 0)
            feed(&follower, ticks: 24, beatsPerMinute: beatsPerMinute)

            XCTAssertEqual(
                follower.tempo?.beatsPerMinute ?? 0, beatsPerMinute, accuracy: 0.01,
                "El tempo estimado a \(beatsPerMinute) BPM se sale de la tolerancia")
        }
    }

    /// Antes de cerrar la primera negra no hay tempo: estimar con dos ticks
    /// sería creerse un intervalo suelto.
    func testNoTempoBeforeTheFirstQuarterNoteCloses() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        feed(&follower, ticks: 23, beatsPerMinute: 120)

        XCTAssertNil(follower.tempo)
    }

    // MARK: - La negra como unidad

    /// El seguidor avisa de que se cerró una negra exactamente cada 24 ticks:
    /// es el instante que la corrección de fase necesita.
    func testQuarterNoteIsReportedEveryTwentyFourTicks() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)

        let interval = tickInterval(beatsPerMinute: 120)
        var completions: [Int] = []
        for index in 1...48 {
            let instant = Int64((interval * Double(index)).rounded())
            if case .quarterNote = follower.receive(tickAtNanoseconds: instant) {
                completions.append(index)
            }
        }

        XCTAssertEqual(completions, [24, 48])
    }

    /// El instante que se reporta es el del tick que cierra la negra, no el
    /// momento en que alguien pregunte.
    func testQuarterNoteCarriesTheInstantOfTheClosingTick() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        let last = feed(&follower, ticks: 23, beatsPerMinute: 120)
        let closing = last + Int64(tickInterval(beatsPerMinute: 120).rounded())

        guard case .quarterNote(let instant) = follower.receive(tickAtNanoseconds: closing) else {
            return XCTFail("El tick 24 tenía que cerrar la negra")
        }
        XCTAssertEqual(instant, closing)
    }

    // MARK: - Un tick tardío aislado

    /// Un tick que llega tarde en mitad de la negra **no mueve el tempo**: lo
    /// que se promedia es la negra entera, no el intervalo suelto.
    func testALateTickInsideTheWindowDoesNotMoveTheTempo() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)

        let interval = tickInterval(beatsPerMinute: 120)
        for index in 1...24 {
            var instant = Int64((interval * Double(index)).rounded())
            if index == 12 { instant += 2_000_000 }  // 2 ms tarde, mucho para un cable
            _ = follower.receive(tickAtNanoseconds: instant)
        }

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 0.01)
    }

    /// Si el tardío es el que cierra la negra, el error se reparte entre los 24
    /// ticks: 2 ms de retraso mueven el tempo menos de 1 BPM.
    func testALateClosingTickIsDividedAcrossTheWindow() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)

        let interval = tickInterval(beatsPerMinute: 120)
        for index in 1...24 {
            var instant = Int64((interval * Double(index)).rounded())
            if index == 24 { instant += 2_000_000 }
            _ = follower.receive(tickAtNanoseconds: instant)
        }

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 1.0)
    }

    // MARK: - Fuera de rango

    /// Un maestro imposible no se acota en silencio: se rechaza y se dice.
    func testATempoOutOfRangeIsRejectedAndReported() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        feed(&follower, ticks: 24, beatsPerMinute: 600)

        XCTAssertNil(follower.tempo)
        XCTAssertTrue(follower.isOutOfRange)
    }

    /// Rechazar no destruye lo que ya se sabía: se conserva el último válido.
    func testARejectedTempoKeepsTheLastValidOne() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        let last = feed(&follower, ticks: 24, beatsPerMinute: 120)
        feed(&follower, ticks: 24, beatsPerMinute: 600, from: last)

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 0.01)
        XCTAssertTrue(follower.isOutOfRange)
    }

    /// Y volver al rango limpia la marca: el estado describe la negra vigente,
    /// no la historia.
    func testComingBackIntoRangeClearsTheMark() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        var last = feed(&follower, ticks: 24, beatsPerMinute: 600)
        last = feed(&follower, ticks: 24, beatsPerMinute: 90, from: last)

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 90, accuracy: 0.01)
        XCTAssertFalse(follower.isOutOfRange)
    }

    // MARK: - Cambio sostenido de tempo

    /// Un cambio real se alcanza al cerrar la negra siguiente, **y no antes**:
    /// la latencia es una propiedad declarada, no un accidente.
    func testASustainedTempoChangeLandsOnTheNextQuarterNote() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        var last = feed(&follower, ticks: 24, beatsPerMinute: 120)

        // Media negra al tempo nuevo: todavía manda el viejo.
        last = feed(&follower, ticks: 12, beatsPerMinute: 90, from: last)
        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 0.01)

        // La otra media cierra la negra y el tempo nuevo entra entero.
        feed(&follower, ticks: 12, beatsPerMinute: 90, from: last)
        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 90, accuracy: 0.01)
    }

    // MARK: - Reset y tiempo no creciente

    /// Arrancar el transporte olvida al maestro anterior: su tempo no dice nada
    /// del siguiente, y el ancla vieja daría una negra absurda.
    func testResetForgetsWhatWasLearned() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        feed(&follower, ticks: 24, beatsPerMinute: 120)
        XCTAssertNotNil(follower.tempo)

        follower.reset()

        XCTAssertNil(follower.tempo)
        XCTAssertFalse(follower.isOutOfRange)
        XCTAssertEqual(follower, ClockFollower())
    }

    /// Dos ticks en el mismo instante no dan un tempo infinito: se rechazan como
    /// cualquier otro valor imposible.
    func testANonAdvancingClockIsRejected() {
        var follower = ClockFollower()
        for _ in 0...ClockFollower.ticksPerQuarterNote {
            _ = follower.receive(tickAtNanoseconds: 0)
        }

        XCTAssertNil(follower.tempo)
        XCTAssertTrue(follower.isOutOfRange)
    }

    // MARK: - Re-anclar tras un corte

    /// Volver a anclar conserva el tempo: es el que sigue sonando mientras no
    /// haya otro mejor.
    func testReanchoringKeepsTheTempo() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        feed(&follower, ticks: 24, beatsPerMinute: 120)

        follower.reanchor()

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 120, accuracy: 0.01)
    }

    /// Y **el hueco no se mide**: tras re-anclar, la negra siguiente se cuenta
    /// desde el primer tick que vuelve, no desde el último de antes del corte.
    func testTheGapIsNotMeasuredAfterReanchoring() {
        var follower = ClockFollower()
        _ = follower.receive(tickAtNanoseconds: 0)
        let last = feed(&follower, ticks: 24, beatsPerMinute: 120)

        follower.reanchor()
        let afterGap = last + 2_000_000_000
        _ = follower.receive(tickAtNanoseconds: afterGap)
        feed(&follower, ticks: 24, beatsPerMinute: 90, from: afterGap)

        XCTAssertEqual(follower.tempo?.beatsPerMinute ?? 0, 90, accuracy: 0.01)
    }

    // MARK: - Reglas de tiempo real

    /// Lo alimenta el callback de recepción de CoreMIDI, así que no puede
    /// llevar nada que asigne. Misma red que vigila el snapshot.
    func testTheFollowerIsATrivialType() {
        XCTAssertTrue(_isPOD(ClockFollower.self))
    }
}
