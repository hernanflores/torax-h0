import CoreMIDI
import XCTest
@testable import MIDI

/// Tests del cierre explícito de `CoreMIDIOutput`.
///
/// **Por qué hace falta.** Hasta ahora los recursos de CoreMIDI se destruían en
/// `deinit`, es decir, en el instante en que ARC decidiera liberar el objeto.
/// Ese instante puede caer dentro de la ventana en la que CoreMIDI todavía está
/// emitiendo eventos ya sellados con timestamp futuro, y destruir el puerto ahí
/// inutiliza la conexión MIDI del proceso: las siguientes llamadas a
/// `MIDIClientCreateWithBlock` devuelven `paramErr`.
///
/// El cierre explícito devuelve ese momento a quien sí sabe cuándo es seguro.
final class CoreMIDIOutputCloseTests: XCTestCase {

    func testClosingIsIdempotent() throws {
        let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Close")
        output.close()
        output.close()
        output.close()
        XCTAssertTrue(output.isClosed)
    }

    func testOutputStartsOpen() throws {
        let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Open")
        defer { output.close() }
        XCTAssertFalse(output.isClosed)
    }

    /// Enviar tras cerrar es un **estado esperado**, no un error: el destino ya
    /// no existe, igual que cuando se desenchufa el cable.
    func testSendingAfterCloseReportsAnUnavailableDestination() throws {
        let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Send After Close")
        output.close()

        let result = output.send(
            .noteOn(channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(64)!),
            to: MIDIEndpointRef(0),
            atHostTime: 0
        )
        XCTAssertEqual(result, .destinationUnavailable)
    }

    /// `deinit` sigue siendo red de seguridad: liberar un objeto ya cerrado no
    /// puede volver a destruir nada.
    func testDeinitAfterCloseDoesNotDisposeTwice() throws {
        for _ in 0..<20 {
            let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Deinit")
            output.close()
        }
        // Si el doble desmontaje rompiera la conexión del proceso, crear un
        // cliente nuevo aquí fallaría.
        let survivor = try CoreMIDIOutput(clientName: "Torax H-0 Test Survivor")
        defer { survivor.close() }
        XCTAssertFalse(survivor.isClosed)
    }

    /// Cerrar también desconecta el aviso de cambios: no pueden llegar
    /// notificaciones sobre una salida que ya no existe.
    func testClosingStopsSetupChangeNotifications() throws {
        let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Notifications")
        output.onSetupChanged = { XCTFail("llegó una notificación tras cerrar") }
        output.close()
        XCTAssertNil(output.onSetupChanged)
    }
}
