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

    // MARK: - El nombre de una escala

    // **Bajó aquí el 2026-09-06, en la Fase 2 de screens-redesign.** El nombre
    // de cada Scale se escribía en dos sitios de `App` —`FamilyReadout` lo tenía
    // privado y `TonalView` tenía el suyo— y el card tonal habría sido el
    // tercero. Es texto de dominio, y `workflow.md` manda que eso no viva donde
    // no hay tests.

    func testEveryScaleHasAName() {
        for scale in Scale.allCases {
            XCTAssertFalse("\(scale)".isEmpty, "\(scale)")
        }
    }

    func testScaleNamesAreTheVocabularyOfThePreSpec() {
        XCTAssertEqual("\(Scale.minor)", "Minor")
        XCTAssertEqual("\(Scale.major)", "Major")
        XCTAssertEqual("\(Scale.dorian)", "Dorian")
        XCTAssertEqual("\(Scale.phrygian)", "Phrygian")
        XCTAssertEqual("\(Scale.pentatonic)", "Pentatonic")
    }

    func testScaleNamesAreAllDistinct() {
        let names = Set(Scale.allCases.map { "\($0)" })
        XCTAssertEqual(names.count, Scale.allCases.count)
    }

    // MARK: - Las tres escalas nuevas

    // **Añadidas el 2026-09-06, en la Fase 3 de screens-redesign.** El brief de
    // iPadOS dibuja seis escalas y `Engine` tenía cinco: coincidían cuatro,
    // faltaban Mixolydian y Lydian, y sobraba Pentatonic. Se añaden las dos que
    // faltaban, se conserva Pentatonic —funciona, tiene tests y es el único caso
    // que ejercita el hueco de los pads— y el usuario pide además Hirajoshi.

    func testTheNewScalesExist() {
        XCTAssertTrue(Scale.allCases.contains(.mixolydian))
        XCTAssertTrue(Scale.allCases.contains(.lydian))
        XCTAssertTrue(Scale.allCases.contains(.hirajoshi))
    }

    func testMixolydianIsMajorWithAFlatSeventh() {
        // Es la única diferencia con Major, y es la que le da su carácter.
        XCTAssertEqual(degrees(of: .mixolydian), [0, 2, 4, 5, 7, 9, 10])
        XCTAssertEqual(degrees(of: .major), [0, 2, 4, 5, 7, 9, 11])
    }

    func testLydianIsMajorWithASharpFourth() {
        XCTAssertEqual(degrees(of: .lydian), [0, 2, 4, 6, 7, 9, 11])
    }

    func testHirajoshiHasFiveDegrees() {
        // Pentatónica japonesa, en la forma que catalogan los secuenciadores:
        // 0-2-3-7-8. Como Pentatonic, deja pads sin altura, y eso está previsto.
        XCTAssertEqual(degrees(of: .hirajoshi), [0, 2, 3, 7, 8])
    }

    func testEveryScaleStartsOnItsRoot() {
        for scale in Scale.allCases {
            XCTAssertEqual(degrees(of: scale).first, 0, "\(scale)")
        }
    }

    func testOrderedListsEveryScaleOnce() {
        XCTAssertEqual(Scale.ordered.count, Scale.allCases.count)
        XCTAssertEqual(Set(Scale.ordered).count, Scale.allCases.count)
    }

    func testOrderedKeepsTheReadingOrderOfTheHandoff() {
        // Las seis del brief primero y en su orden, para que la rejilla de la
        // pantalla `scale` coincida con el PNG. Las dos pentatónicas cierran.
        XCTAssertEqual(
            Scale.ordered,
            [.minor, .major, .dorian, .mixolydian, .phrygian, .lydian, .pentatonic, .hirajoshi])
    }

    func testTheNewScalesHaveNames() {
        XCTAssertEqual(Scale.mixolydian.name, "Mixolydian")
        XCTAssertEqual(Scale.lydian.name, "Lydian")
        XCTAssertEqual(Scale.hirajoshi.name, "Hirajoshi")
    }

    /// Los semitonos de una escala, leídos de su máscara.
    private func degrees(of scale: Scale) -> [Int] {
        (0..<12).filter { scale.pitchClassMask & (1 << UInt16($0)) != 0 }
    }
}
