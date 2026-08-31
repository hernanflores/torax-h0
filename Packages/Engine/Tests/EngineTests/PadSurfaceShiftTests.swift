import XCTest
@testable import Engine

/// Tests del desplazamiento de octava de la superficie de pads.
///
/// Los pads 8 y 16 mueven el registro entero. Lo que estos tests fijan no es
/// solo que mueva, sino **cómo se detiene**: sin envolver y sin recortar, que
/// son las dos formas de romper el alineamiento por octava del que depende todo
/// lo demás.
final class PadSurfaceShiftTests: XCTestCase {

    // MARK: - Mover

    /// **El ejemplo literal del requisito.** Pad 1 en la nota 48 y pad 9 en la
    /// 60; tras el pad 8 quedan en 36 y 48; desde el estado inicial, tras el pad
    /// 16 quedan en 60 y 72.
    func testTheLiteralExampleFromTheRequirement() {
        let base = PadSurface(frame: TonalFrame(scale: .major, root: Root(0)!))
        XCTAssertEqual(base.pitch(at: 0)?.value, 48)
        XCTAssertEqual(base.pitch(at: 8)?.value, 60)

        let down = base.shiftedDown()
        XCTAssertEqual(down.pitch(at: 0)?.value, 36)
        XCTAssertEqual(down.pitch(at: 8)?.value, 48)

        let up = base.shiftedUp()
        XCTAssertEqual(up.pitch(at: 0)?.value, 60)
        XCTAssertEqual(up.pitch(at: 8)?.value, 72)
    }

    /// **Todas** las alturas asignadas se mueven doce semitonos, no solo un
    /// bloque: si los dos bloques no se movieran juntos, el pad 9 dejaría de
    /// estar una octava sobre el pad 1.
    func testShiftingMovesEveryAssignedPitch() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let base = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                for (shifted, delta) in [(base.shiftedUp(), 12), (base.shiftedDown(), -12)] {
                    for index in 0..<16 {
                        guard let before = base.pitch(at: index) else {
                            XCTAssertNil(shifted.pitch(at: index), "\(scale)·\(rootValue)·\(index)")
                            continue
                        }
                        XCTAssertEqual(
                            shifted.pitch(at: index)?.value, before.value + delta,
                            "\(scale)·\(rootValue)·\(index)")
                    }
                }
            }
        }
    }

    /// Desplazar y volver deja la superficie idéntica: el desplazamiento es
    /// estado, no una transformación acumulada sobre las alturas.
    func testShiftingUpAndBackReturnsTheSameSurface() {
        let base = PadSurface(frame: TonalFrame(scale: .minor, root: Root(7)!))
        XCTAssertEqual(base.shiftedUp().shiftedDown(), base)
        XCTAssertEqual(base.shiftedDown().shiftedUp(), base)
    }

    // MARK: - El tope

    /// Se admite mientras **todas** las alturas asignadas quepan en 0–127. En el
    /// extremo el desplazamiento no se aplica y el estado queda idéntico — el
    /// pad deja de responder, que es lo que la pantalla tiene que decir.
    func testTheShiftStopsWhenAnyPitchWouldLeaveTheMidiRange() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let base = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))

                var top = base
                for _ in 0..<32 { top = top.shiftedUp() }
                XCTAssertEqual(top.shiftedUp(), top, "tope agudo \(scale)·\(rootValue)")
                XCTAssertFalse(top.canShiftUp, "tope agudo \(scale)·\(rootValue)")
                XCTAssertTrue(top.canShiftDown, "tope agudo \(scale)·\(rootValue)")

                var bottom = base
                for _ in 0..<32 { bottom = bottom.shiftedDown() }
                XCTAssertEqual(bottom.shiftedDown(), bottom, "tope grave \(scale)·\(rootValue)")
                XCTAssertFalse(bottom.canShiftDown, "tope grave \(scale)·\(rootValue)")
                XCTAssertTrue(bottom.canShiftUp, "tope grave \(scale)·\(rootValue)")
            }
        }
    }

    /// **No envuelve y no recorta**, que son las dos formas de romper el
    /// alineamiento. En cada uno de los treinta y dos desplazamientos: los
    /// dieciséis pads siguen dentro del rango, ninguno se queda pegado al borde
    /// mientras otro sigue subiendo, y el pad 9 sigue exactamente doce semitonos
    /// sobre el pad 1.
    func testTheShiftNeitherWrapsNorClamps() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let base = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                for direction in [true, false] {
                    var surface = base
                    var previous = assignedPitches(of: surface)
                    for step in 0..<32 {
                        let next = direction ? surface.shiftedUp() : surface.shiftedDown()
                        let pitches = assignedPitches(of: next)
                        let label = "\(scale)·\(rootValue)·\(direction)·\(step)"

                        // Ninguna altura desaparece: recortar contra el borde se
                        // vería aquí como un pad que se queda sin nota.
                        XCTAssertEqual(pitches.count, previous.count, label)
                        // Ni un salto de siete octavas al otro extremo.
                        if next != surface {
                            let delta = direction ? 12 : -12
                            XCTAssertEqual(pitches, previous.map { $0 + delta }, label)
                        } else {
                            XCTAssertEqual(pitches, previous, label)
                        }
                        // La invariante, en cada peldaño del recorrido.
                        if let first = next.pitch(at: 0), let ninth = next.pitch(at: 8) {
                            XCTAssertEqual(ninth.value, first.value + 12, label)
                        }

                        surface = next
                        previous = pitches
                    }
                }
            }
        }
    }

    /// El tope depende de la escala y del Root: no es un número fijo, es dónde
    /// cae la altura más grave y la más aguda de esa superficie concreta.
    func testTheLimitDependsOnTheScaleAndTheRoot() {
        var highestReached: [String: Int] = [:]
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                var surface = PadSurface(frame: TonalFrame(scale: scale, root: Root(rootValue)!))
                while surface.canShiftUp { surface = surface.shiftedUp() }
                highestReached["\(scale)·\(rootValue)"] = surface.octaveShift

                // En el tope, la altura más aguda cabe y la siguiente no.
                let highest = (0..<16).compactMap { surface.pitch(at: $0)?.value }.max()!
                XCTAssertTrue(Pitch.validRange.contains(highest), "\(scale)·\(rootValue)")
                XCTAssertGreaterThan(
                    highest + 12, Pitch.validRange.upperBound, "\(scale)·\(rootValue)")
            }
        }
        XCTAssertGreaterThan(Set(highestReached.values).count, 1, "El tope no depende de nada")
    }

    // MARK: - Helpers

    private func assignedPitches(of surface: PadSurface) -> [Int] {
        (0..<16).compactMap { surface.pitch(at: $0)?.value }
    }
}
