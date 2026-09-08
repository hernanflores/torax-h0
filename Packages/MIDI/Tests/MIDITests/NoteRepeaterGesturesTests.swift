import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Temp y Ctrl All alcanzan a los cuatro del Note Repeater (FR17).
///
/// **Tenía que salir gratis, y salió**: los dos gestos operan sobre
/// `TrackParameter`, así que los cuatro entran solos. Estos tests están para que
/// siga siendo cierto — una lista de parámetros escrita a mano en cualquiera de
/// los dos caminos los dejaría fuera en silencio.
final class NoteRepeaterGesturesTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }

        var last: Pattern? {
            lock.lock()
            defer { lock.unlock() }
            return patterns.last
        }
    }

    private func makeInput() -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)),
            publish: published.record
        )
        return (input, published)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(
                ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }

    private func temp(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.ctrlAllModifierIndex, value: value)
    }

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        let controller = ControlMapping.beatStepPro.controller(for: parameter)!
        let value = delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        return .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value)
    }

    private let four: [TrackParameter] = [.repeats, .repeatTime, .ramp, .pace]

    // MARK: - Temp

    /// **Con [13] hundido, girar cualquiera de los cuatro suena y no se
    /// escribe**: al soltar vuelve el valor de antes.
    func testTempOverlaysTheFourAndGivesThemBack() {
        for parameter in four {
            let (input, published) = makeInput()
            let before = input.track.noteRepeater

            input.receive(temp())
            XCTAssertTrue(input.receive(knob(parameter, by: 3)), "\(parameter) no publicó")
            XCTAssertNotEqual(
                input.track.noteRepeater, before, "\(parameter) no se superpuso")

            XCTAssertTrue(input.receive(temp(value: 0)), "\(parameter) no publicó al soltar")
            XCTAssertEqual(
                input.track.noteRepeater, before, "\(parameter) no volvió al soltar")
            XCTAssertFalse(published.patterns.isEmpty)
        }
    }

    /// Y Temp iguala el valor en los Cycles activos del Track seleccionado, que
    /// es lo que el gesto hace con los otros nueve.
    func testTempReachesTheActiveCyclesOfTheSelectedTrack() {
        let (input, _) = makeInput()
        input.receive(stepButton(0))

        input.receive(temp())
        input.receive(knob(.repeats, by: 4))

        let track = input.pattern.track(at: 0)!
        XCTAssertEqual(track.cycle(at: 0)?.noteRepeater.repeats.count, 4)
    }

    // MARK: - Ctrl All

    /// **Con [14] hundido, girar Repeats desplaza los doce Tracks**, y soltar
    /// devuelve la base exacta de cada uno.
    func testCtrlAllMovesTheTwelveTracksAndGivesTheBaseBack() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        XCTAssertTrue(input.receive(knob(.repeats, by: 3)))

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.editingCycle(at: index)?.noteRepeater.repeats.count, 3,
                "el Track \(index + 1) no se movió")
        }

        XCTAssertTrue(input.receive(ctrlAll(value: 0)))
        XCTAssertEqual(input.pattern, before, "soltar no devolvió la base exacta")
    }

    /// **El tope sale de las bases capturadas**: girar contra el extremo no
    /// envuelve y no se pasa del rango de Repeats.
    func testCtrlAllClampsTheFourAtTheirEnds() {
        for parameter in four {
            let (input, _) = makeInput()
            input.receive(ctrlAll())
            for _ in 0..<40 {
                input.receive(knob(parameter, by: 5))
            }

            let repeater = input.pattern.editingCycle(at: 0)!.noteRepeater
            XCTAssertTrue(Repeats.validRange.contains(repeater.repeats.count), "\(parameter)")
            XCTAssertTrue(Ramp.validRange.contains(repeater.ramp.percent), "\(parameter)")
            XCTAssertTrue(Pace.validRange.contains(repeater.pace.percent), "\(parameter)")
            XCTAssertTrue(
                RepeatTime.ordered.contains(repeater.time), "\(parameter): Time salió de la lista")
        }
    }

    /// Y soltar Ctrl All después de haber topado sigue devolviendo la base: el
    /// tope no destruye lo capturado.
    func testReleasingAfterClampingStillRestoresTheBase() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        for _ in 0..<40 {
            input.receive(knob(.pace, by: -5))
        }
        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, before)
    }
}
