import XCTest
@testable import Engine

/// Tests del pool de alturas.
///
/// La Pre Spec: «cada Track puede contener **hasta 8 pitches**», y «una nota
/// activada entra al pool; una desactivada se excluye». El pool va de una nota
/// —centro estable— a ocho.
///
/// **Es un pool, no una melodía.** No guarda qué nota suena en cada paso: guarda
/// de qué material se elige. Esa distinción es la que `product-guidelines.md`
/// eleva a antipatrón cuando se rompe.
final class PitchPoolTests: XCTestCase {

    // MARK: - La restricción que no se negocia

    /// **`Track` se copia en el hilo del scheduler.** Un `Array` dentro metería
    /// `retain`/`release` ahí, que es una violación de las reglas de tiempo
    /// real. `tech-stack.md` lo dejó escrito antes de que hiciera falta; este
    /// test es la red.
    func testThePoolIsATrivialType() {
        XCTAssertTrue(_isPOD(PitchPool.self), "el pool dejó de ser trivial")
    }

    func testTrackStaysTrivialWithThePoolInside() {
        XCTAssertTrue(_isPOD(Cycle.self), "Cycle dejó de ser trivial al entrar el pool")
    }

    // MARK: - Insertar y quitar

    func testAnEmptyPoolIsAValidState() {
        let pool = PitchPool()
        XCTAssertEqual(pool.count, 0)
        XCTAssertTrue(pool.isEmpty)
    }

    func testInsertingAddsThePitch() {
        let pool = PitchPool().inserting(Pitch(60)!)
        XCTAssertEqual(pool.count, 1)
        XCTAssertTrue(pool.contains(Pitch(60)!))
    }

    func testInsertingAPitchAlreadyPresentDoesNotDuplicateIt() {
        let pool = PitchPool().inserting(Pitch(60)!).inserting(Pitch(60)!)
        XCTAssertEqual(pool.count, 1)
    }

    func testRemovingTakesThePitchOut() {
        let pool = PitchPool().inserting(Pitch(60)!).removing(Pitch(60)!)
        XCTAssertEqual(pool.count, 0)
        XCTAssertFalse(pool.contains(Pitch(60)!))
    }

    func testRemovingAPitchThatIsNotThereChangesNothing() {
        let pool = PitchPool().inserting(Pitch(60)!)
        XCTAssertEqual(pool.removing(Pitch(72)!), pool)
    }

    func testTogglingPutsInAndTakesOut() {
        let empty = PitchPool()
        let withPitch = empty.toggling(Pitch(64)!)
        XCTAssertTrue(withPitch.contains(Pitch(64)!))
        XCTAssertEqual(withPitch.toggling(Pitch(64)!), empty)
    }

    // MARK: - Capacidad

    func testThePoolHoldsEightPitches() {
        var pool = PitchPool()
        for pitch in 60..<68 { pool = pool.inserting(Pitch(pitch)!) }
        XCTAssertEqual(pool.count, 8)
    }

    /// **Lleno rechaza la novena sin destruir las ocho.** Perder una nota para
    /// hacer sitio sería destruir material, que es lo que
    /// `product-guidelines.md` prohíbe.
    func testAFullPoolRejectsTheNinthWithoutLosingTheEight() {
        var pool = PitchPool()
        for pitch in 60..<68 { pool = pool.inserting(Pitch(pitch)!) }

        let rejected = pool.inserting(Pitch(80)!)
        XCTAssertEqual(rejected, pool, "el pool cambió al rechazar")
        XCTAssertFalse(rejected.contains(Pitch(80)!))
        for pitch in 60..<68 {
            XCTAssertTrue(rejected.contains(Pitch(pitch)!), "se perdió \(pitch)")
        }
    }

    // MARK: - Orden

    /// **El pool se recorre de grave a agudo.** Es el arpegio ascendente que la
    /// Pre Spec describe para Style monofónico, y hace que el recorrido no
    /// dependa del orden en que se pulsaron los pads.
    func testThePoolIsOrderedFromLowToHigh() {
        let pool = PitchPool()
            .inserting(Pitch(72)!)
            .inserting(Pitch(60)!)
            .inserting(Pitch(67)!)

        XCTAssertEqual(pool.pitch(at: 0), Pitch(60)!)
        XCTAssertEqual(pool.pitch(at: 1), Pitch(67)!)
        XCTAssertEqual(pool.pitch(at: 2), Pitch(72)!)
    }

