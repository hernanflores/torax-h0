import XCTest
@testable import Engine

/// Tests de la superficie de pads: qué altura tiene cada uno de los dieciséis.
///
/// El núcleo de la rebanada 7 es que **un pad es un índice, no una altura**. Lo
/// que sigue fija qué altura le toca a cada índice, y sobre todo la invariante
/// de la que depende todo lo demás: el pad 9 es siempre el pad 1 más doce
/// semitonos.
final class PadSurfaceTests: XCTestCase {

    // MARK: - La octava base

    /// **El ejemplo canónico.** Do mayor, sin desplazar: los siete grados en la
    /// octava que empieza en la nota MIDI 48.
    func testTheFirstSevenPadsAreTheDegreesOfTheBaseOctave() {
        let surface = PadSurface(frame: TonalFrame(scale: .major, root: Root(0)!))
        XCTAssertEqual(pitches(of: surface, 0...6), [48, 50, 52, 53, 55, 57, 59])
    }

    /// **La base es la octava, no una nota fija.** Con Root en Re el pad 1 es la
    /// nota 50: el grado 1 es el Root por definición y se mueve con él.
    func testTheRootMovesTheWholeSurface() {
        let surface = PadSurface(frame: TonalFrame(scale: .major, root: Root(2)!))
        XCTAssertEqual(surface.pitch(at: 0)?.value, 50)
        XCTAssertEqual(pitches(of: surface, 0...6), [50, 52, 54, 55, 57, 59, 61])
    }

    /// Los pads 9–15 son los mismos grados una octava por encima, en el mismo
    /// orden — no otros grados ni el mismo bloque repetido.
    func testTheSecondBlockRepeatsTheDegreesOneOctaveUp() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let surface = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                for offset in 0..<7 {
                    let lower = surface.pitch(at: offset)
                    let upper = surface.pitch(at: offset + 8)
                    switch (lower, upper) {
                    case (nil, nil):
                        continue
                    case (let lower?, let upper?):
                        XCTAssertEqual(
                            upper.value, lower.value + 12, "\(scale)·\(rootValue)·\(offset)")
                    default:
                        XCTFail(
                            "Un bloque tiene altura y el otro no: \(scale)·\(rootValue)·\(offset)")
                    }
                }
            }
        }
    }

    /// **La invariante que sostiene los pads 8 y 16.** Sobre las cinco escalas y
    /// los doce Roots, sin excepción: si no se cumpliera, llamar *octava* al
    /// desplazamiento sería mentir.
    func testPadNineIsAlwaysPadOnePlusTwelveSemitones() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let surface = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                let first = surface.pitch(at: 0)
                let ninth = surface.pitch(at: 8)
                XCTAssertNotNil(first, "\(scale)·\(rootValue)")
                XCTAssertEqual(ninth?.value, first.map { $0.value + 12 }, "\(scale)·\(rootValue)")
            }
        }
    }

    // MARK: - Los pads que no tienen altura

    /// **La desviación consciente**: con cinco grados, los pads 6, 7, 14 y 15
    /// quedan apagados. Es comportamiento querido —decisión 3 del spec—, no un
    /// efecto de cómo se recorre la escala.
    func testAScaleWithFewerDegreesLeavesPadsUnassigned() {
        let surface = PadSurface(frame: TonalFrame(scale: .pentatonic, root: Root(0)!))
        for index in [5, 6, 13, 14] {
            XCTAssertNil(surface.pitch(at: index), "pad \(index + 1)")
        }
        for index in [0, 1, 2, 3, 4, 8, 9, 10, 11, 12] {
            XCTAssertNotNil(surface.pitch(at: index), "pad \(index + 1)")
        }
    }

    /// Los pads 8 y 16 son desplazamiento, no nota — en todas las escalas y
    /// todos los Roots.
    func testTheOctavePadsNeverHaveAPitch() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let surface = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                XCTAssertNil(surface.pitch(at: 7), "\(scale)·\(rootValue)")
                XCTAssertNil(surface.pitch(at: 15), "\(scale)·\(rootValue)")
            }
        }
    }

    /// Un índice fuera de 0–15 no tiene altura y no revienta: es el mismo
    /// criterio que un CC sin asignar.
    func testAnIndexOutsideTheSurfaceHasNoPitchAndDoesNotTrap() {
        let surface = PadSurface(frame: TonalFrame(scale: .major, root: Root(0)!))
        for index in [-1, -100, 16, 17, 128, Int.max, Int.min] {
            XCTAssertNil(surface.pitch(at: index), "\(index)")
        }
    }

    // MARK: - Toda altura sale de la escala

    /// Ningún pad puede meter en el pool una nota que el marco no admita. Es lo
    /// que sustituye al filtro cromático que esta rebanada retira.
    func testEveryAssignedPitchIsAllowedByTheFrame() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                let surface = PadSurface(frame: frame)
                for index in 0..<16 {
                    guard let pitch = surface.pitch(at: index) else { continue }
                    XCTAssertTrue(frame.allows(pitch), "\(scale)·\(rootValue)·\(index)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func pitches(of surface: PadSurface, _ indices: ClosedRange<Int>) -> [Int?] {
        indices.map { surface.pitch(at: $0)?.value }
    }
}
