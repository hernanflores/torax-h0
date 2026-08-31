import XCTest
@testable import Engine

/// Tests de la enumeración por grados de una Scale.
///
/// La superficie de pads de la rebanada 7 no pregunta *qué alturas admite el
/// marco* sino *cuál es el grado N*: el pad 3 es el tercer grado, sea cual sea
/// la escala. Enumerar es la operación que faltaba, y estos tests fijan que
/// **enumerar y admitir son la misma escala vista de dos maneras**, no dos
/// tablas que puedan divergir.
final class ScaleDegreesTests: XCTestCase {

    // MARK: - Cuántos grados tiene cada escala

    /// Cuatro de las cinco escalas de v1 son heptatónicas.
    func testTheSevenNoteScalesHaveSevenDegrees() {
        for scale in [Scale.minor, .major, .dorian, .phrygian] {
            XCTAssertEqual(scale.degrees.count, 7, "\(scale)")
        }
    }

    /// **La pentatónica tiene cinco, y es la razón de que cuatro pads queden
    /// apagados.** El número sale de la máscara, no de una tabla nueva.
    func testThePentatonicHasFiveDegrees() {
        XCTAssertEqual(Scale.pentatonic.degrees.count, 5)
    }

    // MARK: - Qué grados son

    /// Los mismos números que `TonalFrameTests` fija como registro canónico del
    /// proyecto, aquí en su otra forma: no un conjunto que se consulta, una
    /// lista que se recorre.
    func testDegreesAreTheSemitonesOfTheScaleInAscendingOrder() {
        XCTAssertEqual(Scale.major.degrees, [0, 2, 4, 5, 7, 9, 11])
        XCTAssertEqual(Scale.minor.degrees, [0, 2, 3, 5, 7, 8, 10])
        XCTAssertEqual(Scale.dorian.degrees, [0, 2, 3, 5, 7, 9, 10])
        XCTAssertEqual(Scale.phrygian.degrees, [0, 1, 3, 5, 7, 8, 10])
        XCTAssertEqual(Scale.pentatonic.degrees, [0, 3, 5, 7, 10])
    }

    /// **El grado 1 es siempre el 0** — el Root por definición. Es lo que hace
    /// que el pad 1 sea el Root seleccionado, en cualquier escala.
    func testTheFirstDegreeIsAlwaysTheRoot() {
        for scale in Scale.allCases {
            XCTAssertEqual(scale.degrees.first, 0, "\(scale)")
        }
    }

    /// Ascendente y sin repeticiones: dos grados nunca dan la misma nota.
    func testDegreesAreStrictlyAscending() {
        for scale in Scale.allCases {
            let degrees = scale.degrees
            XCTAssertEqual(degrees, degrees.sorted(), "\(scale)")
            XCTAssertEqual(Set(degrees).count, degrees.count, "\(scale)")
        }
    }

    /// Todos dentro de la octava: un grado es un desplazamiento sobre el Root,
    /// no una altura.
    func testDegreesStayWithinTheOctave() {
        for scale in Scale.allCases {
            for degree in scale.degrees {
                XCTAssertTrue((0..<12).contains(degree), "\(scale)·\(degree)")
            }
        }
    }

    // MARK: - Enumerar no contradice a admitir

    /// **La comprobación que impide que las dos tablas diverjan.** Toda altura
    /// construida desde un grado —Root más grado, en cualquier octava— es
    /// admitida por el marco, sobre las cinco escalas y los doce Roots.
    func testEveryPitchBuiltFromADegreeIsAllowedByTheFrame() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                for octaveBase in stride(from: 0, through: 108, by: 12) {
                    for degree in scale.degrees {
                        // La octava más aguda no llega entera al rango MIDI;
                        // lo que se sale no es un caso, es que no existe.
                        guard let pitch = Pitch(octaveBase + rootValue + degree) else { continue }
                        XCTAssertTrue(frame.allows(pitch), "\(scale)·\(rootValue)·\(degree)")
                    }
                }
            }
        }
    }

    /// Y al revés: los grados **agotan** el marco. Ninguna clase de altura
    /// admitida se queda sin grado, así que ningún pad se pierde una nota de la
    /// escala.
    func testTheDegreesCoverEveryAllowedPitchClass() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                let allowed = Set((0..<12).filter { frame.allows(Pitch($0)!) })
                let fromDegrees = Set(scale.degrees.map { ($0 + rootValue) % 12 })
                XCTAssertEqual(fromDegrees, allowed, "\(scale)·\(rootValue)")
            }
        }
    }
}
