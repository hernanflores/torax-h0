import XCTest

@testable import Engine

/// Tests de qué hay que refrescar al pegar.
///
/// **Lo encontró la verificación en dispositivo del 2026-09-10.** Pegar escribía
/// en el `Project` y dejaba sin tocar las dos copias que el `Project` no
/// gobierna: la copia viva del Pattern cargado —la que la pantalla edita y la
/// que se vuelca al Bank en cada edición— y el snapshot que el transporte ya
/// tenía armado.
///
/// El resultado era que lo pegado no sonaba, y que el primer giro de knob
/// devolvía el material anterior encima. La decisión de qué refrescar es una
/// regla, así que vive aquí.
final class PatternPasteRefreshTests: XCTestCase {

    /// Pegar en el hueco que está cargado exige refrescar la copia viva: si no,
    /// la pantalla enseña lo viejo y la próxima edición lo devuelve al Bank.
    func testPastingIntoTheLoadedSlotRefreshesTheLiveCopy() {
        let refresh = PatternPasteRefresh(destination: 3, loaded: 3, armed: nil)

        XCTAssertTrue(refresh.refreshesLiveCopy)
        XCTAssertFalse(refresh.rearms)
    }

    /// Pegar en otro hueco no toca la copia viva: lo cargado no ha cambiado.
    func testPastingElsewhereLeavesTheLiveCopyAlone() {
        let refresh = PatternPasteRefresh(destination: 7, loaded: 3, armed: nil)

        XCTAssertFalse(refresh.refreshesLiveCopy)
        XCTAssertFalse(refresh.rearms)
    }

    /// **Pegar en el hueco armado exige rearmarlo con el material nuevo.** El
    /// transporte recibió el snapshot al armar, antes del pegado, así que sin
    /// rearmar entra el material viejo en el límite de compás.
    func testPastingIntoTheArmedSlotRearmsIt() {
        let refresh = PatternPasteRefresh(destination: 9, loaded: 3, armed: 9)

        XCTAssertTrue(refresh.rearms)
        XCTAssertFalse(refresh.refreshesLiveCopy, "el 9 no es lo cargado")
    }

    /// Pegar en un hueco que no es el armado no rearma nada.
    func testPastingOutsideTheArmedSlotDoesNotRearm() {
        let refresh = PatternPasteRefresh(destination: 4, loaded: 3, armed: 9)
        XCTAssertFalse(refresh.rearms)
    }

    /// **Las dos cosas a la vez.** Sonando se puede rearmar el hueco que ya
    /// suena, y entonces el destino es a la vez lo cargado y lo armado.
    func testPastingIntoASlotThatIsBothLoadedAndArmedDoesBoth() {
        let refresh = PatternPasteRefresh(destination: 3, loaded: 3, armed: 3)

        XCTAssertTrue(refresh.refreshesLiveCopy)
        XCTAssertTrue(refresh.rearms)
    }

    /// Sin nada armado nunca se rearma, mande quien mande el destino.
    func testWithNothingArmedNothingIsRearmed() {
        for destination in 0..<Bank.patternCount {
            XCTAssertFalse(
                PatternPasteRefresh(destination: destination, loaded: 3, armed: nil).rearms,
                "destino \(destination)"
            )
        }
    }
}
