import XCTest

@testable import Engine

/// Tests del compás: dónde cae el próximo límite.
///
/// **Cuatro negras es una decisión, no una lectura del modelo.** La app no tiene
/// concepto de compás ni de métrica —`MusicalTimeline` cuenta negras— así que
/// esto no deriva de nada: es lo que asume cualquier secuenciador de hardware y
/// lo que hace que un cambio de sección caiga donde el oído lo espera.
///
/// **No es el límite de vuelta de ningún Track.** Los doce tienen anillos de
/// longitudes distintas (Steps × Division) y esperar a que cierren todos no
/// converge. El compás es la única rejilla común.
final class BarGridTests: XCTestCase {

    private let bar = BarGrid(tempo: Tempo(beatsPerMinute: 120)!)

    /// A 120 BPM una negra dura 500 ms, así que un compás dura 2 s.
    func testABarIsFourBeats() {
        XCTAssertEqual(BarGrid.beatsPerBar, 4)
        XCTAssertEqual(bar.durationNanoseconds, 2_000_000_000)
    }

    /// El tempo manda: a 60 BPM el compás dura el doble.
    func testTheBarFollowsTheTempo() {
        XCTAssertEqual(
            BarGrid(tempo: Tempo(beatsPerMinute: 60)!).durationNanoseconds, 4_000_000_000)
        XCTAssertEqual(
            BarGrid(tempo: Tempo(beatsPerMinute: 240)!).durationNanoseconds, 1_000_000_000)
    }

    /// Desde el origen, el próximo límite es el final del primer compás.
    func testFromTheOriginTheNextBoundaryIsOneBarAway() {
        XCTAssertEqual(bar.nextBoundary(after: 0), 2_000_000_000)
    }

    /// A mitad de compás, el límite es el final de ése.
    func testInsideABarTheBoundaryIsItsEnd() {
        XCTAssertEqual(bar.nextBoundary(after: 500_000_000), 2_000_000_000)
        XCTAssertEqual(bar.nextBoundary(after: 1_999_999_999), 2_000_000_000)
    }

    /// Y en compases posteriores, el suyo.
    func testLaterBarsGetTheirOwnBoundary() {
        XCTAssertEqual(bar.nextBoundary(after: 2_000_000_001), 4_000_000_000)
        XCTAssertEqual(bar.nextBoundary(after: 9_000_000_000), 10_000_000_000)
    }

    /// **Estar exactamente encima del límite es el caso que se fija por test y
    /// no por intuición.**
    ///
    /// Se elige **el siguiente**, no ése. La razón es de tiempo real: el
    /// scheduler pregunta con la ventana de look-ahead ya sumada, así que un
    /// límite que cae justo en el instante consultado ya está comprometido —sus
    /// eventos se pidieron hace 20 ms—. Devolverlo produciría un cambio que llega
    /// tarde a su propio compás.
    func testExactlyOnTheBoundaryPicksTheNextOne() {
        XCTAssertEqual(bar.nextBoundary(after: 2_000_000_000), 4_000_000_000)
        XCTAssertEqual(bar.nextBoundary(after: 0), 2_000_000_000)
    }

    /// Un instante negativo —antes del origen, que es lo que Delay produce— cae
    /// en el primer límite y no revienta.
    func testBeforeTheOriginTheBoundaryIsTheFirstOne() {
        XCTAssertEqual(bar.nextBoundary(after: -1), 0)
        XCTAssertEqual(bar.nextBoundary(after: -5_000_000_000), 0)
    }

    /// Cuántos compases han pasado desde el origen. Es lo que la cuenta atrás de
    /// la pantalla necesita.
    func testItSaysHowFarTheNextBoundaryIs() {
        XCTAssertEqual(bar.remainingNanoseconds(at: 0), 2_000_000_000)
        XCTAssertEqual(bar.remainingNanoseconds(at: 1_500_000_000), 500_000_000)
        XCTAssertEqual(bar.remainingNanoseconds(at: 2_000_000_000), 2_000_000_000)
    }

    /// Lo que queda nunca es negativo ni mayor que un compás, en ningún instante.
    func testTheRemainderIsAlwaysInsideOneBar() {
        for nanoseconds in stride(from: Int64(0), to: Int64(10_000_000_000), by: 137_000_000) {
            let remaining = bar.remainingNanoseconds(at: nanoseconds)
            XCTAssertGreaterThan(remaining, 0, "\(nanoseconds)")
            XCTAssertLessThanOrEqual(remaining, bar.durationNanoseconds, "\(nanoseconds)")
        }
    }

    /// El límite siempre es múltiplo de la duración del compás: la rejilla no
    /// deriva.
    func testEveryBoundaryIsOnTheGrid() {
        for nanoseconds in stride(from: Int64(0), to: Int64(20_000_000_000), by: 311_000_000) {
            XCTAssertEqual(bar.nextBoundary(after: nanoseconds) % bar.durationNanoseconds, 0)
        }
    }
}
