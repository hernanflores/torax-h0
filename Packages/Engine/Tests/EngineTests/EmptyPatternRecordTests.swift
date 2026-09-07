import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de que un Pattern vacío no se escriba como 37 KB de ceros.
///
/// **Sin esto, un Bank recién creado ocupa lo mismo que uno lleno.** Los
/// dieciséis Patterns existen siempre —es lo que hace que elegir uno no pueda
/// fallar— y cada uno son doce Tracks por dieciséis Cycles: 192 Cycles de
/// quince campos cada uno, todos en su valor por defecto. Multiplicado por
/// dieciséis Patterns y por dieciséis Banks, el disco se llenaría de nada.
///
/// La marca es `null`. No hace falta inventar un centinela: el formato ya tiene
/// una forma de decir «aquí no hay nada», y un hueco `null` se lee con los ojos
/// igual de bien que se lee un objeto.
final class EmptyPatternRecordTests: XCTestCase {

    /// **Órdenes de magnitud**, no un porcentaje. Es el criterio del plan y es
    /// el que separa «comprime bien» de «no se escribe».
    func testAnEmptyBankIsOrdersOfMagnitudeSmallerThanAFullOne() throws {
        var full = Bank()
        for index in 0..<Bank.patternCount {
            full = full.replacing(Pattern.initial, at: index)
        }

        let empty = try size(of: BankRecord(Bank()))
        let loaded = try size(of: BankRecord(full))

        XCTAssertLessThan(
            empty * 100, loaded,
            "un Bank vacío ocupa \(empty) bytes y uno lleno \(loaded): no son órdenes de magnitud"
        )
    }

    /// Y sigue volviendo entero: dieciséis Patterns vacíos, no quince ni
    /// diecisiete.
    func testAnEmptyBankComesBackWithItsSixteenEmptyPatterns() {
        let returned = BankRecord(Bank()).bank

        XCTAssertEqual(returned, Bank())
        for index in 0..<Bank.patternCount {
            XCTAssertEqual(returned.pattern(at: index), Pattern(), "Pattern \(index + 1)")
        }
    }

    /// **Los huecos vacíos no desplazan a los llenos.** Es el riesgo real de
    /// colapsar: que el Pattern 10 vuelva en la posición 2 porque los nueve
    /// anteriores no se escribieron. La marca ocupa su sitio en la lista.
    func testAnEmptySlotKeepsItsPositionInTheBank() {
        let bank = Bank().replacing(Pattern.initial, at: 9)
        let returned = BankRecord(bank).bank

        XCTAssertEqual(returned.pattern(at: 9), Pattern.initial)
        for index in 0..<Bank.patternCount where index != 9 {
            XCTAssertEqual(returned.pattern(at: index), Pattern(), "Pattern \(index + 1)")
        }
    }

    /// La marca es `null` en la lista de patterns, y se ve.
    func testAnEmptyPatternIsWrittenAsNull() throws {
        let bank = Bank().replacing(Pattern.initial, at: 1)
        let data = try JSONEncoder().encode(BankRecord(bank))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let patterns = try XCTUnwrap(json["patterns"] as? [Any])

        XCTAssertEqual(patterns.count, Bank.patternCount)
        XCTAssertTrue(patterns[0] is NSNull, "el hueco vacío no es null")
        XCTAssertFalse(patterns[1] is NSNull, "el hueco con material se escribió como null")
    }

    /// Un Pattern **casi** vacío —una sola altura en un solo Track— no es vacío
    /// y se escribe entero. La marca es para lo que no existe, no para lo que
    /// tiene poco.
    func testAPatternWithASinglePitchIsNotEmpty() throws {
        let bank = Bank().replacing(Pattern.initial, at: 0)
        let data = try JSONEncoder().encode(BankRecord(bank))
        let patterns = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: data) as? [String: Any])?["patterns"] as? [Any]
        )

        XCTAssertFalse(patterns[0] is NSNull)
    }

    /// Un Project entero vacío también colapsa: dieciséis Banks de dieciséis
    /// huecos es donde el ahorro se nota de verdad.
    func testAnEmptyProjectIsSmall() throws {
        let size = try size(of: ProjectRecord(Project()))
        XCTAssertLessThan(size, 4_096, "un Project vacío ocupa \(size) bytes")
    }

    /// Y el Project de arranque sigue teniendo su material donde debe.
    func testTheInitialProjectSurvivesTheCollapse() {
        let returned = ProjectRecord(Project.initial).project(with: banks(of: Project.initial))
        XCTAssertEqual(returned.bank(at: 0)?.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(returned, Project.initial)
    }

    // MARK: - Helper

    private func size(of record: some Encodable) throws -> Int {
        try JSONEncoder().encode(record).count
    }

    /// Los dieciséis Banks de un Project, que es lo que la cabecera necesita
    /// para reconstruirlo: en disco viven en ficheros aparte (FR18).
    private func banks(of project: Project) -> [Bank] {
        (0..<Project.bankCount).compactMap { project.bank(at: $0) }
    }
}
