import XCTest

@testable import Engine

/// Tests de Harmony bajo Temp (`pitch-harmony_20260912`, FR17, AC 12).
///
/// **Temp iguala, pero Harmony no se puede igualar**: cada Cycle puede tener un
/// pool distinto, y copiar offsets de uno a otro daría notas que nadie eligió.
/// Así que cada clic da **un paso en cada Cycle activo, con su propio estado**,
/// y conserva la histéresis. Al soltar vuelve el estado capturado de cada uno.
final class HarmonyUnderTempTests: XCTestCase {

    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func cycle(_ values: [Int]) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) },
            frame: cMajor)
    }

    /// A: C4 E4 G4 ya movido un clic. B: A3 C4 E4 limpio.
    private var start: Track {
        let a = cycle([60, 64, 67])
        return Track(a.with(harmony: a.harmonyMoved(by: 1)))
            .withActiveCount(2)
            .replacing(cycle([57, 60, 64]), at: 1)
    }

    private func harmonies(_ track: Track) -> [Harmony] {
        (0..<track.activeCount).compactMap { track.cycle(at: $0)?.harmony }
    }

    /// Cada clic es un paso en cada Cycle, desde su propio estado.
    func testEachClickStepsEveryActiveCycleFromItsOwnState() throws {
        var overlay = ParameterOverlay()
        let before = start

        let once = overlay.apply(1, to: .harmony, in: before)
        let twice = overlay.apply(1, to: .harmony, in: once)

        for index in 0..<2 {
            let cycle = try XCTUnwrap(before.cycle(at: index))
            XCTAssertEqual(
                twice.cycle(at: index)?.harmony, cycle.harmonyMoved(by: 2), "Cycle \(index)")
        }
    }

    /// **Con histéresis**, a diferencia de Ctrl All: tres arriba y uno abajo no
    /// es dos arriba.
    func testTempKeepsHysteresis() throws {
        var overlay = ParameterOverlay()
        var held = start
        for delta in [1, 1, 1, -1] { held = overlay.apply(delta, to: .harmony, in: held) }

        let b = try XCTUnwrap(start.cycle(at: 1))
        let expected = b.with(harmony: b.harmonyMoved(by: 3)).harmonyMoved(by: -1)
        XCTAssertEqual(held.cycle(at: 1)?.harmony, expected)
        XCTAssertNotEqual(expected, b.harmonyMoved(by: 2), "el caso no distingue")
    }

    /// Soltar devuelve el estado capturado de cada Cycle, cursor incluido.
    func testReleasingRestoresEachCapturedState() {
        var overlay = ParameterOverlay()
        var held = start
        for delta in [1, 1, -1] { held = overlay.apply(delta, to: .harmony, in: held) }

        XCTAssertEqual(harmonies(overlay.restored(into: held)), harmonies(start))
    }

    /// Un giro que no mueve ningún Cycle no captura nada ni cambia el Track.
    func testABlockedTurnCapturesNothing() {
        let blocked = Track(cycle([125, 127]))
        var overlay = ParameterOverlay()

        XCTAssertEqual(overlay.apply(1, to: .harmony, in: blocked), blocked)
        XCTAssertTrue(overlay.isEmpty)
    }

    /// Los Cycles inactivos no se tocan.
    func testInactiveCyclesAreLeftAlone() {
        var overlay = ParameterOverlay()
        let track = start.replacing(cycle([48, 52, 55]), at: 2)

        let held = overlay.apply(1, to: .harmony, in: track)
        XCTAssertEqual(held.cycle(at: 2), track.cycle(at: 2))
    }
}
