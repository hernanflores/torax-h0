import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests del `Project`: dieciséis Banks y dónde se quedó el usuario.
///
/// **Es la raíz del árbol y la única parte del modelo que no es material.**
/// Debajo de él todo es lo que suena; él añade *dónde se estaba mirando* —qué
/// Bank, qué Pattern, qué Track— y los dos ajustes de sesión que sobreviven a
/// cerrar la app: qué reloj manda y a qué hardware se hablaba.
///
/// **Los índices se acotan, no envuelven.** Es el criterio que `Pulses` y `Time`
/// ya siguen: pedir el Bank 20 deja el 16, no el 4. Envolver convertiría un dato
/// corrupto en disco en una selección plausible, que es la peor forma de fallar.
final class ProjectTests: XCTestCase {

    // MARK: - Dieciséis Banks, siempre

    func testAProjectAlwaysHasSixteenBanks() {
        let project = Project()
        XCTAssertEqual(Project.bankCount, 16)
        for index in 0..<Project.bankCount {
            XCTAssertNotNil(project.bank(at: index), "Bank \(index + 1)")
        }
    }

    /// Un Project recién construido está entero vacío: dieciséis Banks de
    /// dieciséis Patterns, los 256 sin material.
    func testAFreshProjectIsEmptyAllTheWayDown() {
        let project = Project()
        for bank in 0..<Project.bankCount {
            XCTAssertEqual(project.bank(at: bank), Bank(), "Bank \(bank + 1)")
        }
    }

    func testAnIndexOutsideTheProjectHasNoBank() {
        let project = Project()
        for index in [-1, -100, Project.bankCount, Project.bankCount + 1, Int.max, Int.min] {
            XCTAssertNil(project.bank(at: index), "\(index)")
        }
    }

    func testReplacingABankChangesOnlyThatOne() {
        let loaded = Bank().replacing(Pattern.initial, at: 0)
        let project = Project().replacing(loaded, at: 7)

        XCTAssertEqual(project.bank(at: 7), loaded)
        for index in 0..<Project.bankCount where index != 7 {
            XCTAssertEqual(project.bank(at: index), Bank(), "Bank \(index + 1)")
        }
    }

    func testReplacingOutsideTheProjectReturnsItUnchanged() {
        let project = Project().replacing(Bank().replacing(Pattern.initial, at: 0), at: 1)
        for index in [-1, Project.bankCount, Int.max] {
            XCTAssertEqual(project.replacing(Bank(), at: index), project, "\(index)")
        }
    }

    // MARK: - Arrancar como arranca hoy

    /// **Meter dos niveles no puede cambiar lo que se oye al abrir la app.**
    ///
    /// Es el mismo requisito que Cycles se puso a sí mismo —«con un Cycle activo
    /// todo suena como hoy»— y aquí se lee: el material de arranque, que es
    /// `Pattern.initial`, está en el Bank 1, Pattern 1, y los 255 restantes están
    /// vacíos. Sin este test, meter Banks es una forma silenciosa de estrenar
    /// otra app.
    func testTheInitialProjectHoldsTodaysMaterialInTheFirstSlot() {
        let project = Project.initial

        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern.initial)

