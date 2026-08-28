import XCTest
@testable import MIDI

/// Tests de la selección de **fuentes** de entrada.
///
/// La lógica es la misma que la de destinos —enumerar, elegir, conservar la
/// elección al refrescar, caer a `nil` sin nada— así que se comparte. Lo que
/// cambia entre una y otra es el papel: qué endpoints son elegibles y cómo se
/// dice que no hay ninguno.
final class MIDISourceSelectionTests: XCTestCase {

    private func endpoint(_ id: UInt32, _ name: String) -> MIDIEndpointInfo {
        MIDIEndpointInfo(endpoint: id, displayName: name)
    }

    private var beatStep: MIDIEndpointInfo { endpoint(1, "Arturia BeatStep Pro") }
    private var keyboard: MIDIEndpointInfo { endpoint(2, "Keystep") }
    private var loopback: MIDIEndpointInfo { endpoint(9, VirtualLoopback.defaultName) }

    // MARK: - Sin controlador es un estado válido

    /// `product-guidelines.md`: sin controlador conectado la app es de solo
    /// lectura y transporte. Eso no es un error, es un modo de uso.
    func testNoSourcesIsAValidState() {
        let selection = MIDIEndpointSelection(.source)
        XCTAssertTrue(selection.available.isEmpty)
        XCTAssertFalse(selection.hasEndpoint)
        XCTAssertEqual(selection.statusDescription, "No MIDI input")
    }

    func testStatusShowsTheSourceNameWhenConnected() {
        let selection = MIDIEndpointSelection(.source, discovering: [beatStep])
        XCTAssertEqual(selection.statusDescription, "Arturia BeatStep Pro")
    }

    /// Ni lenguaje de error ni de disculpa, igual que en la salida.
    func testStatusNeverApologises() {
        let forbidden = ["error", "fail", "sorry", "unable", "could not", "problem", "!"]
        for status in [
            MIDIEndpointSelection(.source).statusDescription,
            MIDIEndpointSelection(.source, discovering: [beatStep]).statusDescription,
        ] {
            for word in forbidden {
                XCTAssertFalse(status.lowercased().contains(word), "«\(status)» dice «\(word)»")
            }
        }
    }

    // MARK: - Selección

    func testFirstSourceIsSelectedAutomatically() {
        XCTAssertEqual(
            MIDIEndpointSelection(.source, discovering: [beatStep, keyboard]).selected,
            beatStep
        )
    }

    func testRefreshingKeepsTheCurrentSelection() {
        let selection = MIDIEndpointSelection(.source, discovering: [beatStep, keyboard])
            .selecting(keyboard)
            .refreshed(with: [keyboard, beatStep])
        XCTAssertEqual(selection.selected, keyboard)
    }

    func testLosingTheSelectedSourceFallsBackToTheRemainingOne() {
        let selection = MIDIEndpointSelection(.source, discovering: [beatStep, keyboard])
            .refreshed(with: [keyboard])
        XCTAssertEqual(selection.selected, keyboard)
    }

    // MARK: - Lo que distingue a una fuente de un destino

    /// El endpoint del arnés de medición es un **destino** virtual, no una
    /// fuente: no tiene por qué excluirse de la lista de entradas, porque nunca
    /// aparece en ella.
    func testTheMeasurementEndpointIsEligibleAsASourceBecauseItNeverIsOne() {
        let selection = MIDIEndpointSelection(.source, discovering: [loopback])
        XCTAssertEqual(selection.available, [loopback])
    }

    /// Como destino, en cambio, se sigue excluyendo.
    func testTheMeasurementEndpointIsStillExcludedFromDestinations() {
        let selection = MIDIEndpointSelection(.destination, discovering: [loopback])
        XCTAssertTrue(selection.available.isEmpty)
        XCTAssertEqual(selection.statusDescription, "No MIDI device")
    }

    /// El papel viaja con la selección: dos selecciones con el mismo contenido
    /// pero distinto papel no son la misma cosa.
    func testRoleIsPartOfTheValue() {
        XCTAssertNotEqual(
            MIDIEndpointSelection(.source, discovering: [beatStep]),
            MIDIEndpointSelection(.destination, discovering: [beatStep])
        )
    }
}
