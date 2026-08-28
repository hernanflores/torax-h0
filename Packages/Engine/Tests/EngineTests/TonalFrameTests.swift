import XCTest
@testable import Engine

/// Tests del marco tonal: qué alturas permite una Scale sobre un Root.
///
/// La Pre Spec: «**Scale + Root** restringen la salida a una escala y centro
/// tonal». No escribe los intervalos de cada escala, así que los de aquí son el
/// registro canónico del proyecto — igual que `EuclideanRhythmTests` lo es de
/// los patrones euclidianos.
final class TonalFrameTests: XCTestCase {

    // MARK: - Los intervalos de cada preset

    /// Mayor natural: T T s T T T s.
    func testMajorIntervals() {
        XCTAssertEqual(pitchClasses(of: .major), [0, 2, 4, 5, 7, 9, 11])
    }

    /// Menor natural: T s T T s T T.
    func testMinorIntervals() {
        XCTAssertEqual(pitchClasses(of: .minor), [0, 2, 3, 5, 7, 8, 10])
    }

    /// Dórico: menor con la sexta mayor.
    func testDorianIntervals() {
        XCTAssertEqual(pitchClasses(of: .dorian), [0, 2, 3, 5, 7, 9, 10])
    }

    /// Frigio: menor con la segunda menor.
    func testPhrygianIntervals() {
        XCTAssertEqual(pitchClasses(of: .phrygian), [0, 1, 3, 5, 7, 8, 10])
    }

    /// Pentatónica menor: cinco notas, sin los dos semitonos de la menor.
    func testPentatonicIntervals() {
        XCTAssertEqual(pitchClasses(of: .pentatonic), [0, 3, 5, 7, 10])
    }

    // MARK: - Root

    /// **Root transpone el conjunto sin cambiar su forma.** Los intervalos entre
    /// notas consecutivas son los mismos en cualquier tonalidad; lo que cambia
    /// es dónde empiezan.
    func testRootTransposesWithoutChangingShape() {
        let shape = intervalShape(of: .minor, root: 0)
        for pitchClass in 0..<12 {
            XCTAssertEqual(intervalShape(of: .minor, root: pitchClass), shape, "Root \(pitchClass)")
        }
    }

    func testRootShiftsTheAllowedPitchClasses() {
        let frame = TonalFrame(scale: .major, root: Root(2)!)
        XCTAssertEqual(pitchClasses(of: frame), [1, 2, 4, 6, 7, 9, 11])
    }

    /// Si mayor: B C# D# E F# G# A#. La fundamental es la clase más alta, así
    /// que la escala envuelve y ninguna nota se pierde en el borde.
    func testRootWrapsAroundTheOctave() {
        let frame = TonalFrame(scale: .major, root: Root(11)!)
        XCTAssertEqual(pitchClasses(of: frame), [1, 3, 4, 6, 8, 10, 11])
    }

    func testRootRejectsValuesOutsideTheOctave() {
        XCTAssertNil(Root(-1))
        XCTAssertNil(Root(12))
        XCTAssertNotNil(Root(0))
        XCTAssertNotNil(Root(11))
    }

    // MARK: - Recorrer las escalas

    /// Misma regla que `Division`: recorrer se detiene en los extremos, no
    /// envuelve. Un knob que dé la vuelta sorprende.
    func testAdvancingStopsAtTheEnds() {
        XCTAssertEqual(Scale.ordered.first!.advanced(by: -5), Scale.ordered.first!)
        XCTAssertEqual(Scale.ordered.last!.advanced(by: 5), Scale.ordered.last!)
    }

    func testAdvancingWalksTheOrderedList() {
        for (index, scale) in Scale.ordered.enumerated() where index + 1 < Scale.ordered.count {
            XCTAssertEqual(scale.advanced(by: 1), Scale.ordered[index + 1], "desde \(scale)")
        }
    }

    func testEveryScaleIsInTheOrderedList() {
        XCTAssertEqual(Set(Scale.ordered), Set(Scale.allCases))
        XCTAssertEqual(Scale.ordered.count, Scale.allCases.count, "sin repetidos")
    }

    // MARK: - Qué alturas permite

