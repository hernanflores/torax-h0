import XCTest

@testable import Engine

/// **`Pattern` a secas es ambiguo en un target de test**, con el mismo motivo
/// que anota `PatternTests`: XCTest arrastra `ApplicationServices`, que trae un
/// `Pattern` propio.
private typealias Pattern = Engine.Pattern

/// Tests del snapshot de Ctrl All: qué había debajo de los doce, y cuánto se ha
/// desplazado.
///
/// **Lo que se prueba aquí es la memoria, no el gesto.** `CtrlAllOffset` guarda
/// el valor base de los parámetros que la mano toca —por Track y por Cycle
/// activo— y el desplazamiento acumulado de cada uno. No sabe nada de step
/// buttons ni de mensajes MIDI: eso es de `ControlInput`, en la fase del gesto.
///
/// **Por qué guarda base y offset por separado, y no el valor superpuesto.** El
/// valor de cada Cycle se recalcula siempre como base + offset. Es lo único que
/// hace exacta la ida y vuelta cuando un Track topa contra su extremo: si se
/// guardara el valor ya acotado, desandar el giro dejaría al topado clavado en
/// el tope mientras los demás vuelven (FR4).
///
/// **Y por qué el offset y no la igualación de Temp.** `ParameterOverlay`
/// **iguala** —el mismo valor absoluto en todos los Cycles del Track
/// seleccionado—; esto **desplaza** —el mismo delta en los doce Tracks,
/// conservando sus diferencias—. Son dos tipos porque son dos verbos.
final class CtrlAllOffsetTests: XCTestCase {

    // MARK: - Material de prueba