        for bank in 0..<Project.bankCount {
            for pattern in 0..<Bank.patternCount where !(bank == 0 && pattern == 0) {
                XCTAssertEqual(
                    project.bank(at: bank)?.pattern(at: pattern),
                    Pattern(),
                    "Bank \(bank + 1), Pattern \(pattern + 1)"
                )
            }
        }
    }

    /// Y arranca mirando ese primer hueco, no a otro sitio.
    func testTheInitialProjectStartsLookingAtTheFirstSlot() {
        let project = Project.initial
        XCTAssertEqual(project.selectedBank, 0)
        XCTAssertEqual(project.selectedPattern, 0)
        XCTAssertEqual(project.selectedTrack, 0)
    }

    /// El tempo de arranque sigue siendo el de siempre, ahora dicho por el Bank.
    func testTheInitialProjectStillRunsAtOneHundredAndTwenty() {
        XCTAssertEqual(project(Project.initial, bank: 0).tempo, Tempo(beatsPerMinute: 120)!)
    }

    // MARK: - Los índices se acotan y no envuelven

    func testSelectingABankOutsideTheRangeStopsAtTheEdge() {
        XCTAssertEqual(Project().selectingBank(20).selectedBank, Project.bankCount - 1)
        XCTAssertEqual(Project().selectingBank(Int.max).selectedBank, Project.bankCount - 1)
        XCTAssertEqual(Project().selectingBank(-3).selectedBank, 0)
        XCTAssertEqual(Project().selectingBank(Int.min).selectedBank, 0)
    }

    func testSelectingAPatternOutsideTheRangeStopsAtTheEdge() {
        XCTAssertEqual(Project().selectingPattern(99).selectedPattern, Bank.patternCount - 1)
        XCTAssertEqual(Project().selectingPattern(-1).selectedPattern, 0)
    }

    /// El Track se acota contra los **doce** del Pattern, no contra dieciséis.
    /// Es la desviación anotada el 2026-09-02, y aquí también manda.
    func testSelectingATrackStopsAtTheTwelfth() {
        XCTAssertEqual(Project().selectingTrack(15).selectedTrack, Pattern.trackCount - 1)
        XCTAssertEqual(Project().selectingTrack(-1).selectedTrack, 0)
    }

    func testEveryValidIndexIsKeptAsIs() {
        for index in 0..<Project.bankCount {
            XCTAssertEqual(Project().selectingBank(index).selectedBank, index)
        }
        for index in 0..<Bank.patternCount {
            XCTAssertEqual(Project().selectingPattern(index).selectedPattern, index)
        }
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(Project().selectingTrack(index).selectedTrack, index)
        }
    }

    /// Mover un índice no toca los otros dos ni el material.
    func testMovingOneIndexLeavesEverythingElseAlone() {
        let project = Project.initial.selectingBank(3).selectingPattern(9).selectingTrack(5)

        XCTAssertEqual(project.selectedBank, 3)
        XCTAssertEqual(project.selectedPattern, 9)
        XCTAssertEqual(project.selectedTrack, 5)
        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern.initial)
    }

    // MARK: - Los ajustes de sesión

    /// Arranca con reloj interno, que es lo que la app hacía antes de que la
    /// elección existiera.
    func testAFreshProjectFollowsItsOwnClock() {
        XCTAssertEqual(Project().clockSource, .internal)
    }

    func testTheClockSourceIsRemembered() {
        XCTAssertEqual(Project().withClockSource(.external).clockSource, .external)
        XCTAssertEqual(
            Project().withClockSource(.external).withClockSource(.internal).clockSource,
            .internal
        )
    }

    /// **Se guarda el nombre del endpoint, no el endpoint.** Un `MIDIEndpointRef`
    /// es un handle de runtime: no significa nada en el arranque siguiente, y
    /// además es de CoreMIDI, que `Engine` no puede ver.
    func testTheChosenEndpointsAreRememberedByName() {
        let project = Project().remembering(
            destinationNamed: "Elektron Digitakt", sourceNamed: "BeatStep Pro")
        XCTAssertEqual(project.destinationName, "Elektron Digitakt")
        XCTAssertEqual(project.sourceName, "BeatStep Pro")
    }

    /// **No haber elegido es un estado válido**, no un error: es exactamente lo
    /// que ocurre la primera vez que se abre la app.
    func testAFreshProjectRemembersNoEndpoints() {
        XCTAssertNil(Project().destinationName)
        XCTAssertNil(Project().sourceName)
    }

    /// Y olvidarlos también: un endpoint que ya no existe se deja de recordar sin
    /// que eso sea un fallo.
    func testEndpointsCanBeForgotten() {
        let project = Project()
            .remembering(destinationNamed: "Digitakt", sourceNamed: "BeatStep Pro")
            .remembering(destinationNamed: nil, sourceNamed: nil)
        XCTAssertNil(project.destinationName)
        XCTAssertNil(project.sourceName)
    }

    /// Los ajustes de sesión no tocan el material ni los índices.
    func testSessionSettingsLeaveTheMaterialAlone() {
        let project = Project.initial
            .selectingBank(2)
            .withClockSource(.external)
            .remembering(destinationNamed: "Digitakt", sourceNamed: nil)

        XCTAssertEqual(project.bank(at: 0)?.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(project.selectedBank, 2)
    }

    // MARK: - La frontera de tiempo real

    /// El Project tampoco es trivial, por la misma razón que el Bank: no cruza al
    /// hilo del scheduler. Con 256 Patterns dentro, pretenderlo serían ~9,5 MB de
    /// valor moviéndose por la pila.
    func testTheProjectIsNotTrivialEither() {
        XCTAssertFalse(_isPOD(Project.self))
        XCTAssertTrue(_isPOD(Pattern.self), "el Pattern dejó de ser trivial")
    }

    // MARK: - Helper

    private func project(_ project: Project, bank index: Int) -> Bank {
        project.bank(at: index)!
    }
}
