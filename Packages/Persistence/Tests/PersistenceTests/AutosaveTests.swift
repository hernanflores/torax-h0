import Engine
import XCTest

@testable import Persistence

private typealias Pattern = Engine.Pattern

/// Tests del Autosave: escribir el trabajo sin escribir en cada giro de knob.
///
/// **El reloj es una variable del test.** Ningún test espera segundos de verdad:
/// eso sería un test que algún día falla solo en un runner cargado. Se le dice
/// al Autosave qué hora es.
final class AutosaveTests: XCTestCase {

    private var files: InMemoryFileSystem!
    private var store: ProjectStore!
    private var clock: TestClock!
    private var autosave: Autosave!
    private let root = URL(fileURLWithPath: "/torax")

    override func setUp() {
        super.setUp()
        files = InMemoryFileSystem()
        store = ProjectStore(fileSystem: files, directory: root)
        clock = TestClock()
        autosave = Autosave(store: store, quietPeriod: 2, now: clock.now)
    }

    private func bank(_ tempo: Double) -> Bank {
        Bank().replacing(Pattern.initial, at: 0).withTempo(Tempo(beatsPerMinute: tempo)!)
    }

    // MARK: - El debounce

    /// **N cambios seguidos producen una escritura, no N.** Es la razón de ser
    /// del Autosave: un encoder produce decenas de eventos por giro.
    func testManyChangesProduceASingleWrite() throws {
        for value in 100...140 {
            autosave.changed(bank(Double(value)), at: 3)
            clock.advance(0.05)
        }
        XCTAssertEqual(files.writes.count, 0, "escribió antes de la calma")

        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 3)), 1)
    }

    /// Y lo que se escribe es **el último estado**, no el primero ni una mezcla.
    func testWhatIsWrittenIsTheLastState() throws {
        autosave.changed(bank(100), at: 0)
        clock.advance(0.1)
        autosave.changed(bank(174), at: 0)

        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(try store.loadBank(at: 0)?.tempo, Tempo(beatsPerMinute: 174)!)
    }

    /// **Mientras siga habiendo movimiento no se escribe.** Cada cambio empuja
    /// la calma hacia delante.
    func testMovementKeepsPushingTheQuietPeriodForward() throws {
        autosave.changed(bank(100), at: 0)

        for _ in 0..<20 {
            clock.advance(1.5)
            try autosave.tick()
            autosave.changed(bank(120), at: 0)
        }

        XCTAssertEqual(files.writes.count, 0, "escribió a mitad de un giro largo")
    }

    /// Sin nada pendiente, mirar no escribe.
    func testTickingWithNothingPendingWritesNothing() throws {
        clock.advance(100)
        try autosave.tick()
        XCTAssertEqual(files.writes.count, 0)
    }

    /// **Se escribe solo el Bank tocado.** Es lo que hace barato el Autosave:
    /// 15,5 ms en vez de los 243,6 que costaría el Project entero.
    func testOnlyTheTouchedBankIsWritten() throws {
        autosave.changed(bank(100), at: 5)
        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(files.writes, [store.bankURL(at: 5).path])
    }

    /// Varios Banks tocados se escriben todos, cada uno una vez.
    func testSeveralTouchedBanksAreEachWrittenOnce() throws {
        autosave.changed(bank(100), at: 1)
        autosave.changed(bank(110), at: 1)
        autosave.changed(bank(120), at: 7)

        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(files.writes.count, 2)
        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 1)), 1)
        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 7)), 1)
    }

    /// Después de escribir, no queda nada pendiente: el ciclo siguiente empieza
    /// limpio.
    func testAfterWritingNothingIsPending() throws {
        autosave.changed(bank(100), at: 0)
        clock.advance(2)
        try autosave.tick()

        XCTAssertFalse(autosave.hasPendingWork)

        clock.advance(100)
        try autosave.tick()
        XCTAssertEqual(files.writes.count, 1, "volvió a escribir lo mismo")
    }

    // MARK: - Forzar la escritura pendiente

    /// **Al pasar a segundo plano no hay tiempo de esperar la calma**, y lo que
    /// no se escriba se pierde (FR14).
    func testFlushWritesImmediatelyWithoutWaiting() throws {
        autosave.changed(bank(100), at: 2)

        try autosave.flush()

        XCTAssertEqual(files.writeCount(for: store.bankURL(at: 2)), 1)
        XCTAssertFalse(autosave.hasPendingWork)
    }

    /// Forzar sin nada pendiente no escribe.
    func testFlushingWithNothingPendingWritesNothing() throws {
        try autosave.flush()
        XCTAssertEqual(files.writes.count, 0)
    }

    /// **Si falla, lo pendiente se conserva.** Un disco lleno no puede además
    /// borrar de memoria lo que no se pudo guardar: el intento siguiente tiene
    /// que poder reintentarlo.
    func testAFailedFlushKeepsTheWorkPending() {
        autosave.changed(bank(100), at: 0)
        files.failEveryWrite = CocoaError(.fileWriteOutOfSpace)

        XCTAssertThrowsError(try autosave.flush())

        XCTAssertTrue(autosave.hasPendingWork, "se perdió el trabajo que no se pudo escribir")
    }

    /// Y cuando el disco vuelve, se escribe lo que quedó.
    func testTheWorkIsWrittenOnceTheDiskComesBack() throws {
        autosave.changed(bank(174), at: 0)
        files.failEveryWrite = CocoaError(.fileWriteOutOfSpace)
        try? autosave.flush()

        files.failEveryWrite = nil
        try autosave.flush()

        XCTAssertEqual(try store.loadBank(at: 0)?.tempo, Tempo(beatsPerMinute: 174)!)
    }

    // MARK: - La cabecera

    /// Los ajustes de sesión pasan por el mismo debounce.
    func testHeaderChangesGoThroughTheSameDebounce() throws {
        autosave.changedHeader(Project.initial.selectingBank(4))
        XCTAssertEqual(files.writes.count, 0)

        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(store.load().project.selectedBank, 4)
    }

    /// Un cambio de cabecera **no reescribe los Banks**. Cambiar de pestaña no
    /// es motivo para escribir 9 MB.
    func testAHeaderChangeDoesNotRewriteTheBanks() throws {
        autosave.changedHeader(Project.initial.selectingBank(1))
        clock.advance(2)
        try autosave.tick()

        XCTAssertEqual(files.writes, [store.projectURL.path])
    }
}
