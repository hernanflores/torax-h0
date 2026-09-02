import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del knob que mueve el Cycle en edición.
///
/// **Dos cursores conviviendo.** El que suena lo mueve el scheduler en el límite
/// de vuelta; el que se edita lo mueve el knob 10, y no se tocan. Es la
/// separación que permite construir el Cycle B mientras suena el A (FR7), y es
/// también donde alguien se va a confundir: por eso lo que se fija aquí es que
/// mover uno no mueve al otro.
final class EditingCycleInputTests: XCTestCase {

    /// CC del knob 10 del preset: el bloque empieza en el 70 y los dieciséis van
    /// seguidos.
    private let cycleKnob = MIDIController(79)!

    private func cycle(pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Un input con los dieciséis Tracks, cada uno con `activeCount` Cycles.
    private func input(activeCycles: Int = 4) -> ControlInput {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Track(cycle()).withActiveCount(activeCycles), at: index)
        }
        return ControlInput(pattern: pattern, publish: { _ in })
    }

    private func turn(_ input: ControlInput, _ controller: MIDIController, by value: UInt8) {
        input.receive(
            .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value))
    }

    /// Un giro a la derecha en `Relative #2`.
    private let clockwise: UInt8 = 0x01
    private let counterClockwise: UInt8 = 0x7F

    // MARK: - El knob mueve el Cycle en edición

    /// El knob 10 mueve el Cycle en edición del **Track seleccionado**.
    func testTheTenthKnobMovesTheEditingCycleOfTheSelectedTrack() {
        let input = input()

        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
    }

    /// Y se frena en los extremos del rango **activo**, no en los dieciséis: no
    /// se edita un Cycle que no se recorre.
    func testItStopsAtBothEndsOfTheActiveRange() {
        let input = input(activeCycles: 3)

        for _ in 0..<10 { turn(input, cycleKnob, by: clockwise) }
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2, "pasó del último activo")

        for _ in 0..<10 { turn(input, cycleKnob, by: counterClockwise) }
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0, "pasó del primero")
    }

    /// Girar contra un extremo no publica: mandar un snapshot idéntico es
    /// trabajo y ruido para nada, igual que con Steps y Division.
    func testTurningAgainstAnEndDoesNotPublish() {
        let input = input(activeCycles: 2)

        XCTAssertTrue(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)))
        XCTAssertFalse(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)),
            "publicó sin cambiar nada")
    }

    /// Con un solo Cycle activo el knob no hace nada, que es lo coherente: no
    /// hay a dónde ir.
    func testWithASingleActiveCycleTheKnobDoesNothing() {
        let input = input(activeCycles: 1)

        XCTAssertFalse(
            input.receive(
                .controlChange(
                    channel: MIDIChannel(1)!, controller: cycleKnob, value: clockwise)))
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 0)
    }

    // MARK: - Los dos cursores no se tocan

    /// **FR7 — mover el Cycle en edición no altera el cursor de reproducción.**
    func testMovingTheEditingCycleLeavesThePlaybackCursorAlone() {
        var pattern = Pattern()
        pattern = pattern.replacing(
            Track(cycle()).withActiveCount(4).withCursor(2), at: 0)
        let input = ControlInput(pattern: pattern, publish: { _ in })

        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 0)?.cursor, 2, "movió el cursor que suena")
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
    }

    /// Ni el material: mover el cursor de edición no toca ni un Cycle.
    func testMovingTheEditingCycleChangesNoMaterial() {
        let input = input()
        let before = input.pattern

        turn(input, cycleKnob, by: clockwise)

        for track in 0..<Pattern.trackCount {
            for slot in 0..<Track.cycleCount {
                XCTAssertEqual(
                    input.pattern.track(at: track)?.cycle(at: slot),
                    before.track(at: track)?.cycle(at: slot),
                    "Track \(track + 1), Cycle \(slot + 1)")
            }
        }
    }

    // MARK: - Cada Track recuerda el suyo

    /// **Cambiar de Track deja a cada uno con su Cycle en edición donde
    /// estaba.** Vive en el Track y no en la vista por esto: volver a uno y
    /// encontrarlo editando otro Cycle sería perder el sitio.
    func testEachTrackKeepsItsOwnEditingCycleAcrossSelection() {
        let input = input()
        let stepButton = { (index: Int) in MIDIController(102 + index)! }

        // El Track 1 se deja editando el Cycle 3.
        turn(input, cycleKnob, by: clockwise)
        turn(input, cycleKnob, by: clockwise)
        // Se pasa al Track 5 y se deja editando el 2.
        turn(input, stepButton(4), by: 127)
        turn(input, cycleKnob, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 4)?.editing, 1)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2, "el Track 1 perdió el sitio")

        // Y al volver, sigue donde estaba.
        turn(input, stepButton(0), by: 127)
        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 2)
    }

    /// El knob mueve **solo** el del Track seleccionado, no el de los otros
    /// quince.
    func testTheKnobMovesOnlyTheSelectedTracksEditingCycle() {
        let input = input()

        turn(input, cycleKnob, by: clockwise)

        for index in 1..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.track(at: index)?.editing, 0, "movió el Track \(index + 1)")
        }
    }
}

