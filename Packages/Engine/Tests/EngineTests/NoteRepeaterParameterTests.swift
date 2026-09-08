import XCTest

@testable import Engine

/// Tests de los cuatro `TrackParameter` del Note Repeater.
///
/// **Caen en `ParameterFamily.shape` y no en una familia nueva.** La tabla de
/// Shape de la Pre Spec ya pone Repeats y Time ahí, y `product-guidelines.md`
/// fija tres acentos verificados a un metro: un cuarto color exigiría verificar
/// un cuarto color, sin una familia nueva que lo justifique.
///
/// **El caso se llama `.repeatTime` y el usuario lee `Time`.** Es desambiguación
/// de Swift frente a `MusicalTime` y `MusicalTimeline`, no un término nuevo
/// (NFR7).
final class NoteRepeaterParameterTests: XCTestCase {

    private let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
    private let four: [TrackParameter] = [.repeats, .repeatTime, .ramp, .pace]

    // MARK: - Los cuatro existen y se clasifican

    func testTheFourParametersBelongToTheShapeFamily() {
        for parameter in [TrackParameter.repeats, .repeatTime, .ramp, .pace] {
            XCTAssertEqual(parameter.family, .shape, "\(parameter)")
        }
    }

    /// Lo que el usuario lee: los términos de la Pre Spec, sin traducir.
    func testTheFourParametersReadAsThePreSpecNamesThem() {
        XCTAssertEqual(TrackParameter.repeats.description, "Repeats")
        XCTAssertEqual(TrackParameter.repeatTime.description, "Time")
        XCTAssertEqual(TrackParameter.ramp.description, "Ramp")
        XCTAssertEqual(TrackParameter.pace.description, "Pace")
    }

    func testTheFourParametersAreEnumerated() {
        for parameter in [TrackParameter.repeats, .repeatTime, .ramp, .pace] {
            XCTAssertTrue(TrackParameter.allCases.contains(parameter), "\(parameter)")
        }
    }

    /// **Los cuatro se distinguen del ritmo aunque compartan familia.** Es lo
    /// que parte el card de Shape en dos líneas: cuatro y cuatro.
    func testTheFourAreMarkedAsNoteRepeaterAndTheRestAreNot() {
        let shape = TrackParameter.allCases.filter { $0.family == .shape }
        XCTAssertEqual(shape.count, 8)
        XCTAssertEqual(shape.filter(\.isNoteRepeater), [.repeats, .repeatTime, .ramp, .pace])
        XCTAssertEqual(
            shape.filter { !$0.isNoteRepeater }, [.steps, .pulses, .rotate, .division])

        for parameter in TrackParameter.allCases where parameter.family == .groove {
            XCTAssertFalse(parameter.isNoteRepeater, "\(parameter)")
        }
    }

    // MARK: - Mover uno no destruye nada

    /// **La regla de destructividad de `product-guidelines.md`**: mover uno deja
    /// intactos Shape, Groove y el pool.
    func testMovingOneTouchesNeitherShapeNorGrooveNorPool() {
        let start = Cycle(
            shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!),
            pool: PitchPool().inserting(Pitch(62)!),
            groove: Groove(velocity: Velocity(80)!, sustain: .default, probability: .default),
            channel: Channel(4)!,
            frame: TonalFrame(scale: .major, root: Root(5)!),
            padOctaveShift: -1
        )

