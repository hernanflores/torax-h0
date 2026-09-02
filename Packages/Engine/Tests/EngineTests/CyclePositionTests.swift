import XCTest

@testable import Engine

/// Ver la nota de `PatternTests`: `Pattern` a secas es ambiguo en un target de
/// test.
private typealias Pattern = Engine.Pattern

/// Tests de la deducción del Cycle en curso a partir del reloj.
///
/// **Lo que se comprueba es que la pantalla y el sonido no puedan discrepar.**
/// El cursor de reproducción vive en el hilo del scheduler y no se publica, así
/// que la pantalla lo deduce; si la deducción no coincidiera exactamente con el
/// avance del scheduler, se vería el Cycle equivocado justo cuando cambia, que
/// es el único momento en que alguien mira.
final class CyclePositionTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Step dura 125 ms a 120 BPM con Division 1/16; una vuelta de 16 Steps,
    /// dos segundos.
    private let stepNanoseconds: Int64 = 125_000_000
    private let turnNanoseconds: Int64 = 2_000_000_000

    private func cycle(steps: Int = 16, division: Division = .sixteenth) -> Cycle {
        Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!, division: division))
    }

    private func track(_ steps: [Int], division: Division = .sixteenth) -> Track {
        var track = Track(cycle(steps: steps[0], division: division))
            .withActiveCount(steps.count)
        for (index, count) in steps.enumerated() {
            track = track.replacing(cycle(steps: count, division: division), at: index)
        }
        return track
    }

    private func cycleInCourse(_ track: Track, at elapsed: Int64) -> Int {
        CyclePosition(elapsedNanoseconds: elapsed, track: track, tempo: tempo).cycle
    }

    // MARK: - El recorrido

    /// Con tres Cycles de la misma longitud, cada vuelta avanza uno y la cuarta
    /// vuelve al primero.
    func testItWalksOneCyclePerTurnAndWraps() {
        let track = track([16, 16, 16])

        XCTAssertEqual(cycleInCourse(track, at: 0), 0)
        XCTAssertEqual(cycleInCourse(track, at: turnNanoseconds - 1), 0)
        XCTAssertEqual(cycleInCourse(track, at: turnNanoseconds), 1)
        XCTAssertEqual(cycleInCourse(track, at: 2 * turnNanoseconds), 2)
        XCTAssertEqual(cycleInCourse(track, at: 3 * turnNanoseconds), 0, "no volvió al primero")
        XCTAssertEqual(cycleInCourse(track, at: 4 * turnNanoseconds), 1)
    }

    /// **Con un solo Cycle activo el resultado es siempre 0**, por mucho tiempo
    /// que pase: es la condición de no regresión (FR10) vista desde la pantalla.
    func testWithASingleActiveCycleItIsAlwaysTheFirst() {
        let track = track([16])

        for turn in 0..<100 {
            XCTAssertEqual(cycleInCourse(track, at: Int64(turn) * turnNanoseconds), 0)
        }
    }

    /// **Cycles de longitudes distintas duran distinto**, así que no se puede
    /// dividir el tiempo por una vuelta y ya: hay que sumar las vueltas de cada
    /// uno. Un Cycle de 8 Steps dura la mitad que uno de 16.
    func testCyclesOfDifferentLengthsLastDifferentAmountsOfTime() {
        // 16 Steps (2 s), luego 8 (1 s), luego 16 (2 s): la pasada dura 5 s.
        let track = track([16, 8, 16])

        XCTAssertEqual(cycleInCourse(track, at: 1_999_000_000), 0)
        XCTAssertEqual(cycleInCourse(track, at: 2_000_000_000), 1)
        XCTAssertEqual(cycleInCourse(track, at: 2_999_000_000), 1)
        XCTAssertEqual(cycleInCourse(track, at: 3_000_000_000), 2)
        XCTAssertEqual(cycleInCourse(track, at: 4_999_000_000), 2)
        XCTAssertEqual(cycleInCourse(track, at: 5_000_000_000), 0, "la pasada no midió 5 s")
    }

    /// Y la Division cambia la escala entera: con 1/8 cada Step dura el doble.
    func testTheDivisionOfTheFirstCycleSetsTheScale() {
        let track = track([16, 16], division: .eighth)

        XCTAssertEqual(cycleInCourse(track, at: 3_999_000_000), 0)
        XCTAssertEqual(cycleInCourse(track, at: 4_000_000_000), 1)
    }

    /// Después de una hora sigue siendo exacto: se recorre la pasada, no se
    /// acumula vuelta a vuelta, así que no hay deriva que crezca con el tiempo.
    func testItIsStillExactAfterAnHour() {
        let track = track([16, 16, 16])
        let hour: Int64 = 3_600_000_000_000
        // Una hora son 1800 vueltas de dos segundos; 1800 % 3 == 0.
        XCTAssertEqual(cycleInCourse(track, at: hour), 0)
        XCTAssertEqual(cycleInCourse(track, at: hour + turnNanoseconds), 1)
    }

    // MARK: - Los bordes

    /// Un tiempo negativo o nulo se resuelve al origen. Ocurre de verdad: el
    /// scheduler reserva un margen por delante para el Delay negativo, y ahí
    /// todavía no ha sonado nada.
    func testTimeBeforeTheOriginResolvesToTheFirstCycle() {
        let track = track([16, 16, 16])

        XCTAssertEqual(cycleInCourse(track, at: 0), 0)
        XCTAssertEqual(cycleInCourse(track, at: -1), 0)
        XCTAssertEqual(cycleInCourse(track, at: -1_000_000_000), 0)
    }

    /// La fracción de vuelta va en `[0, 1)` y se mueve dentro del Cycle en
    /// curso, no de la pasada.
    func testTheTurnFractionIsRelativeToTheCurrentCycle() {
        let track = track([16, 16])

        let quarterIn = CyclePosition(
            elapsedNanoseconds: turnNanoseconds + turnNanoseconds / 4,
            track: track, tempo: tempo)

        XCTAssertEqual(quarterIn.cycle, 1)
        XCTAssertEqual(quarterIn.turn, 0.25, accuracy: 0.0001)
    }

    // MARK: - Los dieciséis

    /// Los dieciséis Tracks a la vez, cada uno con su recorrido: es lo que la
    /// pantalla pide para dibujar sin preguntar dieciséis veces.
    func testEveryTrackGetsItsOwnPosition() {
        var pattern = Pattern()
        pattern = pattern.replacing(track([16, 16]), at: 0)
        pattern = pattern.replacing(track([8, 8]), at: 1)

        let positions = CyclePosition.forEachTrack(
            in: pattern, tempo: tempo, elapsedNanoseconds: turnNanoseconds)

        XCTAssertEqual(positions.count, Pattern.trackCount)
        XCTAssertEqual(positions[0].cycle, 1, "el de 16 Steps ya cerró su vuelta")
        XCTAssertEqual(positions[1].cycle, 0, "el de 8 Steps cerró dos y volvió")
        XCTAssertEqual(positions[2].cycle, 0, "un Track con un Cycle no se mueve")
    }
}
