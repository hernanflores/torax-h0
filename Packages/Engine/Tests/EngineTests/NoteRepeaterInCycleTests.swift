import XCTest

@testable import Engine

/// Tests del `NoteRepeater` dentro del `Cycle`.
///
/// **Vive en el `Cycle` por la misma razón que el pool y el Groove**: el hilo
/// del scheduler lo necesita para construir los mensajes, y lo único que ese
/// hilo lee es el snapshot publicado. De ahí que tenga que ser un valor trivial,
/// y de ahí que `_isPOD(Cycle.self)` siga siendo la red.
///
/// **Cada Cycle tiene el suyo**, así que un desarrollo A/B puede ratchetear solo
/// en el B.
final class NoteRepeaterInCycleTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(4)!)

    // MARK: - El neutro

    /// El `NoteRepeater` por defecto es el estado de antes de la rebanada: sin
    /// repeticiones, y por tanto sin nada del camino nuevo.
    func testTheDefaultRepeaterIsNeutral() {
        let repeater = NoteRepeater.default
        XCTAssertEqual(repeater.repeats, Repeats.default)
        XCTAssertEqual(repeater.time, RepeatTime.default)
        XCTAssertEqual(repeater.ramp, Ramp.default)
        XCTAssertEqual(repeater.pace, Pace.default)
    }

    func testACycleStartsWithTheNeutralRepeater() {
        XCTAssertEqual(Cycle(shape: shape).noteRepeater, NoteRepeater.default)
    }

    // MARK: - `with(...)` no lo pierde

    /// **Cambiar cualquier otra cosa lo conserva.** Es la regla que
    /// `Cycle.with(...)` existe para garantizar: reconstruir el Cycle a mano
    /// perdería en silencio lo que no se nombre.
    func testEveryOtherEditKeepsTheRepeater() {
        let repeater = NoteRepeater(
            repeats: Repeats(5)!,
            time: RepeatTime.ordered.last!,
            ramp: Ramp(percent: -70)!,
            pace: Pace(percent: 30)!
        )
        let cycle = Cycle(shape: shape).with(noteRepeater: repeater)

        XCTAssertEqual(
            cycle.with(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)).noteRepeater, repeater)
        XCTAssertEqual(cycle.with(pool: PitchPool().inserting(Pitch(60)!)).noteRepeater, repeater)
        XCTAssertEqual(
            cycle.with(
                groove: Groove(velocity: Velocity(40)!, sustain: .default, probability: .default)
            ).noteRepeater, repeater)
        XCTAssertEqual(cycle.with(channel: Channel(10)!).noteRepeater, repeater)
        XCTAssertEqual(
            cycle.with(frame: TonalFrame(scale: .major, root: Root(2)!)).noteRepeater, repeater)
        XCTAssertEqual(cycle.with(padOctaveShift: 2).noteRepeater, repeater)
    }

    /// Y cambiarlo no toca nada más, que es la otra mitad de la regla de
    /// destructividad de `product-guidelines.md`.
    func testChangingTheRepeaterTouchesNothingElse() {
        let cycle = Cycle(
            shape: shape,
            pool: PitchPool().inserting(Pitch(64)!),
            groove: Groove(velocity: Velocity(90)!, sustain: .default, probability: .default),
            channel: Channel(7)!,
            frame: TonalFrame(scale: .major, root: Root(7)!),
            padOctaveShift: 1
        )
        let changed = cycle.with(noteRepeater: NoteRepeater(repeats: Repeats(8)!))

        XCTAssertEqual(changed.shape, cycle.shape)
        XCTAssertEqual(changed.pool, cycle.pool)
        XCTAssertEqual(changed.groove, cycle.groove)
        XCTAssertEqual(changed.channel, cycle.channel)
        XCTAssertEqual(changed.frame, cycle.frame)
        XCTAssertEqual(changed.padOctaveShift, cycle.padOctaveShift)
        XCTAssertEqual(changed.noteRepeater.repeats.count, 8)
    }

    // MARK: - Uno por Cycle

    /// **Editar el B no toca al A**: el desarrollo puede ratchetear solo en una
    /// vuelta.
    func testEachCycleCarriesItsOwnRepeater() {
        let track = Track(Cycle(shape: shape))
        let ratcheted = track.replacing(
            track.cycle(at: 1)!.with(noteRepeater: NoteRepeater(repeats: Repeats(6)!)),
            at: 1
        )

        XCTAssertEqual(ratcheted.cycle(at: 1)?.noteRepeater.repeats.count, 6)
        XCTAssertEqual(ratcheted.cycle(at: 0)?.noteRepeater, NoteRepeater.default)
        for index in 2..<Track.cycleCount {
            XCTAssertEqual(
                ratcheted.cycle(at: index)?.noteRepeater, NoteRepeater.default, "Cycle \(index)")
        }
    }

    // MARK: - Sigue siendo trivial

    /// `_isPOD(Cycle.self)` es la red que impide que el snapshot deje de poder
    /// copiarse dentro del hilo del scheduler.
    func testTheCycleIsStillTriviallyCopyable() {
        XCTAssertTrue(_isPOD(NoteRepeater.self), "el NoteRepeater no es trivial")
        XCTAssertTrue(_isPOD(Cycle.self), "el Cycle dejó de ser trivial")
    }

    /// **El coste del campo nuevo, escrito: cuatro bytes por Cycle.** Es lo que
    /// NFR2 presupone —~768 bytes sobre los ~37 KB del snapshot con 12 Tracks ×
    /// 16 Cycles, un 2%— y lo que obliga a guardar los cuatro como `Int8` en vez
    /// de como sus tipos: `RepeatTime` envuelve una fracción, que son dos
    /// palabras, y almacenarla entera multiplicaría por diez el coste del campo.
    func testTheRepeaterCostsFourBytesPerCycle() {
        XCTAssertEqual(MemoryLayout<NoteRepeater>.size, 4)
    }

    /// Una Time fuera de la lista cae en el default al guardarse: el `Cycle`
    /// almacena la posición del knob, y el knob solo pasa por las nueve.
    func testATimeOutsideTheListFallsBackToTheDefault() {
        let unlisted = RepeatTime(numerator: 3, denominator: 7)!
        XCTAssertEqual(NoteRepeater(time: unlisted).time, RepeatTime.default)
    }
}
