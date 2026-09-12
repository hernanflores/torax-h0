import XCTest
@testable import Engine

/// Tests de la cuenta en grados del marco tonal: la unidad en la que Pitch
/// transpone y Harmony mueve (`pitch-harmony_20260912`, FR2).
///
/// **El grado cuenta posiciones de la escala a través de las octavas.** En Do
/// mayor, subir uno desde B3 da C4: no hay octava que cruzar a mano, porque la
/// cuenta ya la cruza. El número absoluto de un grado no significa nada fuera
/// del marco; lo que importa es que sumar uno sea siempre la siguiente altura
/// permitida.
final class TonalFrameDegreeTests: XCTestCase {

    private let cMajor = TonalFrame(scale: .major, root: .c)

    // MARK: - Vecinos

    /// El ejemplo del PRD: B3, C4, D4 son grados consecutivos en Do mayor.
    func testConsecutiveDegreesCrossTheOctave() throws {
        let b3 = try XCTUnwrap(cMajor.degree(of: Pitch(59)!))
        XCTAssertEqual(cMajor.pitch(atDegree: b3 + 1), Pitch(60))
        XCTAssertEqual(cMajor.pitch(atDegree: b3 + 2), Pitch(62))
    }

    /// C4 E4 G4 un grado arriba son D4 F4 A4, y uno abajo B3 D4 F4 (AC 1).
    func testOneDegreeUpAndDownFromATriad() throws {
        let triad = [60, 64, 67].map { Pitch($0)! }
        let degrees = try triad.map { try XCTUnwrap(cMajor.degree(of: $0)) }

        XCTAssertEqual(degrees.map { cMajor.pitch(atDegree: $0 + 1)?.value }, [62, 65, 69])
        XCTAssertEqual(degrees.map { cMajor.pitch(atDegree: $0 - 1)?.value }, [59, 62, 65])
    }

    /// Siete grados son una octava en una escala de siete notas.
    func testSevenDegreesAreAnOctaveInAHeptatonicScale() throws {
        let c4 = try XCTUnwrap(cMajor.degree(of: Pitch(60)!))
        XCTAssertEqual(cMajor.pitch(atDegree: c4 + 7), Pitch(72))
    }

    /// Cinco grados son una octava en las pentatónicas.
    func testFiveDegreesAreAnOctaveInPentatonicScales() throws {
        for scale in [Scale.pentatonic, .hirajoshi] {
            let frame = TonalFrame(scale: scale, root: Root(2)!)
            let d4 = try XCTUnwrap(frame.degree(of: Pitch(62)!))
            XCTAssertEqual(frame.pitch(atDegree: d4 + 5), Pitch(74), "\(scale)")
        }
    }

    // MARK: - Pertenencia y bordes

    /// Una altura fuera del marco no tiene grado.
    func testAPitchOutsideTheFrameHasNoDegree() {
        XCTAssertNil(cMajor.degree(of: Pitch(61)!))
    }

    /// Un grado cuya altura cae fuera de 0–127 no tiene altura.
    func testADegreeOutsideTheMIDIRangeHasNoPitch() throws {
        let top = try XCTUnwrap(cMajor.degree(of: Pitch(127)!))  // G9
        XCTAssertNil(cMajor.pitch(atDegree: top + 1))

        let bottom = try XCTUnwrap(cMajor.degree(of: Pitch(0)!))  // C-1
        XCTAssertNil(cMajor.pitch(atDegree: bottom - 1))
    }

    /// El grado entero mas bajo cae fuera de MIDI sin desbordar la resta.
    func testTheLowestDegreeHasNoPitch() {
        XCTAssertNil(cMajor.pitch(atDegree: Int.min))
    }

    /// **Con Root distinto de Do, las alturas graves bajo el Root siguen
    /// contando.** En Re mayor, C#-1 (1) pertenece a la octava anterior a la del
    /// primer Re y es el grado justo debajo de D-1 (2).
    func testPitchesBelowTheFirstRootStillCount() throws {
        let dMajor = TonalFrame(scale: .major, root: Root(2)!)
        let d = try XCTUnwrap(dMajor.degree(of: Pitch(2)!))
        let cSharp = try XCTUnwrap(dMajor.degree(of: Pitch(1)!))
        XCTAssertEqual(cSharp, d - 1)
        XCTAssertNil(dMajor.pitch(atDegree: cSharp - 1), "B-2 no existe en MIDI")
    }

    // MARK: - Ida y vuelta

    /// Para toda altura permitida, en las ocho escalas y los doce Roots, ir a
    /// grado y volver da la misma altura, y el grado siguiente es la siguiente
    /// altura permitida.
    func testRoundTripAndSuccessorInEveryFrame() {
        for scale in Scale.allCases {
            for rootValue in Root.validRange {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                var previous: (pitch: Int, degree: Int)?
                for value in Pitch.validRange {
                    let pitch = Pitch(value)!
                    guard let degree = frame.degree(of: pitch) else {
                        XCTAssertFalse(frame.allows(pitch))
                        continue
                    }
                    XCTAssertEqual(
                        frame.pitch(atDegree: degree), pitch, "\(scale)·\(rootValue)·\(value)")
                    if let previous {
                        XCTAssertEqual(
                            degree, previous.degree + 1, "\(scale)·\(rootValue)·\(value)")
                    }
                    previous = (value, degree)
                }
            }
        }
    }
}
