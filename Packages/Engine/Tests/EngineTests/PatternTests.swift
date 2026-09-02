import XCTest
@testable import Engine

/// **`Pattern` a secas es ambiguo en un target de test.** Los tests corren en
/// macOS y XCTest arrastra `ApplicationServices`, que trae un `Pattern` de
/// Quickdraw. Se cualifica aquí en vez de renombrar el tipo del dominio, que se
/// llama como lo llama la Pre Spec.
private typealias Pattern = Engine.Pattern

/// Tests del `Pattern`: los dieciséis Tracks como un solo valor.
///
/// **Es el valor que cruza al hilo del scheduler.** Hasta la v1 lo que se
/// publicaba era un `Track`; a partir de aquí son dieciséis, y lo que estos
/// tests vigilan antes que nada es que siga siendo un dato trivial — copiable
/// con un `memcpy`, sin nada con conteo de referencias dentro—. Si eso no se
/// cumple, el resto de la rebanada no es posible tal como está planteada.
final class PatternTests: XCTestCase {

    // MARK: - Dieciséis, siempre

    /// «Hasta 16 Tracks por Pattern», dice la Pre Spec. Aquí son dieciséis
    /// exactos: ninguno se crea ni se destruye.
    func testAPatternAlwaysHasSixteenTracks() {
        let pattern = Pattern()
        XCTAssertEqual(Pattern.trackCount, 16)
        for index in 0..<16 {
            XCTAssertNotNil(pattern.cycle(at: index), "Track \(index + 1)")
        }
    }

    /// Un Pattern recién construido no tiene material en ninguno: dieciséis
    /// Tracks vacíos son silencio, y el silencio sale del material y no de una
    /// bandera de actividad.
    func testAFreshPatternHasNoMaterialAnywhere() {
        let pattern = Pattern()
        for index in 0..<16 {
            XCTAssertTrue(pattern.cycle(at: index)!.pool.isEmpty, "Track \(index + 1)")
        }
    }

    /// Un índice fuera de 0–15 no existe y no revienta — mismo criterio que un
    /// pad fuera de la superficie o un CC sin asignar.
    func testAnIndexOutsideThePatternHasNoTrack() {
        let pattern = Pattern()
        for index in [-1, -100, 16, 17, 128, Int.max, Int.min] {
            XCTAssertNil(pattern.cycle(at: index), "\(index)")
        }
    }

    // MARK: - Sustituir uno no toca los otros quince

    func testReplacingATrackChangesOnlyThatOne() {
        let pattern = Pattern()
        let edited = Cycle(
            shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!),
            pool: PitchPool().toggling(Pitch(60)!)
        )

        for target in 0..<16 {
            let updated = pattern.replacing(edited, at: target)

            XCTAssertEqual(updated.cycle(at: target), edited, "Track \(target + 1)")
            for other in 0..<16 where other != target {
                XCTAssertEqual(
                    updated.cycle(at: other), pattern.cycle(at: other),
                    "el Track \(target + 1) tocó al \(other + 1)")
            }
        }
    }

    /// Sustituir fuera de rango devuelve el Pattern intacto: no es un error, no
    /// cambia nada.
    func testReplacingOutsideTheRangeChangesNothing() {
        let pattern = Pattern()
        let edited = Cycle(shape: Shape(steps: Steps(4)!, pulses: Pulses(1)!))

        for index in [-1, 16, Int.max] {
            XCTAssertEqual(pattern.replacing(edited, at: index), pattern, "\(index)")
        }
    }

    /// Los dieciséis huecos son independientes entre sí: se llenan uno a uno y
    /// cada uno conserva lo suyo.
    func testEverySlotKeepsItsOwnTrack() {
        var pattern = Pattern()
        for index in 0..<16 {
            let track = Cycle(shape: Shape(steps: Steps(index + 1)!, pulses: Pulses(1)!))
            pattern = pattern.replacing(track, at: index)
        }

        for index in 0..<16 {
            XCTAssertEqual(
                pattern.cycle(at: index)?.shape.steps.count, index + 1, "Track \(index + 1)")
        }
    }

    // MARK: - Igualdad

    func testTwoPatternsWithTheSameTracksAreEqual() {
        let track = Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!))
        XCTAssertEqual(Pattern().replacing(track, at: 5), Pattern().replacing(track, at: 5))
        XCTAssertNotEqual(Pattern().replacing(track, at: 5), Pattern().replacing(track, at: 6))
    }

    // MARK: - La red de tiempo real

    /// **La comprobación que decide si la rebanada es posible.** El hilo del
    /// scheduler copia este valor en cada ventana; un `retain` ahí es una
    /// violación de las reglas de tiempo real. Es la misma red que ya vigila a
    /// `Track`, sobre el tipo que de verdad cruza.
    func testThePatternIsATrivialValue() {
        XCTAssertTrue(_isPOD(Pattern.self), "Pattern dejó de ser trivial")
        XCTAssertTrue(_isPOD(Cycle.self), "Cycle dejó de ser trivial")
    }

    /// El tamaño es dieciséis Tracks y nada más: sin cabecera, sin punteros.
    ///
    /// > **Cambió el 2026-09-02, al entrar Cycles.** Un Track dejó de ser el
    /// > juego de parámetros y pasó a contener dieciséis, así que el Pattern
    /// > pasa de 2304 bytes a 37 248. El coste de copiarlo se midió **antes** de
    /// > construirlo, en `CycleSnapshotCostTests`: ~870 ns, el 0,0044% de la
    /// > ventana. Esta aserción sigue vigilando lo mismo que antes —que no haya
    /// > cabecera ni punteros— sobre el nivel que ahora corresponde.
    func testThePatternIsExactlySixteenTracksWide() {
        XCTAssertEqual(MemoryLayout<Pattern>.size, MemoryLayout<Track>.size * 16)
        XCTAssertEqual(MemoryLayout<Track>.size, MemoryLayout<Cycle>.size * 16 + 24)
    }
}
