import XCTest

@testable import MIDI

/// Tests del defecto que MIDI Learn tenía delante: **la sesión de red monopoliza
/// la entrada**.
///
/// iPadOS publica siempre `Red Session 1` como fuente, esté o no en uso, y va la
/// primera de la lista. La app autoselecciona la primera, así que el controlador
/// real no se elige solo al conectarlo y el estado `No MIDI input` de
/// `product-guidelines.md` es inalcanzable.
///
/// **Se identifica por `driverOwner`, no por el nombre visible** (NFR4). El
/// diagnóstico del 2026-09-09 en iPad lo confirmó: la sesión de red declara
/// `com.apple.AppleMIDINetworkDriver` y los tres controladores por USB
/// `com.apple.AppleMIDIUSBDriver`. El nombre depende del idioma del sistema y de
/// lo que el usuario le haya puesto.
///
/// **Lo recordado manda sobre la autoselección** (FR15). El plan del track
/// original decía que «cuando haya persistencia, recordar la última elección lo
/// resuelve mejor que cualquier heurística»; la hay desde el 2026-09-07.
final class NetworkSessionSourceTests: XCTestCase {

    private let network = MIDIEndpointInfo(
        endpoint: 1, displayName: "Red Session 1", isNetworkSession: true)
    private let beatStep = MIDIEndpointInfo(
        endpoint: 2, displayName: "Arturia BeatStep Pro", isNetworkSession: false)
    private let opz = MIDIEndpointInfo(endpoint: 3, displayName: "OP-Z", isNetworkSession: false)

    // MARK: - El estado vacío vuelve a ser alcanzable (FR13)

    func testWithOnlyTheNetworkSessionThereIsNoEndpoint() {
        let selection = MIDIEndpointSelection(.source, discovering: [network])

        XCTAssertFalse(selection.hasEndpoint)
        XCTAssertEqual(selection.statusDescription, "No MIDI input")
    }

    // MARK: - Conectar un controlador basta (FR14)

    func testTheControllerIsChosenOverTheNetworkSession() {
        let selection = MIDIEndpointSelection(.source, discovering: [network, beatStep])

        XCTAssertEqual(selection.selected, beatStep)
    }

    /// **La red va primera en la lista real**, así que este es el orden que
    /// importa: el que el iPad devolvió el 2026-09-09.
    func testTheOrderOfTheSystemListDoesNotMatter() {
        let selection = MIDIEndpointSelection(.source, discovering: [beatStep, network])

        XCTAssertEqual(selection.selected, beatStep)
    }

    func testConnectingAControllerOnRefreshSelectsIt() {
        let selection = MIDIEndpointSelection(.source, discovering: [network])
            .refreshed(with: [network, beatStep])

        XCTAssertEqual(selection.selected, beatStep)
    }

    func testDisconnectingTheControllerFallsBackToTheEmptyState() {
        let selection = MIDIEndpointSelection(.source, discovering: [network, beatStep])
            .refreshed(with: [network])

        XCTAssertFalse(selection.hasEndpoint)
    }

    // MARK: - Elegible a mano, siempre (FR12)

    func testTheNetworkSessionStaysInTheList() {
        let selection = MIDIEndpointSelection(.source, discovering: [network, beatStep])

        XCTAssertTrue(selection.available.contains(network))
    }

    func testTheNetworkSessionCanBeChosenByHand() {
        let selection = MIDIEndpointSelection(.source, discovering: [network, beatStep])
            .selecting(network)

        XCTAssertEqual(selection.selected, network)
    }

    /// **Elegida a mano, sobrevive al refresco.** Es la garantía que el track
    /// original se puso a sí mismo y que este no toca.
    func testAManualChoiceOfTheNetworkSessionSurvivesARefresh() {
        let selection = MIDIEndpointSelection(.source, discovering: [network, beatStep])
            .selecting(network)
            .refreshed(with: [network, beatStep])

        XCTAssertEqual(selection.selected, network)
    }

    // MARK: - Lo recordado manda (FR15)

