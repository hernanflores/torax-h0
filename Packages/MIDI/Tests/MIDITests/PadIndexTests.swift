import Engine
import XCTest
@testable import MIDI

/// Tests de la resolución de un pad a su índice.
///
/// **El cambio de modelo de la rebanada 7.** El número de nota que envía el
/// controlador deja de leerse como altura y pasa a decir únicamente *qué pad se
/// pulsó*. La altura la decide después la superficie, con el marco tonal y la
/// octava vigente.
final class PadIndexTests: XCTestCase {

    private let mapping = ControlMapping.provisional

    // MARK: - El bloque se resuelve a índice

    /// El primero da 0 y el decimosexto da 15, y los catorce de en medio en
    /// orden.
    func testTheBlockResolvesToTheSixteenIndices() throws {
        let base = Int(mapping.padBlock.value)
        for offset in 0..<16 {
            let note = try XCTUnwrap(MIDINote(base + offset))
            XCTAssertEqual(mapping.padIndex(for: note), offset)
        }
    }

    /// Por debajo y por encima del bloque no hay índice — mismo criterio que un
    /// CC sin asignar: no es un error.
    func testNotesOutsideTheBlockHaveNoIndex() throws {
        let base = Int(mapping.padBlock.value)
        for number in 0...127 where !(base..<(base + 16)).contains(number) {
            let note = try XCTUnwrap(MIDINote(number))
            XCTAssertNil(mapping.padIndex(for: note), "nota \(number)")
        }
    }

    /// **El bloque es un dato del mapeo, no una constante repartida por el
    /// código:** cambiarlo mueve los dieciséis pads a la vez.
    func testMovingTheBlockMovesAllSixteenPadsAtOnce() throws {
        let moved = ControlMapping(
            assignments: [.steps: 70], padBlock: try XCTUnwrap(MIDINote(60)))

        for offset in 0..<16 {
            XCTAssertEqual(moved.padIndex(for: try XCTUnwrap(MIDINote(60 + offset))), offset)
        }
        XCTAssertNil(moved.padIndex(for: try XCTUnwrap(MIDINote(59))))
        XCTAssertNil(moved.padIndex(for: try XCTUnwrap(MIDINote(76))))
    }

    /// El bloque cabe entero en el rango MIDI: dieciséis pads consecutivos desde
    /// la nota base, sin que el último se salga.
    func testTheBlockFitsInsideTheMidiRange() {
        XCTAssertNotNil(MIDINote(Int(mapping.padBlock.value) + 15))
    }

    // MARK: - El número de transporte no es la altura musical

    /// **La coincidencia numérica no se puede leer nunca como identidad.** El
    /// pad cuyo mensaje es la nota 36 produce la nota 48 con el marco por
    /// defecto: el número que viaja por el cable y la altura que suena son dos
    /// cosas distintas, y este test existe para que nadie las vuelva a juntar.
    func testTheTransportNumberIsNotTheMusicalPitch() throws {
        let note = try XCTUnwrap(MIDINote(36))
        let index = try XCTUnwrap(mapping.padIndex(for: note))
        XCTAssertEqual(index, 0)

        let surface = PadSurface(frame: TonalFrame(scale: .major, root: Root(0)!))
        XCTAssertEqual(surface.pitch(at: index)?.value, 48)
        XCTAssertNotEqual(surface.pitch(at: index)?.value, Int(note.value))
    }
}