    /// La pertenencia depende solo de la clase de altura: si Do está en la
    /// escala, lo está en todas las octavas.
    func testMembershipIsTheSameInEveryOctave() {
        let frame = TonalFrame(scale: .minor, root: Root(0)!)
        for pitch in 0...127 {
            XCTAssertEqual(
                frame.allows(Pitch(pitch)!),
                frame.allows(Pitch(pitch % 12)!),
                "altura \(pitch)"
            )
        }
    }

    /// Invariante exhaustiva: para toda Scale y todo Root, una altura está
    /// permitida si y solo si su clase está en el conjunto transpuesto.
    func testMembershipMatchesTheTransposedSet() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                let allowed = Set(pitchClasses(of: frame))
                for pitch in 0...127 {
                    XCTAssertEqual(
                        frame.allows(Pitch(pitch)!),
                        allowed.contains(pitch % 12),
                        "\(scale) · Root \(rootValue) · altura \(pitch)"
                    )
                }
            }
        }
    }

    // MARK: - La permitida más cercana

    func testAPitchAlreadyInTheFrameIsItsOwnNearest() {
        let frame = TonalFrame(scale: .major, root: Root(0)!)
        for pitch in 0...127 where frame.allows(Pitch(pitch)!) {
            XCTAssertEqual(frame.nearest(to: Pitch(pitch)!), Pitch(pitch)!, "altura \(pitch)")
        }
    }

    func testAPitchOutsideTheFrameMovesToTheClosestAllowedOne() {
        let frame = TonalFrame(scale: .major, root: Root(0)!)
        // Do sostenido (61) está entre Do (60) y Re (62), ambos permitidos.
        // El desempate es hacia abajo, así que baja a Do.
        XCTAssertEqual(frame.nearest(to: Pitch(61)!), Pitch(60)!)
        // Fa sostenido (66) tiene Fa (65) a un semitono y Sol (67) a uno:
        // empate, baja.
        XCTAssertEqual(frame.nearest(to: Pitch(66)!), Pitch(65)!)
    }

    /// **El desempate está escrito, no descubierto.** Con dos permitidas a la
    /// misma distancia se baja, porque bajar conserva el registro y subir puede
    /// empujar una nota fuera del rango por arriba.
    func testTiesResolveDownwards() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                for pitch in 1...126 {
                    let source = Pitch(pitch)!
                    guard !frame.allows(source) else { continue }
                    let nearest = frame.nearest(to: source)
                    let distanceDown = pitch - nearest.value
                    let distanceUp = nearest.value - pitch
                    guard distanceUp > 0 else { continue }
                    // Si subió, es que no había ninguna igual de cerca abajo.
                    let mirrored = pitch - distanceUp
                    if mirrored >= 0 {
                        XCTAssertFalse(
                            frame.allows(Pitch(mirrored)!),
                            "\(scale) · Root \(rootValue) · \(pitch) subió habiendo empate abajo"
                        )
                    }
                }
            }
        }
    }

    /// Ninguna reubicación se sale del rango MIDI, ni siquiera en los bordes.
    func testNearestStaysWithinTheMidiRange() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                for pitch in 0...127 {
                    let nearest = frame.nearest(to: Pitch(pitch)!)
                    XCTAssertTrue(frame.allows(nearest), "\(scale)·\(rootValue)·\(pitch)")
                    XCTAssertTrue(
                        Pitch.validRange.contains(nearest.value), "\(scale)·\(rootValue)·\(pitch)"
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func pitchClasses(of scale: Scale) -> [Int] {
        pitchClasses(of: TonalFrame(scale: scale, root: Root(0)!))
    }

    private func pitchClasses(of frame: TonalFrame) -> [Int] {
        (0..<12).filter { frame.allows(Pitch($0)!) }
    }

    /// La forma de la escala: los saltos entre notas consecutivas, cerrando la
    /// octava.
    private func intervalShape(of scale: Scale, root: Int) -> [Int] {
        let classes = pitchClasses(of: TonalFrame(scale: scale, root: Root(root)!)).sorted()
        let rotated =
            classes.drop(while: { $0 < root })
            + classes.prefix(while: { $0 < root }).map { $0 + 12 }
        return zip(rotated, rotated.dropFirst()).map { $1 - $0 }
    }
}
