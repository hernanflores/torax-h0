import XCTest
@testable import MIDI

/// Tests de la reconsulta de destinos ante un cambio del sistema.
///
/// La desconexión **no se detecta por el resultado del envío**: está medido que
/// CoreMIDI acepta el mensaje para un endpoint inexistente y lo descarta en
/// silencio (ver `MIDISendResult.classify`). El único mecanismo fiable es la
/// notificación `onSetupChanged`, y lo que este tipo garantiza es que esa
/// notificación acaba en una reconsulta.
final class MIDIEndpointWatcherTests: XCTestCase {

    private func destination(_ id: UInt32, _ name: String) -> MIDIEndpointInfo {
        MIDIEndpointInfo(endpoint: id, displayName: name)
    }

    private var synth: MIDIEndpointInfo { destination(1, "Prophet Rev2") }
    private var drums: MIDIEndpointInfo { destination(2, "Digitakt") }

    /// Enumerador que el test controla, en lugar del sistema.
    private final class FakeSystem: @unchecked Sendable {
        var destinations: [MIDIEndpointInfo] = []
        private(set) var queryCount = 0

        func enumerate() -> [MIDIEndpointInfo] {
            queryCount += 1
            return destinations
        }
    }

    /// Entrega síncrona: en producto el salto es al hilo principal, porque la
    /// notificación llega desde el hilo de CoreMIDI.
    private func makeWatcher(_ system: FakeSystem) -> MIDIEndpointWatcher {
        MIDIEndpointWatcher(
            .destination,
            enumerating: system.enumerate,
            delivering: { work in work() }
        )
    }

    // MARK: - La notificación provoca reconsulta

    func testSetupChangeTriggersAFreshQuery() {
        let system = FakeSystem()
        system.destinations = [synth]
        let watcher = makeWatcher(system)

        let queriesAfterInit = system.queryCount
        watcher.setupChanged()
        XCTAssertEqual(system.queryCount, queriesAfterInit + 1)
    }

    func testDestinationAppearingIsPickedUp() {
        let system = FakeSystem()
        let watcher = makeWatcher(system)
        XCTAssertFalse(watcher.selection.hasEndpoint)

        system.destinations = [synth]
        watcher.setupChanged()

        XCTAssertEqual(watcher.selection.selected, synth)
    }

    /// El caso del track: desenchufar el cable a media reproducción.
    func testDestinationDisappearingFallsBackToNoDevice() {
        let system = FakeSystem()
        system.destinations = [synth]
        let watcher = makeWatcher(system)
        XCTAssertEqual(watcher.selection.selected, synth)

        system.destinations = []
        watcher.setupChanged()

        XCTAssertNil(watcher.selection.selected)
        XCTAssertFalse(watcher.selection.hasEndpoint)
    }

    /// Desaparecer uno de dos no deja al usuario sin salida: se cae al que queda.
    func testLosingTheSelectedDestinationFallsBackToTheRemainingOne() {
        let system = FakeSystem()
        system.destinations = [synth, drums]
        let watcher = makeWatcher(system)
        XCTAssertEqual(watcher.selection.selected, synth)

        system.destinations = [drums]
        watcher.setupChanged()

        XCTAssertEqual(watcher.selection.selected, drums)
    }

    /// Volver a enchufar lo devuelve al estado con destino, sin reiniciar nada.
    func testReconnectingRecoversWithoutRestart() {
        let system = FakeSystem()
        system.destinations = [synth]
        let watcher = makeWatcher(system)

        system.destinations = []
        watcher.setupChanged()
        XCTAssertFalse(watcher.selection.hasEndpoint)

        system.destinations = [synth]
        watcher.setupChanged()
        XCTAssertEqual(watcher.selection.selected, synth)
    }

    // MARK: - Aviso de cambio

    func testObserverIsNotifiedOnChange() {
        let system = FakeSystem()
        let watcher = makeWatcher(system)

        var observed: [MIDIEndpointSelection] = []
        watcher.onChange = { observed.append($0) }

        system.destinations = [synth]
        watcher.setupChanged()

        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed.last?.selected, synth)
    }

    /// Una notificación que no cambia nada no debe agitar la interfaz: CoreMIDI
    /// emite `msgSetupChanged` por cambios que no afectan a los destinos.
    func testObserverIsNotNotifiedWhenNothingChanged() {
        let system = FakeSystem()
        system.destinations = [synth]
        let watcher = makeWatcher(system)

        var notifications = 0
        watcher.onChange = { _ in notifications += 1 }

        watcher.setupChanged()
        watcher.setupChanged()

        XCTAssertEqual(notifications, 0)
    }

    // MARK: - El estado se comunica sin disculpas

    /// `product-guidelines.md`: «Un dispositivo MIDI desconectado se comunica
    /// con un estado (`No MIDI device`), no con una disculpa.»
    func testNoDeviceStateUsesTheExactWordingFromTheGuidelines() {
        XCTAssertEqual(MIDIEndpointSelection(.destination).statusDescription, "No MIDI device")
    }

    func testStatusShowsTheDestinationNameWhenConnected() {
        XCTAssertEqual(
            MIDIEndpointSelection(.destination, discovering: [synth]).statusDescription,
            "Prophet Rev2"
        )
    }

    /// Ni lenguaje de error ni de disculpa, en ninguno de los dos estados.
    func testStatusNeverApologises() {
        let forbidden = ["error", "fail", "sorry", "unable", "could not", "problem", "!"]
        for status in [
            MIDIEndpointSelection(.destination).statusDescription,
            MIDIEndpointSelection(.destination, discovering: [synth]).statusDescription,
        ] {
            for word in forbidden {
                XCTAssertFalse(
                    status.lowercased().contains(word),
                    "«\(status)» usa lenguaje de error o disculpa: «\(word)»"
                )
            }
        }
    }
}
