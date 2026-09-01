import Engine
import XCTest
@testable import MIDI

/// Tests del ancla temporal del playhead.
///
/// **Es el camino de vuelta que faltaba.** `PatternHandoff` lleva el estado del
/// hilo de control al del scheduler; esto lleva el tiempo del scheduler a la
/// interfaz. La regla es la misma en ambas direcciones: el hilo del scheduler no
/// se bloquea, y quien lea tarde o no lea no puede afectarle.
final class PlayheadClockTests: XCTestCase {

    // MARK: - Parado

    func testAStoppedClockHasNoElapsedTime() {
        XCTAssertNil(PlayheadClock().elapsedNanoseconds(now: 1_000_000))
    }

    /// **Parado significa quieto.** Si el reloj siguiera contando con el
    /// transporte detenido, el playhead se movería sin que sonara nada — que es
    /// exactamente la animación no derivada del reloj musical que
    /// `product-guidelines.md` marca como antipatrón.
    func testStoppingFreezesTheClock() {
        let clock = PlayheadClock()
        clock.start(atHostTime: 100)
        XCTAssertNotNil(clock.elapsedNanoseconds(now: 200))

        clock.stop()
        XCTAssertNil(clock.elapsedNanoseconds(now: 300))
        XCTAssertNil(clock.elapsedNanoseconds(now: 400))
    }

    // MARK: - Corriendo

    func testElapsedTimeIsMeasuredFromTheOrigin() {
        let clock = PlayheadClock()
        let origin = HostClock.now()
        clock.start(atHostTime: origin)

        let oneSecond = HostClock.hostTicks(fromNanoseconds: 1_000_000_000)
        let elapsed = clock.elapsedNanoseconds(now: origin &+ oneSecond)

        XCTAssertNotNil(elapsed)
        XCTAssertEqual(Double(elapsed!), 1_000_000_000, accuracy: 1_000)
    }

    func testAtTheOriginNoTimeHasElapsed() {
        let clock = PlayheadClock()
        clock.start(atHostTime: 500)
        XCTAssertEqual(clock.elapsedNanoseconds(now: 500), 0)
    }

    /// Volver a arrancar toma un origen nuevo: el segundo Play empieza el anillo
    /// desde el principio, no a mitad de vuelta.
    func testRestartingTakesAFreshOrigin() {
        let clock = PlayheadClock()
        clock.start(atHostTime: 100)
        clock.start(atHostTime: 900)
        XCTAssertEqual(clock.elapsedNanoseconds(now: 900), 0)
    }

    /// Un `now` anterior al origen no puede ocurrir con un reloj monótono, pero
    /// si ocurriera no se devuelve un tiempo negativo envuelto en un número
    /// enorme.
    func testATimeBeforeTheOriginReadsAsZero() {
        let clock = PlayheadClock()
        clock.start(atHostTime: 1_000)
        XCTAssertEqual(clock.elapsedNanoseconds(now: 500), 0)
    }

}
