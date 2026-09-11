import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests del portapapeles de Patterns.
///
/// **Guarda el Pattern entero, no un índice** (FR1). Es lo que permite pegar en
/// otro Bank, donde el hueco 3 contiene otra cosa: el material viaja como valor
/// y el Banco de origen no interviene en el pegado.
///
/// Recuerda además de dónde salió, y eso es **solo para dibujar la marca de
/// origen** (FR2, FR12).
final class PatternClipboardTests: XCTestCase {

    private var material: Pattern {
        Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)),
            at: 0
        )
    }

    /// Guarda el material entero y de dónde salió.
    func testTheClipboardHoldsTheMaterialAndItsOrigin() {
        let clipboard = PatternClipboard(pattern: material, bankIndex: 4, slotIndex: 9)

        XCTAssertEqual(clipboard.pattern, material)
        XCTAssertEqual(clipboard.bankIndex, 4)
        XCTAssertEqual(clipboard.slotIndex, 9)
    }

    /// **La marca solo se dibuja en el Bank de origen** (FR12). Mirando otro
    /// Banco no hay celda que marcar, y la señal de que hay algo cargado es que
    /// `paste` está habilitado.
    func testTheOriginMarkIsDrawnOnlyInItsOwnBank() {
        let clipboard = PatternClipboard(pattern: material, bankIndex: 4, slotIndex: 9)

        XCTAssertEqual(clipboard.markedSlot(inBank: 4), 9)
        XCTAssertNil(clipboard.markedSlot(inBank: 5))
        XCTAssertNil(clipboard.markedSlot(inBank: 0))
    }

    /// **Parado, el destino es el hueco seleccionado** (FR8).
    func testStoppedThePasteDestinationIsTheSelectedSlot() {
        XCTAssertEqual(
            PatternClipboard.destination(selected: 2, armed: nil, isRunning: false),
            2
        )
    }

    /// Y parado no hay armado que valga: aunque quedara uno anotado, el destino
    /// sigue siendo el seleccionado.
    func testStoppedAnArmedSlotDoesNotDivertThePaste() {
        XCTAssertEqual(
            PatternClipboard.destination(selected: 2, armed: 11, isRunning: false),
            2
        )
    }

    /// **Corriendo manda el armado** (FR8): sonando, tocar un hueco no mueve la
    /// selección —solo arma—, así que es la única forma de apuntar a un hueco
    /// distinto del que suena.
    func testRunningTheArmedSlotWins() {
        XCTAssertEqual(
            PatternClipboard.destination(selected: 2, armed: 11, isRunning: true),
            11
        )
    }

    /// Corriendo y sin nada armado, el destino es el que suena.
    func testRunningWithNothingArmedThePasteLandsOnWhatSounds() {
        XCTAssertEqual(
            PatternClipboard.destination(selected: 2, armed: nil, isRunning: true),
            2
        )
    }
}
