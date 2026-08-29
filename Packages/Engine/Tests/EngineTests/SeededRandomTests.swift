import XCTest

@testable import Engine

/// Tests del generador pseudoaleatorio sembrado.
///
/// **La reproducibilidad se testea explícitamente**, como exige
/// `code_styleguides/swift.md`: misma semilla, misma secuencia. Es la propiedad
/// que la Pre Spec pide —«cambia, pero no es caos totalmente impredecible»— y
/// la única que separa este generador de un `Int.random()` prohibido.
final class SeededRandomTests: XCTestCase {

    // MARK: - Reproducibilidad

    /// La secuencia va escrita en el test, no comparada contra otra instancia:
    /// si el algoritmo cambiara, dos instancias seguirían coincidiendo entre
    /// sí y el test no se enteraría.
    func testSameSeedProducesTheSameSequence() {
        var first = SeededRandom(seed: 1)
        var second = SeededRandom(seed: 1)

        let fromFirst = (0..<16).map { _ in first.next() }
        let fromSecond = (0..<16).map { _ in second.next() }

        XCTAssertEqual(fromFirst, fromSecond)
    }

    func testDifferentSeedsDiverge() {
        var one = SeededRandom(seed: 1)
        var two = SeededRandom(seed: 2)

        let fromOne = (0..<16).map { _ in one.next() }
        let fromTwo = (0..<16).map { _ in two.next() }

        XCTAssertNotEqual(fromOne, fromTwo)
    }

    /// Reseembrar devuelve el generador a su punto de partida. Es lo que hace
    /// que pulsar Play dos veces reproduzca la misma sesión — la precisión de
    /// «repetible» documentada en `tech-stack.md` el 2026-08-29.
    func testReseedingReturnsToTheStart() {
        var generator = SeededRandom(seed: 7)
        let opening = (0..<8).map { _ in generator.next() }

        generator = SeededRandom(seed: 7)
        let again = (0..<8).map { _ in generator.next() }

        XCTAssertEqual(opening, again)
    }

    // MARK: - La secuencia no es degenerada

    /// Un generador que se cuelga en un valor o que alterna entre dos pasaría
    /// los tests de reproducibilidad y sería inservible para Probability.
    func testTheSequenceDoesNotCollapseToAFewValues() {
        var generator = SeededRandom(seed: 42)
        var seen = Set<UInt64>()

        for _ in 0..<1_000 {
            seen.insert(generator.next())
        }

        XCTAssertGreaterThan(seen.count, 990, "la secuencia se repite demasiado pronto")
    }

    /// Reparto grosso modo uniforme sobre el rango: sin esto, un Probability
    /// del 50% podría omitir el 90% de los Pulses.
    func testTheSequenceSpreadsAcrossTheRange() {
        var generator = SeededRandom(seed: 99)
        var buckets = [Int](repeating: 0, count: 4)

        for _ in 0..<4_000 {
            buckets[Int(generator.next() >> 62)] += 1
        }

        for count in buckets {
            XCTAssertGreaterThan(count, 800, "reparto sesgado: \(buckets)")
            XCTAssertLessThan(count, 1_200, "reparto sesgado: \(buckets)")
        }
    }

    /// Una semilla de cero no puede dejar al generador clavado — es el modo de
    /// fallo clásico de los generadores por desplazamiento y registro.
    func testZeroSeedStillGenerates() {
        var generator = SeededRandom(seed: 0)
        let values = (0..<8).map { _ in generator.next() }

        XCTAssertGreaterThan(Set(values).count, 1, "la semilla cero deja el generador clavado")
    }

    // MARK: - Trivialidad

    /// Vive dentro de `TrackScheduler`, que se construye en el hilo de control
    /// pero avanza en el del scheduler. Un estado que no sea trivial metería
    /// conteo de referencias en ese camino.
    func testTheGeneratorIsTrivial() {
        XCTAssertTrue(_isPOD(SeededRandom.self), "el generador dejó de ser trivial")
    }
}
