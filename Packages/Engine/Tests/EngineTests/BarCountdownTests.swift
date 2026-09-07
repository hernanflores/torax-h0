import XCTest

@testable import Engine

/// Tests de la cuenta atrás hasta el compás (FR25).
///
/// **La vista no calcula tiempo.** Lo que pinta la pantalla mientras un Pattern
/// espera sale de aquí, ya en la forma en que se va a leer: un número de negras,
/// no nanosegundos que alguien tenga que dividir en la vista.
///
/// **Se cuenta en negras y no en segundos** porque es lo que se lee a un metro
/// mientras suena algo: «entra en 2» es una instrucción, «en 1,4 s» es un dato.
final class BarCountdownTests: XCTestCase {

    private let bar = BarGrid(tempo: Tempo(beatsPerMinute: 120)!)

    /// Desde el origen faltan las cuatro negras del compás.
    func testFromTheOriginTheWholeBarIsLeft() {
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 0), 4)
    }

    /// **Se redondea hacia arriba**: mientras quede algo de la negra en curso,
    /// esa negra todavía cuenta. Redondear hacia abajo enseñaría un 0 durante
    /// medio segundo, y un 0 que no entra es peor que no enseñar nada.
    func testAPartialBeatStillCounts() {
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 1), 4)
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 500_000_000), 3)
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 500_000_001), 3)
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 1_500_000_000), 1)
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 1_999_999_999), 1)
    }

    /// Justo en el límite empieza otro compás entero.
    func testOnTheBoundaryTheCountStartsOver() {
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: 2_000_000_000), 4)
    }

    /// La cuenta nunca es 0 ni mayor que un compás, en ningún instante.
    func testTheCountIsAlwaysBetweenOneAndFour() {
        for nanoseconds in stride(from: Int64(0), to: Int64(12_000_000_000), by: 97_000_000) {
            let beats = bar.beatsUntilNextBoundary(at: nanoseconds)
            XCTAssertGreaterThanOrEqual(beats, 1, "\(nanoseconds)")
            XCTAssertLessThanOrEqual(beats, BarGrid.beatsPerBar, "\(nanoseconds)")
        }
    }

    /// El tempo no cambia el número de negras, solo lo que dura cada una: es la
    /// razón de contar negras y no segundos.
    func testTheCountIsTheSameAtAnyTempo() {
        for bpm in [60.0, 120.0, 174.0] {
            let grid = BarGrid(tempo: Tempo(beatsPerMinute: bpm)!)
            XCTAssertEqual(grid.beatsUntilNextBoundary(at: 0), 4, "\(bpm) BPM")
        }
    }

    /// Antes del origen no se cuenta hacia atrás: falta el compás entero.
    func testBeforeTheOriginTheWholeBarIsLeft() {
        XCTAssertEqual(bar.beatsUntilNextBoundary(at: -1), 4)
    }
}
