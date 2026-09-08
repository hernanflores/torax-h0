import Engine
import Foundation
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de FR5: adoptar cancela Temp y Ctrl All **sin restaurar**.
///
/// El overlay de Temp y el desplazamiento de Ctrl All guardan valores capturados
/// del Pattern anterior. Restaurarlos sobre el Pattern nuevo escribiría material
/// de otro sitio encima del recién adoptado, que es exactamente la destrucción
/// que este track existe para impedir.
final class AdoptionCancelsModifiersTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }
    }

    // MARK: - Temp

    /// Con Temp hundido, adoptar y soltar no escribe nada: el Pattern queda como
    /// lo dejó la adopción.
    func testReleasingTempAfterAdoptingWritesNothing() {
        let (input, published) = makeInput()

        input.receive(temp())
        input.receive(knob(.pulses, by: 3))

        let adopted = makeAdoptedPattern()
        input.adopt(adopted)
        let publishedSoFar = published.patterns.count

        input.receive(temp(value: 0))

        XCTAssertEqual(input.pattern, adopted, "soltar Temp escribió sobre el Pattern adoptado")
        XCTAssertEqual(published.patterns.count, publishedSoFar, "soltar Temp publicó")
    }

    /// Y `releaseModifiers()` —la vía de la reconexión— tampoco escribe nada.
    func testReleaseModifiersAfterAdoptingWithTempHeldWritesNothing() {
        let (input, published) = makeInput()

        input.receive(temp())
        input.receive(knob(.pulses, by: 3))

        let adopted = makeAdoptedPattern()
        input.adopt(adopted)
        let publishedSoFar = published.patterns.count

        input.releaseModifiers()

        XCTAssertEqual(input.pattern, adopted)
        XCTAssertEqual(published.patterns.count, publishedSoFar)
    }

    // MARK: - Ctrl All

    /// Lo mismo con Ctrl All.
    func testReleasingCtrlAllAfterAdoptingWritesNothing() {
        let (input, published) = makeInput()

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))

        let adopted = makeAdoptedPattern()
        input.adopt(adopted)
        let publishedSoFar = published.patterns.count

        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, adopted, "soltar Ctrl All escribió sobre el Pattern adoptado")
        XCTAssertEqual(published.patterns.count, publishedSoFar, "soltar Ctrl All publicó")
    }

    /// **Incluido el caso de haber girado contra el tope antes de adoptar**, que
    /// es donde el desplazamiento acumulado y lo que se ve dejan de coincidir:
    /// la base capturada sigue siendo la del Pattern viejo.
    func testReleasingCtrlAllAfterTurningAgainstTheStopAndAdoptingWritesNothing() {
        let (input, published) = makeInput()

        input.receive(ctrlAll())
        for _ in 0..<8 { input.receive(knob(.pulses, by: 8)) }  // contra el tope

        let adopted = makeAdoptedPattern()
        input.adopt(adopted)
        let publishedSoFar = published.patterns.count

        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, adopted)
        XCTAssertEqual(published.patterns.count, publishedSoFar)
    }

    // MARK: - El modificador sigue hundido

    /// **Soltar no es lo que cancela: adoptar sí.** El botón sigue físicamente
    /// hundido, así que a efectos del gesto siguiente Temp sigue activo.
    func testTempStaysHeldAfterAdopting() {
        let (input, _) = makeInput()

        input.receive(temp())
        input.adopt(makeAdoptedPattern())

        XCTAssertTrue(input.isTempActive, "adoptar levantó el botón")
    }

    /// Y el giro siguiente se superpone, no escribe: el modificador sigue al
    /// mando sobre el material nuevo.
    func testATurnAfterAdoptingWithTempHeldIsStillTemporary() {
        let (input, _) = makeInput()

        input.receive(temp())
        let adopted = makeAdoptedPattern()
        input.adopt(adopted)

        input.receive(knob(.pulses, by: 3))
        input.receive(temp(value: 0))

        XCTAssertEqual(input.pattern, adopted, "el fill sobre el Pattern nuevo no se deshizo")
    }

    /// Lo mismo para Ctrl All.
    func testCtrlAllStaysHeldAfterAdopting() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.adopt(makeAdoptedPattern())

        XCTAssertTrue(input.isCtrlAllActive, "adoptar levantó el botón")
    }

    // MARK: - Helpers

    private func makeInput() -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
                pool: PitchPool().inserting(Pitch(48)!)
            ),
            publish: published.record
        )
        return (input, published)
    }

    private func makeAdoptedPattern() -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Cycle(shape: Shape(steps: Steps(9)!, pulses: Pulses(2)!)),
                at: index
            )
        }
        return pattern
    }

    private func temp(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.ctrlAllModifierIndex, value: value)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }
}