    func testARememberedSourceIsChosen() {
        let selection = MIDIEndpointSelection(
            .source, discovering: [network, beatStep, opz], remembering: "OP-Z")

        XCTAssertEqual(selection.selected, opz)
    }

    /// **Incluida la de red**: haberla elegido a mano y guardado es una elección
    /// explícita, y la regla de no autoseleccionarla no la contradice.
    func testARememberedNetworkSessionIsChosen() {
        let selection = MIDIEndpointSelection(
            .source, discovering: [network, beatStep], remembering: "Red Session 1")

        XCTAssertEqual(selection.selected, network)
    }

    /// Lo recordado que ya no está no bloquea: se cae a la regla de FR12, y no a
    /// la red.
    func testARememberedSourceThatIsGoneFallsBackWithoutChoosingTheNetwork() {
        let selection = MIDIEndpointSelection(
            .source, discovering: [network, beatStep], remembering: "Un sinte que ya no está")

        XCTAssertEqual(selection.selected, beatStep)
    }

    func testNothingRememberedBehavesLikeBefore() {
        let selection = MIDIEndpointSelection(
            .source, discovering: [network, beatStep], remembering: nil)

        XCTAssertEqual(selection.selected, beatStep)
    }

    /// Un nombre recordado que aparece dos veces se resuelve al primero, sin
    /// elegir por el camino algo que nadie pidió.
    func testARememberedNameThatRepeatsResolvesToTheFirst() {
        let twin = MIDIEndpointInfo(endpoint: 9, displayName: "OP-Z", isNetworkSession: false)
        let selection = MIDIEndpointSelection(
            .source, discovering: [network, opz, twin], remembering: "OP-Z")

        XCTAssertEqual(selection.selected, opz)
        XCTAssertEqual(selection.refreshed(with: [network, twin, opz]).selected, opz)
    }

    // MARK: - El destino, desde el 2026-09-09

    /// **La regla pasó a valer también para la salida.** El `spec.md` decía que
    /// como destino la sesión de red «no estorba a ningún estado especificado»,
    /// y el iPad lo desmintió: se autoseleccionaba, así que la app arrancaba
    /// mandando las notas a la red en vez de a un sintetizador.
    func testTheNetworkSessionIsNotAutoSelectedAsADestinationEither() {
        let selection = MIDIEndpointSelection(.destination, discovering: [network])

        XCTAssertFalse(selection.hasEndpoint)
        XCTAssertEqual(selection.statusDescription, "No MIDI device")
    }

    func testASynthIsChosenOverTheNetworkSessionAsADestination() {
        let synth = MIDIEndpointInfo(endpoint: 4, displayName: "Sinte", isNetworkSession: false)
        let selection = MIDIEndpointSelection(.destination, discovering: [network, synth])

        XCTAssertEqual(selection.selected, synth)
    }

    /// **Sigue siendo elegible**, que es la mitad que no cambia: MIDI por red a
    /// otro equipo es una vía legítima de salida.
    func testTheNetworkSessionCanStillBeChosenAsADestinationByHand() {
        let selection = MIDIEndpointSelection(.destination, discovering: [network])
            .selecting(network)

        XCTAssertEqual(selection.selected, network)
    }

    func testARememberedNetworkDestinationIsChosen() {
        let synth = MIDIEndpointInfo(endpoint: 4, displayName: "Sinte", isNetworkSession: false)
        let selection = MIDIEndpointSelection(
            .destination, discovering: [network, synth], remembering: "Red Session 1")

        XCTAssertEqual(selection.selected, network)
    }

    /// Los endpoints de la propia app siguen fuera del destino, que era la otra
    /// regla que vive en esta comprobación.
    func testTheAppsOwnEndpointIsStillNotADestination() {
        let own = MIDIEndpointInfo(
            endpoint: 5, displayName: VirtualLoopback.defaultName, isNetworkSession: false)
        let selection = MIDIEndpointSelection(.destination, discovering: [own])

        XCTAssertFalse(selection.hasEndpoint)
    }
}
