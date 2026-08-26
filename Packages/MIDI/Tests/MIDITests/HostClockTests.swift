import XCTest
@testable import MIDI

/// Tests de la conversión entre nanosegundos y tiempo de host.
///
/// CoreMIDI sella los eventos con tiempo de host (`mach_absolute_time`), cuya
/// unidad NO es el nanosegundo en todas las máquinas: en Apple Silicon la
/// relación es 1:1, pero en Intel no. Dar por hecha esa equivalencia es un fallo
/// clásico que produce un tempo erróneo en unos dispositivos y correcto en
/// otros, así que la conversión es explícita y va con tests.
final class HostClockTests: XCTestCase {

    func testNanosecondsRoundTripThroughHostTicks() {
        for nanoseconds in [0, 1_000, 125_000_000, 10_000_000_000] as [UInt64] {
            let ticks = HostClock.hostTicks(fromNanoseconds: nanoseconds)
            let recovered = HostClock.nanoseconds(fromHostTicks: ticks)
            XCTAssertEqual(Double(recovered), Double(nanoseconds), accuracy: 1,
                           "Round-trip perdió precisión en \(nanoseconds) ns")
        }
    }

    func testZeroMapsToZero() {
        XCTAssertEqual(HostClock.hostTicks(fromNanoseconds: 0), 0)
        XCTAssertEqual(HostClock.nanoseconds(fromHostTicks: 0), 0)
    }

    func testConversionIsMonotonic() {
        XCTAssertLessThan(
            HostClock.hostTicks(fromNanoseconds: 1_000_000),
            HostClock.hostTicks(fromNanoseconds: 2_000_000)
        )
    }

    func testNowAdvances() {
        let first = HostClock.now()
        var spin = 0
        // Espera activa breve: evita depender de sleep en un test de reloj.
        while HostClock.now() == first && spin < 1_000_000 { spin += 1 }
        XCTAssertGreaterThan(HostClock.now(), first)
    }

    /// Una duración musical convertida a ticks y de vuelta debe conservar el
    /// valor: es la conversión que usará el scheduler en cada ventana.
    func testMusicalDurationSurvivesConversion() {
        let stepNanoseconds: UInt64 = 125_000_000
        let ticks = HostClock.hostTicks(fromNanoseconds: stepNanoseconds)
        XCTAssertEqual(Double(HostClock.nanoseconds(fromHostTicks: ticks)),
                       Double(stepNanoseconds), accuracy: 1)
    }
}
