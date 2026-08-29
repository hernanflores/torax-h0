import XCTest
@testable import Engine

/// Tests del recorrido ordenado de Divisions.
///
/// Division no es un entero libre: es una lista de valores musicales por la que
/// un knob avanza y retrocede. La Pre Spec la describe como «ajuste fino» del
/// valor rítmico del Step, con default 1/16.
final class DivisionSequenceTests: XCTestCase {

    // MARK: - La lista

    /// De más lenta a más rápida, que es el sentido en el que gira el knob.
    func testOrderedRunsFromSlowestToFastest() {
        XCTAssertEqual(
            Division.ordered.map(\.description),
            ["1/1", "1/2", "1/4", "1/8", "1/16", "1/32"]
        )
    }

    func testDefaultIsInTheList() {
        XCTAssertTrue(Division.ordered.contains(.sixteenth))
    }

    func testSlowestAndFastestAreTheEnds() {
        XCTAssertEqual(Division.slowest, Division.ordered.first)
        XCTAssertEqual(Division.fastest, Division.ordered.last)
        XCTAssertEqual(Division.fastest, .thirtySecond)
    }

    /// Cada valor de la lista dura la mitad que el anterior: es lo que hace que
    /// girar el knob se perciba como duplicar o dividir la velocidad.
    func testEachDivisionIsTwiceAsFastAsTheOneBefore() {
        let tempo = Tempo(beatsPerMinute: 120)!
        let durations = Division.ordered.map {
            MusicalTimeline(tempo: tempo, division: $0).stepDurationNanoseconds
        }
        for (slower, faster) in zip(durations, durations.dropFirst()) {
            XCTAssertEqual(faster, slower / 2, accuracy: 1)
        }
    }

    // MARK: - Recorrer

    func testAdvancingByZeroIsTheIdentity() {
        for division in Division.ordered {
            XCTAssertEqual(division.advanced(by: 0), division)
        }
    }

    func testAdvancingForwardMovesTowardsFaster() {
        XCTAssertEqual(Division.quarter.advanced(by: 1), .eighth)
        XCTAssertEqual(Division.quarter.advanced(by: 2), .sixteenth)
    }

    func testAdvancingBackwardsMovesTowardsSlower() {
        XCTAssertEqual(Division.sixteenth.advanced(by: -1), .eighth)
        XCTAssertEqual(Division.sixteenth.advanced(by: -2), .quarter)
    }

    // MARK: - Los extremos frenan, no envuelven

    /// **No envuelve a propósito.** Un knob que salta de 1/32 a 1/1 al pasarse
    /// convertiría un giro de ajuste fino en un cambio brutal de velocidad.
    func testAdvancingPastTheFastestStops() {
        XCTAssertEqual(Division.thirtySecond.advanced(by: 1), .thirtySecond)
        XCTAssertEqual(Division.thirtySecond.advanced(by: 99), .thirtySecond)
    }

    /// El knob llega a 1/32 desde 1/16, que era el tope hasta la rebanada 5.
    func testTheKnobReachesThirtySecondFromSixteenth() {
        XCTAssertEqual(Division.sixteenth.advanced(by: 1), .thirtySecond)
    }

    func testAdvancingPastTheSlowestStops() {
        XCTAssertEqual(Division.slowest?.advanced(by: -1), Division.slowest)
        XCTAssertEqual(Division.slowest?.advanced(by: -99), Division.slowest)
    }

    /// Un giro largo desde un extremo llega al otro y se queda ahí.
    func testALongTurnLandsOnTheEndAndStays() {
        XCTAssertEqual(Division.slowest?.advanced(by: 100), Division.fastest)
        XCTAssertEqual(Division.fastest?.advanced(by: -100), Division.slowest)
    }

    /// Una Division fuera de la lista —el tipo admite cualquier fracción
    /// positiva— no puede romper el recorrido.
    func testAdvancingFromAValueOutsideTheListIsSafe() {
        let unlisted = Division(numerator: 3, denominator: 7)!
        XCTAssertEqual(unlisted.advanced(by: 1), unlisted)
        XCTAssertEqual(unlisted.advanced(by: -1), unlisted)
    }
}