        for parameter in [TrackParameter.repeats, .repeatTime, .ramp, .pace] {
            let moved = start.applying(2, to: parameter)
            XCTAssertEqual(moved.shape, start.shape, "\(parameter)")
            XCTAssertEqual(moved.groove, start.groove, "\(parameter)")
            XCTAssertEqual(moved.pool, start.pool, "\(parameter)")
            XCTAssertEqual(moved.channel, start.channel, "\(parameter)")
            XCTAssertEqual(moved.frame, start.frame, "\(parameter)")
            XCTAssertEqual(moved.padOctaveShift, start.padOctaveShift, "\(parameter)")
        }
    }

    /// Y mover uno de los cuatro no mueve a los otros tres.
    func testMovingOneOfTheFourLeavesTheOtherThreeAlone() {
        let repeated = cycle.applying(3, to: .repeats)
        XCTAssertEqual(repeated.noteRepeater.repeats.count, 3)
        XCTAssertEqual(repeated.noteRepeater.time, RepeatTime.default)
        XCTAssertEqual(repeated.noteRepeater.ramp, Ramp.default)
        XCTAssertEqual(repeated.noteRepeater.pace, Pace.default)

        let ramped = repeated.applying(-40, to: .ramp)
        XCTAssertEqual(ramped.noteRepeater.repeats.count, 3)
        XCTAssertEqual(ramped.noteRepeater.ramp.percent, -40)
        XCTAssertEqual(ramped.noteRepeater.pace, Pace.default)

        let paced = ramped.applying(25, to: .pace)
        XCTAssertEqual(paced.noteRepeater.pace.percent, 25)
        XCTAssertEqual(paced.noteRepeater.ramp.percent, -40)

        let timed = paced.applying(1, to: .repeatTime)
        XCTAssertEqual(timed.noteRepeater.time, RepeatTime.ordered[5])
        XCTAssertEqual(timed.noteRepeater.repeats.count, 3)
    }

    /// Ninguno envuelve: girar contra un tope devuelve el mismo valor.
    func testNoneOfTheFourWrapsAtItsEnds() {
        XCTAssertEqual(cycle.applying(40, to: .repeats).noteRepeater.repeats.count, 8)
        XCTAssertEqual(cycle.applying(-40, to: .repeats).noteRepeater.repeats.count, 0)
        XCTAssertEqual(cycle.applying(200, to: .ramp).noteRepeater.ramp.percent, 100)
        XCTAssertEqual(cycle.applying(-200, to: .pace).noteRepeater.pace.percent, -100)
        XCTAssertEqual(
            cycle.applying(40, to: .repeatTime).noteRepeater.time, RepeatTime.ordered.last!)
    }

    // MARK: - Lo que se lee

    /// `3`, `1/32`, `+40%` y `−20%`. **Ramp y Pace con signo**, por la misma
    /// razón que Delay: subir y bajar no se distinguen por el contexto.
    func testTheFourWriteTheirValueWithTheirUnit() {
        let moved =
            cycle
            .applying(3, to: .repeats)
            .applying(40, to: .ramp)
            .applying(-20, to: .pace)

        XCTAssertEqual(TrackParameter.repeats.value(in: moved), "3")
        XCTAssertEqual(TrackParameter.repeatTime.value(in: moved), "1/32")
        XCTAssertEqual(TrackParameter.ramp.value(in: moved), "+40%")
        XCTAssertEqual(TrackParameter.pace.value(in: moved), "-20%")
    }

    /// El cero no lleva signo: no es ni subir ni bajar.
    func testZeroCarriesNoSign() {
        XCTAssertEqual(TrackParameter.ramp.value(in: cycle), "0%")
        XCTAssertEqual(TrackParameter.pace.value(in: cycle), "0%")
    }

    // MARK: - El valor grande transitorio

    /// **Girar cualquiera de los cuatro anuncia su valor grande** con el mismo
    /// formato que el card: el término de la Pre Spec y el valor, sin adornos
    /// (FR15).
    func testTurningEachOneAnnouncesItsValue() {
        let start = cycle.applying(2, to: .repeats)

        XCTAssertEqual(
            ParameterChange(from: start, to: start.applying(1, to: .repeats))?.description,
            "Repeats 3")
        XCTAssertEqual(
            ParameterChange(from: start, to: start.applying(1, to: .repeatTime))?.description,
            "Time 1/48")
        XCTAssertEqual(
            ParameterChange(from: start, to: start.applying(40, to: .ramp))?.description,
            "Ramp +40%")
        XCTAssertEqual(
            ParameterChange(from: start, to: start.applying(-20, to: .pace))?.description,
            "Pace -20%")
    }

    /// Y lo que anuncia el giro es exactamente lo que dice el card en reposo:
    /// si alguna vez se separan, es un fallo y no una variación.
    func testTheAnnouncementMatchesTheCard() {
        for parameter in four {
            let moved = cycle.applying(2, to: parameter)
            let change = ParameterChange(from: cycle, to: moved)

            XCTAssertEqual(change?.value, parameter.value(in: moved), "\(parameter)")
            XCTAssertEqual(change?.label, parameter.description, "\(parameter)")
        }
    }

    // MARK: - Ctrl All los alcanza

    /// **Los cuatro declaran su rango** (`displacementRange`), porque ninguno
    /// envuelve: Ctrl All necesita el rango para topar el desplazamiento
    /// acumulado.
    func testTheFourDeclareTheirDisplacementRange() {
        XCTAssertEqual(TrackParameter.repeats.displacementRange, Repeats.validRange)
        XCTAssertEqual(
            TrackParameter.repeatTime.displacementRange, 0...(RepeatTime.ordered.count - 1))
        XCTAssertEqual(TrackParameter.ramp.displacementRange, Ramp.validRange)
        XCTAssertEqual(TrackParameter.pace.displacementRange, Pace.validRange)
    }

    /// Y Ctrl All los topa como a los demás: el desplazamiento acumulado se
    /// satura y no envuelve.
    func testCtrlAllClampsTheFourLikeTheRest() {
        var offset = CtrlAllOffset().capturing(.repeats, from: Pattern.initial)
        for _ in 0..<50 {
            offset = offset.advancing(.repeats, by: 1)
        }

        XCTAssertLessThanOrEqual(offset.amount(of: .repeats), Repeats.validRange.upperBound)
    }
}
