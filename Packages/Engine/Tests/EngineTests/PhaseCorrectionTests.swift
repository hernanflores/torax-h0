import XCTest

@testable import Engine

/// Tests de la corrección de fase contra un maestro externo.
///
/// El tempo estimado acierta de media y la rejilla se separa despacio; esto es
/// lo que la devuelve al sitio. Un error de signo aquí no se oye como desfase
/// sino como que la app se aleja el doble de rápido.
final class PhaseCorrectionTests: XCTestCase {

    /// Negra de 500 ms: 120 BPM.
    private let quarterNote = 500_000_000.0

    private func correction(
        origin: Int64, tick: Int64, limit: Int64 = 50_000_000
    ) -> Int64 {
        PhaseCorrection.nanoseconds(
            gridOriginNanoseconds: origin,
            quarterNoteNanoseconds: quarterNote,
            masterTickNanoseconds: tick,
            limitNanoseconds: limit)
    }

    // MARK: - En fase

    /// Un tick que cae justo en un límite de la rejilla no mueve nada.
    func testATickOnTheGridNeedsNoCorrection() {
        XCTAssertEqual(correction(origin: 0, tick: 4 * 500_000_000), 0)
    }

    /// Y el origen mismo es un límite de la rejilla.
    func testTheOriginItselfIsOnTheGrid() {
        XCTAssertEqual(correction(origin: 1_000_000_000, tick: 1_000_000_000), 0)
    }

    // MARK: - Signo

    /// Rejilla **adelantada**: su límite ya pasó cuando llega el tick del
    /// maestro. La corrección es positiva — retrasa el origen.
    func testAnAheadGridIsPushedLater() {
        let tick = Int64(2 * 500_000_000) + 5_000_000  // 5 ms después del límite
        XCTAssertEqual(correction(origin: 0, tick: tick), 5_000_000)
    }

    /// Rejilla **atrasada**: el tick llega antes que su límite. La corrección es
    /// negativa — adelanta el origen.
    func testABehindGridIsPulledEarlier() {
        let tick = Int64(2 * 500_000_000) - 5_000_000  // 5 ms antes del límite
        XCTAssertEqual(correction(origin: 0, tick: tick), -5_000_000)
    }

    /// Se corrige contra el límite **más cercano**, no contra el anterior: un
    /// tick a un milisegundo del siguiente pulso se adelanta un milisegundo, no
    /// se retrasa casi una negra.
    func testTheNearestBoundaryWins() {
        let tick = Int64(3 * 500_000_000) - 1_000_000
        XCTAssertEqual(correction(origin: 0, tick: tick), -1_000_000)
    }

    /// Aplicar la corrección deja la rejilla en fase: corregir dos veces
    /// seguidas no mueve nada la segunda.
    func testApplyingTheCorrectionLeavesNoError() {
        let tick = Int64(2 * 500_000_000) + 5_000_000
        let first = correction(origin: 0, tick: tick)

        XCTAssertEqual(correction(origin: first, tick: tick), 0)
    }

    // MARK: - Origen posterior al tick

    /// Con el origen por delante del tick —posible en el arranque, porque el
    /// origen lleva el presupuesto de Delay negativo— la aritmética sigue
    /// dando el límite más cercano y no un módulo negativo suelto.
    func testAnOriginAfterTheTickStillFindsTheNearestBoundary() {
        let origin = Int64(1_000_000_000)
        let tick = origin - Int64(500_000_000) - 3_000_000  // una negra antes, 3 ms tarde

        XCTAssertEqual(correction(origin: origin, tick: tick), -3_000_000)
    }

    // MARK: - Acotada

    /// Un tick absurdamente desviado no produce un salto arbitrario: la
    /// corrección se acota, y lo que sobra se irá en las negras siguientes.
    func testTheCorrectionIsClamped() {
        let tick = Int64(2 * 500_000_000) + 200_000_000  // 200 ms tarde
        XCTAssertEqual(correction(origin: 0, tick: tick, limit: 10_000_000), 10_000_000)
    }

    /// Y también por el lado negativo.
    func testTheClampIsSymmetric() {
        let tick = Int64(2 * 500_000_000) - 200_000_000
        XCTAssertEqual(correction(origin: 0, tick: tick, limit: 10_000_000), -10_000_000)
    }

    /// Con límite cero no se corrige nada: es la forma de apagar la corrección
    /// sin ramas en quien la llama.
    func testAZeroLimitDisablesTheCorrection() {
        let tick = Int64(2 * 500_000_000) + 5_000_000
        XCTAssertEqual(correction(origin: 0, tick: tick, limit: 0), 0)
    }

    // MARK: - Entradas imposibles

    /// Una negra de duración no positiva no puede definir una fase. No se
    /// corrige, en vez de dividir por cero.
    func testANonPositiveQuarterNoteCorrectsNothing() {
        XCTAssertEqual(
            PhaseCorrection.nanoseconds(
                gridOriginNanoseconds: 0,
                quarterNoteNanoseconds: 0,
                masterTickNanoseconds: 5_000_000,
                limitNanoseconds: 50_000_000),
            0)
    }
}