    func testTheOrderDoesNotDependOnInsertionOrder() {
        let ascending = PitchPool().inserting(Pitch(60)!).inserting(Pitch(64)!).inserting(
            Pitch(67)!)
        let descending = PitchPool().inserting(Pitch(67)!).inserting(Pitch(64)!).inserting(
            Pitch(60)!)
        XCTAssertEqual(ascending, descending)
    }

    func testReadingPastTheEndGivesNothing() {
        let pool = PitchPool().inserting(Pitch(60)!)
        XCTAssertNil(pool.pitch(at: 1))
        XCTAssertNil(pool.pitch(at: -1))
        XCTAssertNil(PitchPool().pitch(at: 0))
    }

    /// El rango MIDI completo cabe: 0 y 127 no se confunden con «hueco vacío».
    func testTheExtremesOfTheMidiRangeAreStorable() {
        let pool = PitchPool().inserting(Pitch(0)!).inserting(Pitch(127)!)
        XCTAssertEqual(pool.count, 2)
        XCTAssertTrue(pool.contains(Pitch(0)!))
        XCTAssertTrue(pool.contains(Pitch(127)!))
    }

    // MARK: - Reencuadre no destructivo

    /// **La regla de destructividad de `product-guidelines.md`:** «el pool tonal
    /// sobrevive a un cambio de Scale reencuadrándose, no vaciándose». Es la
    /// misma que rige a `Pulses` desde la rebanada 2.
    func testReframingMovesOutOfFrameNotesInsteadOfDroppingThem() {
        let chromatic = PitchPool()
            .inserting(Pitch(60)!)  // Do — ya en Do mayor, no se mueve
            .inserting(Pitch(63)!)  // Re# — fuera, baja a Re (62)
            .inserting(Pitch(66)!)  // Fa# — fuera, baja a Fa (65)

        let frame = TonalFrame(scale: .major, root: Root(0)!)
        let reframed = chromatic.reframed(to: frame)

        XCTAssertEqual(reframed.count, 3, "se perdió material")
        for index in 0..<reframed.count {
            XCTAssertTrue(frame.allows(reframed.pitch(at: index)!), "quedó fuera de marco")
        }
    }

    /// Invariante: tras cualquier reencuadre, ninguna nota queda fuera del
    /// marco.
    func testNothingStaysOutsideTheFrameAfterReframing() {
        let pool = PitchPool()
            .inserting(Pitch(60)!).inserting(Pitch(61)!).inserting(Pitch(62)!)
            .inserting(Pitch(63)!).inserting(Pitch(64)!).inserting(Pitch(65)!)
            .inserting(Pitch(66)!).inserting(Pitch(67)!)

        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                let reframed = pool.reframed(to: frame)
                for index in 0..<reframed.count {
                    XCTAssertTrue(
                        frame.allows(reframed.pitch(at: index)!),
                        "\(scale) · Root \(rootValue) · índice \(index)"
                    )
                }
            }
        }
    }

    /// Una nota ya dentro del marco no se mueve.
    func testPitchesAlreadyInFrameAreLeftAlone() {
        let frame = TonalFrame(scale: .major, root: Root(0)!)
        let pool = PitchPool().inserting(Pitch(60)!).inserting(Pitch(64)!).inserting(Pitch(67)!)
        XCTAssertEqual(pool.reframed(to: frame), pool)
    }

    /// **Aquí sí se pierde material, y está aceptado.** Si dos notas caen en la
    /// misma al reencuadrar, el pool encoge en vez de guardar un duplicado. Es
    /// pérdida real; lo que el plan no acepta es que ocurra sin un test que la
    /// fije.
    ///
    /// El choque más simple: en Do mayor, Do# (61) baja a Do (60) por el
    /// desempate, y Do ya estaba.
    func testTwoPitchesCollapsingIntoOneShrinkThePool() {
        let pool = PitchPool().inserting(Pitch(60)!).inserting(Pitch(61)!)
        let reframed = pool.reframed(to: TonalFrame(scale: .major, root: Root(0)!))

        XCTAssertEqual(reframed.count, 1, "el duplicado no se colapsó")
        XCTAssertTrue(reframed.contains(Pitch(60)!))
    }

    func testReframingAnEmptyPoolLeavesItEmpty() {
        let reframed = PitchPool().reframed(to: TonalFrame(scale: .minor, root: Root(5)!))
        XCTAssertTrue(reframed.isEmpty)
    }
}
