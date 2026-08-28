import XCTest
@testable import Engine

/// Tests del nombre de una altura.
///
/// **Se muestra el pool, y un pool son alturas concretas, no clases.** Do3 y Do4
/// son dos notas distintas del pool y la pantalla tiene que poder
/// distinguirlas — si solo dijera «C», dos entradas del pool se verían iguales.
final class PitchNameTests: XCTestCase {

    /// Convención científica: Do central (MIDI 60) es C4.
    func testMiddleCIsC4() {
        XCTAssertEqual(Pitch(60)!.description, "C4")
    }

    func testTheOctaveChangesAtC() {
        XCTAssertEqual(Pitch(59)!.description, "B3")
        XCTAssertEqual(Pitch(60)!.description, "C4")
        XCTAssertEqual(Pitch(71)!.description, "B4")
        XCTAssertEqual(Pitch(72)!.description, "C5")
    }

    /// Sostenidos y no bemoles, igual que `Root`: un solo nombre por clase de
    /// altura, sin que dependa de la escala en curso.
    func testAccidentalsAreSharps() {
        XCTAssertEqual(Pitch(61)!.description, "C#4")
        XCTAssertEqual(Pitch(66)!.description, "F#4")
    }

    func testTheExtremesOfTheRangeHaveNames() {
        XCTAssertEqual(Pitch(0)!.description, "C-1")
        XCTAssertEqual(Pitch(127)!.description, "G9")
    }

    /// Ninguna altura se queda sin nombre, y no hay dos con el mismo.
    func testEveryPitchHasItsOwnName() {
        let names = Pitch.validRange.map { Pitch($0)!.description }
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// La clase de altura coincide con la letra: el nombre y `pitchClass` no
    /// pueden discrepar.
    func testTheNameAgreesWithThePitchClass() {
        for value in Pitch.validRange {
            let pitch = Pitch(value)!
            XCTAssertTrue(
                pitch.description.hasPrefix(Root(pitch.pitchClass)!.description),
                "altura \(value)"
            )
        }
    }
}
