import XCTest

@testable import Engine

/// Tests del mapa entre el tiempo del reloj y el tiempo musical.
///
/// Es lo que permite seguir a un maestro **sin tocar la rejilla**: los Steps se
/// siguen calculando contra un tempo de referencia fijo, y este mapa convierte
/// esos instantes en tiempo de reloj. Un error aquí no se oye como desafinación
/// sino como que la app se va de tempo o da un salto.
final class TempoMapTests: XCTestCase {

    /// Negra de 500 ms: el tempo de referencia de casi todos estos tests.
    private let reference = 500_000_000.0

    // MARK: - Sin maestro

    /// Sin nadie a quien seguir, el mapa es la identidad: el tiempo musical y el
    /// del reloj son el mismo, que es como se comportaba la app antes.
    func testWithoutAMasterTheMapIsTheIdentity() {
        let map = TempoMap(referenceQuarterNoteNanoseconds: reference)

        for wall: Int64 in [0, 1_000, 123_456_789, 10_000_000_000] {
            XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: wall), wall)
            XCTAssertEqual(map.wallNanoseconds(forGridNanoseconds: wall), wall)
        }
    }

    // MARK: - Seguir un tempo

    /// Un maestro al doble de lento hace que el tiempo musical avance a la
    /// mitad: un segundo de reloj son 500 ms de rejilla.
    func testAHalfSpeedMasterHalvesTheGrid() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 1_000_000_000, atWallNanoseconds: 0)

        XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: 1_000_000_000), 500_000_000)
    }

    /// Y uno al doble de rápido, al revés.
    func testADoubleSpeedMasterDoublesTheGrid() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 250_000_000, atWallNanoseconds: 0)

        XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: 1_000_000_000), 2_000_000_000)
    }

    /// **La propiedad que evita el salto audible.** Cambiar de tempo no mueve el
    /// instante en curso: el mapa se rebasa donde está, y solo cambia la
    /// pendiente a partir de ahí.
    func testChangingTempoDoesNotMoveTheCurrentInstant() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 400_000_000, atWallNanoseconds: 0)

        let wall: Int64 = 3_000_000_000
        let before = map.gridNanoseconds(atWallNanoseconds: wall)

        map.follow(quarterNoteNanoseconds: 900_000_000, atWallNanoseconds: wall)

        XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: wall), before)
    }

    /// Y después del cambio, la pendiente es la nueva.
    func testAfterTheChangeTheNewTempoRules() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 1_000_000_000, atWallNanoseconds: 1_000_000_000)

        let base = map.gridNanoseconds(atWallNanoseconds: 1_000_000_000)
        XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: 3_000_000_000) - base, 1_000_000_000)
    }

    // MARK: - Ida y vuelta

    /// Convertir a tiempo de reloj y volver da lo mismo: el scheduler hace las
    /// dos cosas —mide el horizonte en tiempo musical y sella timestamps en
    /// tiempo de reloj— y una asimetría aquí desplazaría cada evento.
    func testTheMapRoundTrips() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 345_678_901, atWallNanoseconds: 700_000_000)

        for wall: Int64 in [700_000_000, 1_000_000_000, 5_000_000_000] {
            let grid = map.gridNanoseconds(atWallNanoseconds: wall)
            XCTAssertEqual(
                Double(map.wallNanoseconds(forGridNanoseconds: grid)), Double(wall), accuracy: 1)
        }
    }

    // MARK: - Corrección de fase

    /// Retrasar el origen retrasa cuándo cae cada instante musical: el mismo
    /// Step se sella más tarde.
    func testShiftingTheOriginLaterDelaysTheGrid() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        let before = map.wallNanoseconds(forGridNanoseconds: 1_000_000_000)

        map.shiftOrigin(byWallNanoseconds: 3_000_000)

        XCTAssertEqual(map.wallNanoseconds(forGridNanoseconds: 1_000_000_000), before + 3_000_000)
    }

    /// Y adelantarlo, al revés.
    func testShiftingTheOriginEarlierAdvancesTheGrid() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        let before = map.wallNanoseconds(forGridNanoseconds: 1_000_000_000)

        map.shiftOrigin(byWallNanoseconds: -2_000_000)

        XCTAssertEqual(map.wallNanoseconds(forGridNanoseconds: 1_000_000_000), before - 2_000_000)
    }

    /// La corrección se mide en tiempo de reloj aunque el maestro vaya a otro
    /// tempo: son milisegundos de desfase, no fracciones de negra.
    func testTheShiftIsInWallTimeEvenWhenFollowing() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 1_000_000_000, atWallNanoseconds: 0)
        let before = map.wallNanoseconds(forGridNanoseconds: 250_000_000)

        map.shiftOrigin(byWallNanoseconds: 5_000_000)

        XCTAssertEqual(map.wallNanoseconds(forGridNanoseconds: 250_000_000), before + 5_000_000)
    }

    // MARK: - Entradas imposibles

    /// Una negra de duración no positiva no cambia nada: es lo que llegaría de
    /// un maestro roto, y el mapa conserva lo que tenía.
    func testANonPositiveQuarterNoteIsIgnored() {
        var map = TempoMap(referenceQuarterNoteNanoseconds: reference)
        map.follow(quarterNoteNanoseconds: 1_000_000_000, atWallNanoseconds: 0)
        let before = map.gridNanoseconds(atWallNanoseconds: 2_000_000_000)

        map.follow(quarterNoteNanoseconds: 0, atWallNanoseconds: 2_000_000_000)

        XCTAssertEqual(map.gridNanoseconds(atWallNanoseconds: 2_000_000_000), before)
    }

    // MARK: - Reglas de tiempo real

    /// Vive en el hilo del scheduler: no puede llevar nada que asigne.
    func testTheMapIsATrivialType() {
        XCTAssertTrue(_isPOD(TempoMap.self))
    }
}
