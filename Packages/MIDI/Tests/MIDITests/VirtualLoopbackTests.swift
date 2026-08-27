import CoreMIDI
import XCTest
@testable import MIDI

/// Tests del loopback virtual.
///
/// Es la primera vez en el proyecto que se mide algo real: se envía con
/// timestamp futuro y se comprueba cuándo llega de verdad. Estos tests corren en
/// macOS; el veredicto del track exige repetirlo en el iPad, que es otra
/// máquina con otro planificador.
final class VirtualLoopbackTests: XCTestCase {

    func testLoopbackPublishesAnEndpoint() throws {
        let loopback = try VirtualLoopback(name: "ToraxH0 Loopback Test") { _, _ in }
        XCTAssertNotEqual(loopback.endpoint, 0)
    }

    /// El mensaje enviado al endpoint virtual debe llegar de vuelta.
    func testMessageSentToTheVirtualEndpointIsReceived() throws {
        let received = expectation(description: "mensaje recibido")
        let loopback = try VirtualLoopback(name: "ToraxH0 Loopback Recv") { _, _ in
            received.fulfill()
        }
        let output = try CoreMIDIOutput(clientName: "ToraxH0 Loopback Sender")

        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(100)!
        )
        let target = HostClock.now() + HostClock.hostTicks(fromNanoseconds: 20_000_000)
        XCTAssertEqual(output.send(message, to: loopback.endpoint, atHostTime: target), .sent)

        wait(for: [received], timeout: 5)
    }

    /// El timestamp que llega en el paquete debe ser el que se programó: es la
    /// referencia contra la que se mide la desviación real de entrega.
    func testReceivedTimestampMatchesTheScheduledOne() throws {
        let received = expectation(description: "mensaje recibido")
        // El handler corre en el hilo de CoreMIDI, así que el resultado cruza
        // hilos: se recoge en un contador atómico, no en una variable capturada.
        let scheduledSeen = AtomicCounter()

        let loopback = try VirtualLoopback(name: "ToraxH0 Loopback TS") { scheduled, _ in
            scheduledSeen.value = scheduled
            received.fulfill()
        }
        let output = try CoreMIDIOutput(clientName: "ToraxH0 Loopback TS Sender")

        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(64)!, velocity: MIDIVelocity(64)!
        )
        let target = HostClock.now() + HostClock.hostTicks(fromNanoseconds: 30_000_000)
        _ = output.send(message, to: loopback.endpoint, atHostTime: target)

        wait(for: [received], timeout: 5)
        XCTAssertEqual(scheduledSeen.value, target)
    }

    /// Un evento programado en el futuro no puede entregarse antes de tiempo.
    ///
    /// Es la propiedad que sostiene toda la arquitectura: si CoreMIDI no
    /// respetara el timestamp, el look-ahead scheduling no serviría de nada.
    func testFutureEventIsNotDeliveredEarly() throws {
        let received = expectation(description: "mensaje recibido")
        // Se guarda el patrón de bits del Int64 con signo en el contador
        // atómico: cruza hilos sin capturas mutables.
        let deltaBits = AtomicCounter()

        let loopback = try VirtualLoopback(name: "Torax H0 Loopback Early") { scheduled, actual in
            let delta = Int64(HostClock.nanoseconds(fromHostTicks: actual))
                - Int64(HostClock.nanoseconds(fromHostTicks: scheduled))
            deltaBits.value = UInt64(bitPattern: delta)
            received.fulfill()
        }
        let output = try CoreMIDIOutput(clientName: "ToraxH0 Loopback Early Sender")

        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(1)!, note: MIDINote(60)!, velocity: MIDIVelocity(100)!
        )
        let target = HostClock.now() + HostClock.hostTicks(fromNanoseconds: 100_000_000)
        _ = output.send(message, to: loopback.endpoint, atHostTime: target)

        wait(for: [received], timeout: 5)
        let deltaNanoseconds = Int64(bitPattern: deltaBits.value)
        // Margen generoso: aquí solo se comprueba que no llega ANTES, no la
        // precisión. Medir precisión es trabajo del arnés, en el iPad.
        XCTAssertGreaterThan(deltaNanoseconds, -1_000_000,
                             "El evento se entrego mas de 1 ms antes de su timestamp")
    }
}