    private func cycle(pulses: Int = 5, velocity: Int = 100, steps: Int = 16) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: Velocity(velocity)!,
                sustain: Sustain(percent: 50)!,
                probability: Probability(percent: 100)!,
                timing: Timing(percent: 50)!,
                delay: Delay(percent: 0)!
            )
        )
    }

    /// Un Track con un Cycle distinto en cada hueco activo.
    ///
    /// Se fija primero cuántos hay activos y **después** se escribe cada uno:
    /// `withActiveCount(_:)` siembra los huecos nuevos con una copia del Cycle en
    /// edición, así que hacerlo al revés los dejaría a todos iguales.
    private func track(pulsesPerCycle: [Int]) -> Track {
        var track = Track(cycle(pulses: pulsesPerCycle[0]))
            .withActiveCount(pulsesPerCycle.count)
        for (index, pulses) in pulsesPerCycle.enumerated() {
            track = track.replacing(cycle(pulses: pulses), at: index)
        }
        return track
    }

    /// Un Pattern con los doce Tracks distintos entre sí.
    private func pattern(pulsesPerTrack: [Int]) -> Pattern {
        var pattern = Pattern()
        for (index, pulses) in pulsesPerTrack.enumerated() {
            pattern = pattern.replacing(Track(cycle(pulses: pulses)), at: index)
        }
        return pattern
    }

    private var twelve: [Int] { [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] }

    // MARK: - El reposo

    /// **El snapshot vacío es el estado de reposo**, no un caso degenerado: es lo
    /// que hay mientras nadie mantiene el step 14.
    func testAnEmptyOffsetIsTheRestingState() {
        let offset = CtrlAllOffset()

        XCTAssertTrue(offset.isEmpty, "el offset recién creado dice tener algo guardado")
        XCTAssertTrue(
            offset.parameters.isEmpty, "declara parámetros tocados sin haber tocado ninguno")
    }

    /// Restaurar desde el reposo no cambia nada: soltar el step 14 sin haber
    /// girado se queda en nada.
    func testRestoringFromAnEmptyOffsetChangesNothing() {
        let original = pattern(pulsesPerTrack: twelve)

        XCTAssertEqual(CtrlAllOffset().restored(into: original), original)
    }

    // MARK: - Guardar la base

    /// **La base se guarda por Track y por Cycle activo.** Es lo que separa este
    /// snapshot del de Temp, que solo alcanza a un Track.
    func testCapturingStoresABasePerTrackAndCycle() {
        var source = pattern(pulsesPerTrack: twelve)
        source = source.replacing(track(pulsesPerCycle: [5, 7, 9]), at: 0)

        let offset = CtrlAllOffset().capturing(.pulses, from: source)

        XCTAssertEqual(offset.base(of: .pulses, track: 0, cycle: 0), 5)
        XCTAssertEqual(offset.base(of: .pulses, track: 0, cycle: 1), 7)
        XCTAssertEqual(offset.base(of: .pulses, track: 0, cycle: 2), 9)
        XCTAssertEqual(offset.base(of: .pulses, track: 3, cycle: 0), 4)
        XCTAssertEqual(offset.base(of: .pulses, track: 11, cycle: 0), 12)
    }

    /// **Los Cycles inactivos no se capturan**: el desplazamiento alcanza a lo
    /// que se recorre, y de lo demás no hay nada que devolver.
    func testCapturingSkipsInactiveCycles() {
        var source = pattern(pulsesPerTrack: twelve)
        source = source.replacing(track(pulsesPerCycle: [5, 7]), at: 0)

        let offset = CtrlAllOffset().capturing(.pulses, from: source)

        XCTAssertNotNil(offset.base(of: .pulses, track: 0, cycle: 1))
        XCTAssertNil(offset.base(of: .pulses, track: 0, cycle: 2), "capturó un Cycle inactivo")
    }

    /// **Capturar dos veces no re-guarda la base**, y es el caso normal y no el
    /// raro: girar un knob produce un mensaje tras otro, y el segundo llega con
    /// el desplazamiento ya puesto. Re-guardar dejaría el gesto escrito para
    /// siempre — lo que este tipo existe para impedir.
    func testCapturingTwiceKeepsTheFirstBase() {
        let source = pattern(pulsesPerTrack: twelve)

        var offset = CtrlAllOffset().capturing(.pulses, from: source)
        let moved = source.replacing(Track(cycle(pulses: 15)), at: 0)
        offset = offset.capturing(.pulses, from: moved)

        XCTAssertEqual(offset.base(of: .pulses, track: 0, cycle: 0), 1, "se re-guardó la base")
    }

    /// Un parámetro que nadie tocó no aparece en el snapshot.
    func testAnUntouchedParameterIsNotStored() {
        let offset = CtrlAllOffset().capturing(.pulses, from: pattern(pulsesPerTrack: twelve))

        XCTAssertNil(offset.base(of: .velocity, track: 0, cycle: 0))
        XCTAssertEqual(offset.parameters, [.pulses])
    }

    // MARK: - El desplazamiento acumulado

    /// Cada parámetro lleva su propio desplazamiento (FR7): durante un hold se
    /// puede subir uno y bajar otro.
    func testEachParameterAccumulatesItsOwnOffset() {
        let source = pattern(pulsesPerTrack: twelve)
        var offset = CtrlAllOffset()

        offset = offset.capturing(.pulses, from: source).advancing(.pulses, by: 3)
        offset = offset.capturing(.velocity, from: source).advancing(.velocity, by: -10)

        XCTAssertEqual(offset.amount(of: .pulses), 3)
        XCTAssertEqual(offset.amount(of: .velocity), -10)
        XCTAssertEqual(offset.parameters, [.pulses, .velocity])
    }

    /// Girar dos veces acumula, y girar de vuelta desanda.
    func testTurningAccumulatesAndUnwinds() {
        let source = pattern(pulsesPerTrack: twelve)
        var offset = CtrlAllOffset().capturing(.pulses, from: source)

        offset = offset.advancing(.pulses, by: 2).advancing(.pulses, by: 3)
        XCTAssertEqual(offset.amount(of: .pulses), 5)

        offset = offset.advancing(.pulses, by: -5)
        XCTAssertEqual(offset.amount(of: .pulses), 0, "desandar el giro no volvió a cero")
    }

    /// Un parámetro sin tocar tiene desplazamiento cero, no `nil`: preguntar por
    /// él es normal, y cero es la respuesta correcta.
    func testAnUntouchedParameterHasNoDisplacement() {
        XCTAssertEqual(CtrlAllOffset().amount(of: .rotate), 0)
    }

    // MARK: - Genérico sobre TrackParameter

    /// **El tipo acepta cualquier caso de `TrackParameter`** (FR18), sin
    /// enumerar los nueve: Accent, Repeats y los demás quedan cubiertos el día
    /// que se mapeen, sin volver aquí.
    func testEveryTrackParameterCanBeCapturedAndAdvanced() {
        let source = pattern(pulsesPerTrack: twelve)

        for parameter in TrackParameter.allCases {
            let offset = CtrlAllOffset().capturing(parameter, from: source)
                .advancing(parameter, by: 1)

            XCTAssertNotNil(
                offset.base(of: parameter, track: 0, cycle: 0), "\(parameter) no se capturó")
            XCTAssertEqual(offset.amount(of: parameter), 1, "\(parameter) no acumuló")
        }
    }

    /// Y `parameters` los devuelve en el orden declarado, no en el del recorrido
    /// de un diccionario: un orden que cambia entre ejecuciones convierte un test
    /// en un lanzamiento de moneda.
    func testParametersComeBackInDeclaredOrder() {
        let source = pattern(pulsesPerTrack: twelve)
        var offset = CtrlAllOffset()

        for parameter in TrackParameter.allCases.reversed() {
            offset = offset.capturing(parameter, from: source)
        }

        XCTAssertEqual(offset.parameters, TrackParameter.allCases)
    }
}
