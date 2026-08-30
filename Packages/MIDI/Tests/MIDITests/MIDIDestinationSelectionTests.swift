import XCTest
@testable import MIDI

/// Tests de la lista de destinos y su selección.
///
/// Se testea como valor puro, sobre listas dadas a mano, y no contra CoreMIDI:
/// la máquina de CI no tiene sintetizadores conectados, y lo que hay que
/// verificar aquí es la lógica de selección, no la enumeración del sistema.
final class MIDIEndpointSelectionTests: XCTestCase {

    private func destination(_ id: UInt32, _ name: String) -> MIDIEndpointInfo {
        MIDIEndpointInfo(endpoint: id, displayName: name)
    }

    private var synth: MIDIEndpointInfo { destination(1, "Prophet Rev2") }
    private var drums: MIDIEndpointInfo { destination(2, "Digitakt") }
    private var loopback: MIDIEndpointInfo { destination(9, VirtualLoopback.defaultName) }

    // MARK: - La lista refleja los destinos del sistema

    func testAvailableDestinationsMirrorTheSystemList() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth, drums])
        XCTAssertEqual(selection.available, [synth, drums])
    }

    func testRefreshingPicksUpADestinationThatAppeared() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth])
            .refreshed(with: [synth, drums])
        XCTAssertEqual(selection.available, [synth, drums])
    }

    // MARK: - Sin destinos es un estado válido

    /// «No MIDI device» no es un error ni un fallo de arranque: es lo que se ve
    /// cuando no hay nada enchufado.
    func testNoDestinationsIsAValidState() {
        let selection = MIDIEndpointSelection(.destination, discovering: [])
        XCTAssertTrue(selection.available.isEmpty)
        XCTAssertNil(selection.selected)
        XCTAssertFalse(selection.hasEndpoint)
    }

    func testEmptySelectionIsTheDefault() {
        XCTAssertFalse(MIDIEndpointSelection(.destination).hasEndpoint)
    }

    // MARK: - El endpoint de medición no es elegible

    /// Durante la medición de jitter el arnés y la app corren a la vez, así que
    /// su endpoint virtual aparece en la lista del sistema. Elegirlo mandaría
    /// las notas al medidor en vez de al sintetizador.
    func testMeasurementEndpointIsNotEligible() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth, loopback, drums])
        XCTAssertEqual(selection.available, [synth, drums])
    }

    func testMeasurementEndpointCannotBeSelected() {
        let selection = MIDIEndpointSelection(.destination, discovering: [loopback])
        XCTAssertFalse(selection.hasEndpoint)
        XCTAssertEqual(selection.selecting(loopback).selected, nil)
    }

    /// Un sistema en el que lo único presente es el medidor equivale a no tener
    /// nada conectado.
    func testOnlyTheMeasurementEndpointIsTheSameAsNoDevice() {
        XCTAssertTrue(
            MIDIEndpointSelection(.destination, discovering: [loopback]).available.isEmpty)
    }

    // MARK: - Selección

    /// Con algo conectado se elige solo, para que pulsar Play suene sin tener
    /// que tocar antes un selector.
    func testFirstDestinationIsSelectedAutomatically() {
        XCTAssertEqual(
            MIDIEndpointSelection(.destination, discovering: [synth, drums]).selected, synth)
    }

    func testSelectingChoosesAnotherDestination() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth, drums]).selecting(
            drums)
        XCTAssertEqual(selection.selected, drums)
    }

    func testSelectingSomethingNotInTheListIsIgnored() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth])
        XCTAssertEqual(selection.selecting(drums).selected, synth)
    }

    /// Refrescar no puede mover la elección del usuario bajo sus pies.
    func testRefreshingKeepsTheCurrentSelection() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth, drums])
            .selecting(drums)
            .refreshed(with: [synth, drums])
        XCTAssertEqual(selection.selected, drums)
    }

    func testRefreshingKeepsTheSelectionEvenIfTheOrderChanged() {
        let selection = MIDIEndpointSelection(.destination, discovering: [synth, drums])
            .selecting(drums)
            .refreshed(with: [drums, synth])
        XCTAssertEqual(selection.selected, drums)
    }
}
