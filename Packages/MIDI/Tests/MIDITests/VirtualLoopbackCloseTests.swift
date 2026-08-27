import CoreMIDI
import XCTest
@testable import MIDI

/// Tests del cierre explícito de `VirtualLoopback`.
///
/// El endpoint virtual del arnés es el recurso cuyo desmontaje descontrolado
/// rompe la conexión MIDI del proceso. Cerrarlo cuando lo decide quien mide, y
/// no cuando ARC libera un local, es la mitad del track.
final class VirtualLoopbackCloseTests: XCTestCase {

    private func makeLoopback(
        _ name: String,
        onReceive handler: @escaping VirtualLoopback.ReceiveHandler = { _, _ in }
    ) throws -> VirtualLoopback {
        try VirtualLoopback(name: name, onReceive: handler)
    }

    func testLoopbackStartsOpen() throws {
        let loopback = try makeLoopback("Torax H-0 Test Loopback Open")
        defer { loopback.close() }
        XCTAssertFalse(loopback.isClosed)
    }

    func testClosingIsIdempotent() throws {
        let loopback = try makeLoopback("Torax H-0 Test Loopback Idempotent")
        loopback.close()
        loopback.close()
        loopback.close()
        XCTAssertTrue(loopback.isClosed)
    }

    /// Tras cerrar no pueden llegar callbacks: la guarda se comprueba dentro del
    /// propio callback, antes de tocar nada, porque CoreMIDI puede tener una
    /// entrega ya en vuelo cuando se cierra.
    func testNoCallbackArrivesAfterClosing() throws {
        let received = AtomicCounter()
        let loopback = try makeLoopback("Torax H-0 Test Loopback Silent") { _, _ in
            received.increment()
        }
        let endpoint = loopback.endpoint
        loopback.close()

        // Se intenta enviar por una salida distinta al endpoint ya destruido.
        let output = try CoreMIDIOutput(clientName: "Torax H-0 Test Loopback Sender")
        defer { output.close() }
        output.send(
            .noteOn(channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(64)!),
            to: endpoint,
            atHostTime: 0
        )
        usleep(100_000)

        XCTAssertEqual(received.value, 0, "llegó un callback tras cerrar el loopback")
    }

    /// Crear y cerrar en orden muchas veces no puede inutilizar la conexión MIDI
    /// del proceso — que es exactamente el fallo que este track persigue.
    func testRepeatedOrderedTeardownKeepsTheProcessAbleToCreateClients() throws {
        for index in 0..<15 {
            let loopback = try makeLoopback("Torax H-0 Test Loopback Cycle \(index)")
            loopback.close()
        }
        let survivor = try makeLoopback("Torax H-0 Test Loopback Survivor")
        defer { survivor.close() }
        XCTAssertFalse(survivor.isClosed)
    }
}