/// Tests de que toda edición apunta al Cycle en edición.
///
/// **FR8 — los knobs, los pads y lo táctil mueven el Cycle en edición del Track
/// seleccionado.** Los otros quince Cycles y los otros quince Tracks no se
/// tocan. Es lo que permite construir el Cycle B mientras suena el A, y es
/// también el sitio donde una implementación descuidada destruiría trabajo: un
/// `replacing` que apuntara al Cycle que suena pisaría lo que se está oyendo.
final class EditingTargetsTheEditingCycleTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!
    private let stepNanoseconds: Int64 = 125_000_000
    private let clockwise: UInt8 = 0x01

    private func cycle(pulses: Int = 5, pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    private func input(activeCycles: Int = 3, editing: Int = 1) -> ControlInput {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Track(cycle()).withActiveCount(activeCycles).withEditing(editing), at: index)
        }
        return ControlInput(pattern: pattern, publish: { _ in })
    }

    private func turn(_ input: ControlInput, cc: Int, by value: UInt8) {
        input.receive(
            .controlChange(
                channel: MIDIChannel(1)!, controller: MIDIController(cc)!, value: value))
    }

    // MARK: - Los knobs

    /// **Un giro mueve el parámetro del Cycle en edición y de ningún otro.** Se
    /// comprueba sobre los quince Cycles restantes del mismo Track y sobre los
    /// quince Tracks restantes: un `replacing` que escribiera de más no se vería
    /// mirando solo el que se tocó.
    func testAKnobMovesOnlyTheEditingCycleOfTheSelectedTrack() {
        let input = input(editing: 1)
        let before = input.pattern

        // CC 71 es Pulses.
        turn(input, cc: 71, by: clockwise)

        XCTAssertNotEqual(
            input.pattern.track(at: 0)?.cycle(at: 1), before.track(at: 0)?.cycle(at: 1),
            "no movió el Cycle en edición")

        for slot in 0..<Track.cycleCount where slot != 1 {
            XCTAssertEqual(
                input.pattern.track(at: 0)?.cycle(at: slot), before.track(at: 0)?.cycle(at: slot),
                "tocó el Cycle \(slot + 1) del Track seleccionado")
        }
        for track in 1..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.track(at: track), before.track(at: track),
                "tocó el Track \(track + 1)")
        }
    }

    /// Y no mueve ninguno de los dos cursores: girar un knob edita material, no
    /// cambia de sitio.
    func testAKnobMovesNeitherCursor() {
        let input = input(editing: 1)

        turn(input, cc: 71, by: clockwise)

        XCTAssertEqual(input.pattern.track(at: 0)?.editing, 1)
        XCTAssertEqual(input.pattern.track(at: 0)?.cursor, 0)
    }

    // MARK: - Los pads

    /// Un pad mete la altura en el pool **del Cycle en edición**.
    func testAPadFillsThePoolOfTheEditingCycle() {
        let input = input(editing: 2)
        let before = input.pattern.track(at: 0)!.cycle(at: 2)!.pool.count

        input.receive(
            .noteOn(
                channel: MIDIChannel(1)!, note: MIDINote(38)!,
                velocity: MIDIVelocity(unchecked: 100)))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 2)?.pool.count, before + 1)
        XCTAssertEqual(
            input.pattern.track(at: 0)?.cycle(at: 0)?.pool.count, before,
            "metió la altura en un Cycle que no se estaba editando")
    }

    // MARK: - Lo táctil

    /// El canal y el marco tonal también son del Cycle en edición: son
    /// ediciones, y `product-guidelines.md` las pone del lado táctil, no en otro
    /// nivel del modelo.
    func testTouchEditsAlsoTargetTheEditingCycle() {
        let input = input(editing: 1)

        XCTAssertTrue(input.setChannel(Channel(11)!))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 1)?.channel, Channel(11)!)
        XCTAssertEqual(
            input.pattern.track(at: 0)?.cycle(at: 0)?.channel, Channel(1)!,
            "cambió el canal de un Cycle que no se estaba editando")
    }

    // MARK: - Contra lo que suena

    /// **Construir el B mientras suena el A.** Editar un Cycle que no está
    /// sonando no altera ni una nota de lo que sale, hasta que la vuelta cierre.
    func testEditingACycleThatIsNotSoundingChangesNothingThatSounds() {
        let handoff = PatternHandoff(Pattern())
        var pattern = Pattern()
        pattern = pattern.replacing(
            Track(cycle(pitch: 48)).withActiveCount(2)
                .replacing(cycle(pitch: 60), at: 1)
                .withEditing(1),
            at: 0
        )
        handoff.publish(pattern)

        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        let input = ControlInput(pattern: pattern, publishingTo: handoff)

        // Se edita el Cycle 2 —el que no suena— a mitad de la primera vuelta.
        var heard: [Int?] = []
        scheduler.advance(toHorizon: 8 * stepNanoseconds, refreshingFrom: handoff) {
            _, _, _, pitch, _, _ in
            heard.append(pitch?.value)
        }
        turn(input, cc: 71, by: clockwise)
        scheduler.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: handoff) {
            _, _, _, pitch, _, _ in
            heard.append(pitch?.value)
        }

        XCTAssertFalse(heard.isEmpty)
        XCTAssertTrue(
            heard.allSatisfy { $0 == 48 }, "la edición del Cycle 2 se coló en la vuelta del 1")
    }

    /// Y editar el que **sí** está sonando se oye en la ventana siguiente, como
    /// siempre: la edición en caliente no se pierde por tener Cycles.
    func testEditingTheSoundingCycleIsHeardOnTheNextWindow() {
        let handoff = PatternHandoff(Pattern())
        let pattern = Pattern().replacing(
            Track(cycle(pitch: 48)).withActiveCount(2)
                .replacing(cycle(pitch: 60), at: 1)
                .withEditing(0),
            at: 0
        )
        handoff.publish(pattern)

        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)
        let input = ControlInput(pattern: pattern, publishingTo: handoff)

        scheduler.advance(toHorizon: 4 * stepNanoseconds, refreshingFrom: handoff) {
            _, _, _, _, _, _ in
        }

        // Se sube un semitono el pool del Cycle que suena, metiendo otra altura.
        input.receive(
            .noteOn(
                channel: MIDIChannel(1)!, note: MIDINote(37)!,
                velocity: MIDIVelocity(unchecked: 100)))

        var heard: Set<Int> = []
        scheduler.advance(toHorizon: 16 * stepNanoseconds, refreshingFrom: handoff) {
            _, _, _, pitch, _, _ in
            if let value = pitch?.value { heard.insert(value) }
        }

        XCTAssertGreaterThan(heard.count, 1, "la edición en caliente no llegó a sonar")
    }
}
