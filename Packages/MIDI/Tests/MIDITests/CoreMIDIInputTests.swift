import CoreMIDI
import XCTest
@testable import MIDI

/// Tests de la entrada por CoreMIDI.
///
/// Crean clientes reales, así que corren en la mitad de la suite que la CI
/// aísla en su propio proceso (ver `workflow.md`).
final class CoreMIDIInputTests: XCTestCase {

    private func makeInput(_ name: String) throws -> CoreMIDIInput {
        try CoreMIDIInput(clientName: name) { _, _ in }
    }

    func testInputStartsOpen() throws {
        let input = try makeInput("Torax H-0 Test Input Open")
        defer { input.close() }
        XCTAssertFalse(input.isClosed)
    }

    func testClosingIsIdempotent() throws {
        let input = try makeInput("Torax H-0 Test Input Idempotent")
        input.close()
        input.close()
        input.close()
        XCTAssertTrue(input.isClosed)
    }

    /// Enumerar no falla aunque no haya nada conectado: sin fuentes es un estado
    /// válido, no un error.
    func testEnumeratingSourcesWithNothingConnectedIsValid() throws {
        let input = try makeInput("Torax H-0 Test Input Sources")
        defer { input.close() }
        XCTAssertNoThrow(input.availableSources())
    }

    /// Tras cerrar no se enumera ni se conecta: los handles ya no existen.
    func testAfterClosingThereIsNothingToConnectTo() throws {
        let input = try makeInput("Torax H-0 Test Input Closed")
        input.close()

        XCTAssertTrue(input.availableSources().isEmpty)
        XCTAssertFalse(input.connect(to: MIDIEndpointRef(0)))
    }

    /// Desconectar sin haber conectado no hace nada ni revienta.
    func testDisconnectingWithoutConnectingIsHarmless() throws {
        let input = try makeInput("Torax H-0 Test Input Disconnect")
        defer { input.close() }
        input.disconnect()
        input.disconnect()
    }

    /// Cerrar también corta el aviso de cambios.
    func testClosingStopsSetupChangeNotifications() throws {
        let input = try makeInput("Torax H-0 Test Input Notifications")
        input.onSetupChanged = { XCTFail("llegó una notificación tras cerrar") }
        input.close()
        XCTAssertNil(input.onSetupChanged)
    }

    /// **La comprobación que importa para este track:** crear y cerrar entradas
    /// en orden, muchas veces, no puede inutilizar la creación de clientes del
    /// proceso. Es el fallo que `midi-test-flake_20260826` persigue, y este
    /// track añade un segundo cliente de CoreMIDI a la app.
    func testRepeatedOrderedTeardownKeepsTheProcessAbleToCreateClients() throws {
        for index in 0..<15 {
            let input = try makeInput("Torax H-0 Test Input Cycle \(index)")
            input.close()
        }
        let survivor = try makeInput("Torax H-0 Test Input Survivor")
        defer { survivor.close() }
        XCTAssertFalse(survivor.isClosed)
    }
}
