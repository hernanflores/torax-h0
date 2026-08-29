import CoreMIDI
import XCTest
@testable import MIDI

/// Tests de la capa CoreMIDI que sí se pueden ejecutar en host.
///
/// CoreMIDI existe en macOS igual que en iPadOS, así que crear el cliente,
/// enumerar destinos y liberar recursos se puede verificar aquí. Lo que no se
/// puede verificar sin hardware es la **precisión de entrega**: eso es
/// exactamente lo que mide el arnés de jitter en el iPad, y por eso el track
/// existe.
final class CoreMIDIOutputTests: XCTestCase {

    func testClientCreationSucceeds() throws {
        XCTAssertNoThrow(try CoreMIDIOutput(clientName: "ToraxH0Tests"))
    }

    func testDestinationsCanBeEnumerated() throws {
        let output = try CoreMIDIOutput(clientName: "ToraxH0Tests")
        let destinations = output.availableDestinations()

        // La lista puede estar vacía —una máquina sin nada conectado es un caso
        // legítimo— pero la enumeración no puede fallar ni devolver basura.
        for destination in destinations {
            XCTAssertNotEqual(destination.endpoint, 0)
            XCTAssertFalse(destination.displayName.isEmpty)
        }
    }

    func testEachDestinationHasADistinctEndpoint() throws {
        let output = try CoreMIDIOutput(clientName: "ToraxH0Tests")
        let endpoints = output.availableDestinations().map(\.endpoint)
        XCTAssertEqual(Set(endpoints).count, endpoints.count)
    }

    /// Documenta un comportamiento de CoreMIDI que contradice la intuición:
    /// **enviar a un endpoint inexistente no falla**.
    ///
    /// CoreMIDI acepta el mensaje y lo descarta en silencio, sin validar el
    /// destino de forma síncrona. La consecuencia de diseño es importante: el
    /// resultado del envío NO sirve para detectar que un dispositivo se
    /// desconectó. Para eso está `onSetupChanged`.
    ///
    /// El test existe para que, si algún día CoreMIDI cambia de criterio, nos
    /// enteremos por un fallo de test y no por un bug en el escenario.
    func testSendingToAnInvalidEndpointIsSilentlyAccepted() throws {
        let output = try CoreMIDIOutput(clientName: "ToraxH0Tests")
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(100)!
        )

        let result = output.send(message, to: MIDIEndpointRef(0), atHostTime: HostClock.now())
        XCTAssertEqual(
            result, .sent,
            "CoreMIDI acepta envios a endpoints invalidos sin reportar error")
    }

    func testSetupChangeCallbackCanBeRegistered() throws {
        let output = try CoreMIDIOutput(clientName: "ToraxH0Tests")
        XCTAssertNil(output.onSetupChanged)

        output.onSetupChanged = {}
        XCTAssertNotNil(output.onSetupChanged)
    }

    /// Si hay algún destino real disponible, se comprueba que el envío con
    /// timestamp futuro se acepta. No mide precisión: solo que la llamada pasa.
    func testSendingToARealDestinationIsAccepted() throws {
        let output = try CoreMIDIOutput(clientName: "ToraxH0Tests")
        guard let destination = output.availableDestinations().first else {
            throw XCTSkip("No hay destinos MIDI en esta máquina")
        }

        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(1)!
        )
        let future = HostClock.now() + HostClock.hostTicks(fromNanoseconds: 50_000_000)

        XCTAssertEqual(output.send(message, to: destination.endpoint, atHostTime: future), .sent)
    }
}
