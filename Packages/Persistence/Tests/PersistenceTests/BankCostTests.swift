import Engine
import XCTest

@testable import Persistence

private typealias Pattern = Engine.Pattern

/// Cuánto ocupa y cuánto cuesta guardar un Bank (NFR3).
///
/// **Se mide antes de construir encima**, que es el criterio que
/// `cycles_20260901` estableció: el Autosave de la Fase 5 va a llamar a esto
/// cada pocos segundos, y decidir su cadencia sin saber lo que cuesta una
/// escritura sería elegir a ciegas.
///
/// **Presupuesto: por debajo de 100 ms por Bank**, y la medición que decide es
/// la de dispositivo, en la Fase 8. Ésta es la línea base en host.
final class BankCostTests: XCTestCase {

    /// Un Bank lleno de verdad: dieciséis Patterns con material en los doce
    /// Tracks, y cada Track con sus dieciséis Cycles.
    private func fullBank() -> Bank {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Cycle(
                    shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
                    pool: PitchPool().inserting(Pitch(48 + index)!).inserting(Pitch(60)!),
                    channel: Channel(index + 1)!
                ),
                at: index
            )
        }

        var bank = Bank()
        for index in 0..<Bank.patternCount {
            bank = bank.replacing(pattern, at: index)
        }
        return bank
    }

    /// **El número que el plan pide anotar.** Un Bank lleno ronda los cientos de
    /// KB; lo que se afirma es el orden, no el dígito, para que el test no falle
    /// cada vez que se añada un campo.
    func testAFullBankFitsInTheExpectedOrderOfMagnitude() throws {
        let data = try JSONEncoder().encode(BankRecord(fullBank()))
        let kilobytes = data.count / 1024

        XCTAssertGreaterThan(
            kilobytes, 100, "un Bank lleno son \(kilobytes) KB: menos de lo esperado")
        XCTAssertLessThan(kilobytes, 2_048, "un Bank lleno son \(kilobytes) KB: se disparó")
        print("Bank lleno: \(data.count) bytes (\(kilobytes) KB)")
    }

    /// Y un Bank vacío sigue siendo minúsculo, que es lo que la marca de la Fase
    /// 3 compró.
    func testAnEmptyBankStaysTiny() throws {
        let data = try JSONEncoder().encode(BankRecord(Bank()))
        XCTAssertLessThan(data.count, 1_024, "un Bank vacío son \(data.count) bytes")
        print("Bank vacío: \(data.count) bytes")
    }

    /// **Serializar y escribir un Bank lleno, medido.** Contra el sistema de
    /// ficheros en memoria, así que lo que mide es la serialización: el coste de
    /// disco real se mide en dispositivo (Fase 8), que es donde el presupuesto de
    /// 100 ms se decide.
    func testSavingAFullBankIsFastEnoughToBeMeasured() {
        let files = InMemoryFileSystem()
        let store = ProjectStore(fileSystem: files, directory: URL(fileURLWithPath: "/torax"))
        let bank = fullBank()

        let start = DispatchTime.now().uptimeNanoseconds
        try? store.save(bank, at: 0)
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        print("Guardar un Bank lleno: \(String(format: "%.1f", milliseconds)) ms (en memoria)")
        XCTAssertLessThan(
            milliseconds, 100,
            "serializar un Bank lleno costó \(milliseconds) ms, y el presupuesto entero son 100"
        )
    }

    /// Guardar el Project entero es dieciséis veces eso, y por eso **el Autosave
    /// no lo hace**: escribe solo el Bank tocado (FR14).
    func testSavingTheWholeProjectIsWhatTheAutosaveAvoids() {
        let files = InMemoryFileSystem()
        let store = ProjectStore(fileSystem: files, directory: URL(fileURLWithPath: "/torax"))

        var project = Project()
        for index in 0..<Project.bankCount {
            project = project.replacing(fullBank(), at: index)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        try? store.save(project)
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        print("Guardar el Project entero: \(String(format: "%.1f", milliseconds)) ms (en memoria)")
        XCTAssertEqual(files.writes.count, Project.bankCount + 1)
    }
}
