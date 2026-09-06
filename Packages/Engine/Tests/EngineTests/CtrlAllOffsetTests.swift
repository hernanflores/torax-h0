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
        // **Un Cycle con los nueve parámetros en el interior de su rango.** El
        // helper de esta clase deja Timing en 50 y Probability en 100, que son
        // sus extremos, y contra un extremo el tope del acumulado no deja
        // avanzar: el test estaría comprobando la saturación en vez de la
        // acumulación, y falló por eso mientras se escribía.
        let interior = Cycle(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(5)!, rotate: Rotate(2)),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!,
                timing: Timing(percent: 60)!,
                delay: Delay(percent: 0)!
            )
        )
        let source = Pattern().replacing(Track(interior), at: 0)

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

/// Tests de aplicar el desplazamiento sobre el Pattern.
///
/// **Lo que se fija aquí es que Ctrl All desplaza y no iguala**, y que acotar
/// contra un extremo no destruye nada: es la mitad del tipo que justifica
/// guardar base y offset por separado.
final class CtrlAllApplyTests: XCTestCase {

    private func cycle(pulses: Int = 5, velocity: Int = 100, steps: Int = 16, rotate: Int = 0)
        -> Cycle
    {
        Cycle(
            shape: Shape(
                steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate)),
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

    private func pattern(pulsesPerTrack: [Int]) -> Pattern {
        var pattern = Pattern()
        for (index, pulses) in pulsesPerTrack.enumerated() {
            pattern = pattern.replacing(Track(cycle(pulses: pulses)), at: index)
        }
        return pattern
    }

    private var twelve: [Int] { [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] }

    private func pulses(_ pattern: Pattern, track: Int, cycle: Int = 0) -> Int? {
        pattern.track(at: track)?.cycle(at: cycle)?.shape.pulses.count
    }

    // MARK: - Desplaza los doce

    /// Un delta mueve el mismo parámetro en los doce Tracks.
    func testOneTurnMovesAllTwelveTracks() {
        var offset = CtrlAllOffset()
        let source = pattern(pulsesPerTrack: twelve)

        let moved = offset.apply(1, to: .pulses, in: source)

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(pulses(moved, track: index), index + 2, "Track \(index + 1)")
        }
    }

    /// **Y conserva las diferencias**, que es lo que lo separa de Temp: dos
    /// Tracks a distancia 5 siguen a distancia 5 después del gesto.
    func testTheDistanceBetweenTracksSurvives() {
        var offset = CtrlAllOffset()
        var source = Pattern()
        source = source.replacing(Track(cycle(pulses: 4)), at: 0)
        source = source.replacing(Track(cycle(pulses: 9)), at: 1)

        let moved = offset.apply(3, to: .pulses, in: source)

        XCTAssertEqual(pulses(moved, track: 0), 7)
        XCTAssertEqual(pulses(moved, track: 1), 12)
        XCTAssertEqual(
            pulses(moved, track: 1)! - pulses(moved, track: 0)!, 5,
            "el gesto aplanó la diferencia entre los dos Tracks")
    }

    /// Alcanza a todos los Cycles activos, y cada uno conserva el suyo
    /// desplazado.
    func testEveryActiveCycleMovesKeepingItsOwnValue() {
        var offset = CtrlAllOffset()
        var track = Track(cycle(pulses: 5)).withActiveCount(3)
        for (index, count) in [5, 7, 9].enumerated() {
            track = track.replacing(cycle(pulses: count), at: index)
        }
        let source = Pattern().replacing(track, at: 0)

        let moved = offset.apply(2, to: .pulses, in: source)

        XCTAssertEqual(pulses(moved, track: 0, cycle: 0), 7)
        XCTAssertEqual(pulses(moved, track: 0, cycle: 1), 9)
        XCTAssertEqual(pulses(moved, track: 0, cycle: 2), 11)
    }

    /// Los Cycles inactivos no se tocan.
    func testInactiveCyclesAreLeftAlone() {
        var offset = CtrlAllOffset()
        var track = Track(cycle(pulses: 5)).withActiveCount(2)
        track = track.replacing(cycle(pulses: 12), at: 2)
        let source = Pattern().replacing(track, at: 0)

        let moved = offset.apply(2, to: .pulses, in: source)

        XCTAssertEqual(pulses(moved, track: 0, cycle: 2), 12, "tocó un Cycle inactivo")
    }

    /// Aplicar guarda la base la primera vez.
    func testApplyingCapturesTheBase() {
        var offset = CtrlAllOffset()

        _ = offset.apply(3, to: .pulses, in: pattern(pulsesPerTrack: twelve))

        XCTAssertEqual(offset.base(of: .pulses, track: 0, cycle: 0), 1)
        XCTAssertEqual(offset.amount(of: .pulses), 3)
    }

    // MARK: - Acotar sin destruir

    /// **Un Track topado no arrastra a los demás.** Cada Cycle acota contra sus
    /// propios extremos.
    func testATrackAtItsLimitDoesNotHoldTheOthersBack() {
        var offset = CtrlAllOffset()
        var source = Pattern()
        source = source.replacing(Track(cycle(pulses: 16)), at: 0)
        source = source.replacing(Track(cycle(pulses: 5)), at: 1)

        let moved = offset.apply(2, to: .pulses, in: source)

        XCTAssertEqual(pulses(moved, track: 0), 16, "el topado se pasó de su extremo")
        XCTAssertEqual(pulses(moved, track: 1), 7, "el topado arrastró al que tenía recorrido")
    }

    /// **El Track topado vuelve en cuanto el desplazamiento vuelve a entrar en
    /// su rango, y vuelve al valor exacto.**
    ///
    /// > **Lo que este test NO dice, porque se escribió creyendo lo contrario.**
    /// > El primer borrador afirmaba que el topado «se despega en el primer clic
    /// > de vuelta», y es falso: con base 16 y tres clics arriba, un clic abajo
    /// > deja el desplazamiento en +2 y `16 + 2` sigue acotado a 16. Lo que se
    /// > gana guardando base y offset por separado no es inmediatez sino
    /// > **exactitud**: el desplazamiento pedido se recuerda entero, así que
    /// > cuando vuelve a entrar en rango el Track retoma su valor real en lugar
    /// > de uno derivado de lo que cupo.
    /// >
    /// > La alternativa —aplicar el delta al valor ya acotado— es peor por otra
    /// > razón, y es la que justifica el diseño: el clic de vuelta lo bajaría a
    /// > 15 **desde el tope**, así que desandar el giro entero dejaría el Track
    /// > en 13 en vez de en 16. Perdería material de forma permanente, que es lo
    /// > que `product-guidelines.md` prohíbe.
    func testTheClampedTrackComesBackExactlyWhenTheOffsetReenters() {
        var offset = CtrlAllOffset()
        var source = Pattern()
        source = source.replacing(Track(cycle(pulses: 16)), at: 0)

        var moved = offset.apply(3, to: .pulses, in: source)
        XCTAssertEqual(pulses(moved, track: 0), 16, "se pasó de su extremo")

        // Sigue acotado mientras el desplazamiento no vuelva a entrar en rango.
        moved = offset.apply(-1, to: .pulses, in: moved)
        XCTAssertEqual(pulses(moved, track: 0), 16)

        // En cuanto entra, retoma su valor real y no uno derivado de lo que cupo.
        moved = offset.apply(-4, to: .pulses, in: moved)
        XCTAssertEqual(
            pulses(moved, track: 0), 14,
            "volvió a un valor derivado del tope en vez de al suyo")

        // Y desandar el giro entero lo devuelve exactamente a su base.
        moved = offset.apply(2, to: .pulses, in: moved)
        XCTAssertEqual(pulses(moved, track: 0), 16)
        XCTAssertEqual(offset.amount(of: .pulses), 0)
    }

    /// **Dentro del tope, la ida y vuelta es exacta** aunque por el camino algún
    /// Track haya topado contra su extremo.
    func testASweepUpAndDownWithinTheLimitIsLossless() {
        var offset = CtrlAllOffset()
        let source = pattern(pulsesPerTrack: twelve)

        var moved = source
        for _ in 0..<8 { moved = offset.apply(1, to: .pulses, in: moved) }
        for _ in 0..<8 { moved = offset.apply(-1, to: .pulses, in: moved) }

        XCTAssertEqual(offset.amount(of: .pulses), 0)
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(pulses(moved, track: index), index + 1, "Track \(index + 1)")
        }
    }

    /// **Pasado el tope ya no lo es, y no puede serlo.** Cuarenta clics arriba
    /// saturan el desplazamiento en +15; los cuarenta de vuelta parten de ahí y
    /// saturan en −11, así que el Pattern no queda donde empezó.
    ///
    /// > **No es un defecto del tope: es el tope.** Cualquier acotado del
    /// > acumulado tiene este efecto, y a cambio evita que el knob quede muerto
    /// > durante decenas de clics (FR5). **La garantía de no perder nada no vive
    /// > aquí sino en `restored(into:)`**: soltar el step 14 devuelve la base
    /// > exacta por muchas vueltas que se hayan dado, que es lo que el gesto
    /// > promete de verdad.
    func testBeyondTheLimitTheSweepDoesNotReturnButReleasingDoes() {
        var offset = CtrlAllOffset()
        let source = pattern(pulsesPerTrack: twelve)

        var moved = source
        for _ in 0..<40 { moved = offset.apply(1, to: .pulses, in: moved) }
        for _ in 0..<40 { moved = offset.apply(-1, to: .pulses, in: moved) }

        XCTAssertNotEqual(moved, source, "el tope no llegó a saturar")
        XCTAssertEqual(offset.restored(into: moved), source, "soltar no devolvió la base")
    }

    // MARK: - Rotate envuelve

    /// **Rotate envuelve con el `steps.count` de cada Cycle**, así que dos Tracks
    /// de longitud distinta se desfasan entre sí bajo el mismo desplazamiento —
    /// que es lo que se le pide a un Rotate global.
    func testRotateWrapsWithEachCyclesOwnSteps() {
        var offset = CtrlAllOffset()
        var source = Pattern()
        source = source.replacing(Track(cycle(steps: 16, rotate: 15)), at: 0)
        source = source.replacing(Track(cycle(steps: 12, rotate: 11)), at: 1)

        let moved = offset.apply(1, to: .rotate, in: source)

        XCTAssertEqual(moved.track(at: 0)?.cycle(at: 0)?.shape.rotate.amount, 0)
        XCTAssertEqual(moved.track(at: 1)?.cycle(at: 0)?.shape.rotate.amount, 0)
    }

    // MARK: - Mute no es asunto suyo

    /// Un Track muteado recibe el desplazamiento igual que los demás (FR3): el
    /// offset no consulta la máscara, que vive en `MIDI`.
    func testMutedTracksAreNotSpecialHere() {
        var offset = CtrlAllOffset()
        let moved = offset.apply(1, to: .pulses, in: pattern(pulsesPerTrack: twelve))

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(pulses(moved, track: index), index + 2)
        }
    }

    // MARK: - Un giro que no mueve nada

    /// Un delta cero devuelve el Pattern tal cual, para que quien publica lo
    /// detecte comparando, como hoy.
    func testAZeroTurnChangesNothing() {
        var offset = CtrlAllOffset()
        let source = pattern(pulsesPerTrack: twelve)

        XCTAssertEqual(offset.apply(0, to: .pulses, in: source), source)
    }
}

/// Tests del tope del desplazamiento acumulado.
///
/// **Un knob que deja de responder se lee como una avería.** Sin tope, cuarenta
/// clics contra el límite exigen cuarenta clics de vuelta antes de que algo se
/// mueva, y el síntoma —el knob no hace nada— es el mismo que produce un encoder
/// mal configurado (nota del 2026-08-28). El tope existe para que el gesto no se
/// parezca a un fallo.
final class CtrlAllOffsetLimitTests: XCTestCase {

    private func cycle(pulses: Int = 5, steps: Int = 16, rotate: Int = 0) -> Cycle {
        Cycle(
            shape: Shape(
                steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate)),
            pool: PitchPool().inserting(Pitch(48)!)
        )
    }

    private func pattern(pulsesPerTrack: [Int]) -> Pattern {
        var pattern = Pattern()
        for (index, pulses) in pulsesPerTrack.enumerated() {
            pattern = pattern.replacing(Track(cycle(pulses: pulses)), at: index)
        }
        return pattern
    }

    private func pulses(_ pattern: Pattern, track: Int) -> Int? {
        pattern.track(at: track)?.cycle(at: 0)?.shape.pulses.count
    }

    // MARK: - El recorrido de cada parámetro

    /// Cada parámetro acotado declara sus extremos; **Rotate no**, porque
    /// envuelve (FR6).
    func testEveryClampedParameterDeclaresItsRange() {
        XCTAssertEqual(TrackParameter.steps.displacementRange, 1...16)
        XCTAssertEqual(TrackParameter.pulses.displacementRange, 1...16)
        XCTAssertEqual(TrackParameter.velocity.displacementRange, 1...127)
        XCTAssertEqual(TrackParameter.probability.displacementRange, 0...100)
        XCTAssertEqual(TrackParameter.timing.displacementRange, 50...75)
        XCTAssertEqual(TrackParameter.delay.displacementRange, -100...100)
        XCTAssertNil(TrackParameter.rotate.displacementRange, "Rotate no tiene extremos")
    }

    /// Y ninguno se queda sin declararlos por olvido: si algún día se añade un
    /// parámetro, este test obliga a decidir si envuelve o se acota.
    func testEveryParameterEitherHasARangeOrWraps() {
        for parameter in TrackParameter.allCases {
            if parameter == .rotate {
                XCTAssertNil(parameter.displacementRange)
            } else {
                XCTAssertNotNil(parameter.displacementRange, "\(parameter) no declara extremos")
            }
        }
    }

    // MARK: - El tope

    /// **Cuarenta clics contra el tope y uno de vuelta mueven algo.** Es el
    /// requisito entero (FR5).
    func testFortyClicksAgainstTheLimitAndOneBackMovesSomething() {
        var offset = CtrlAllOffset()
        var moved = pattern(pulsesPerTrack: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])

        for _ in 0..<40 { moved = offset.apply(1, to: .pulses, in: moved) }
        XCTAssertEqual(
            offset.amount(of: .pulses), 15,
            "el tope no es el recorrido real: al Track de base 1 le quedaban 15")

        let before = moved
        moved = offset.apply(-1, to: .pulses, in: moved)

        XCTAssertNotEqual(moved, before, "un clic de vuelta no movió nada: el knob quedó muerto")
    }

    /// El tope es simétrico: también hacia abajo.
    func testTheLimitIsSymmetric() {
        var offset = CtrlAllOffset()
        var moved = pattern(pulsesPerTrack: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])

        for _ in 0..<40 { moved = offset.apply(-1, to: .pulses, in: moved) }
        XCTAssertEqual(
            offset.amount(of: .pulses), -11,
            "el tope se calculó con el ancho del parámetro y no con las bases: al "
                + "Track de base 12 solo le quedaban 11 hacia abajo")

        let before = moved
        moved = offset.apply(1, to: .pulses, in: moved)
        XCTAssertNotEqual(moved, before)
    }

    /// **El tope es el ancho del parámetro, no el del Track que se está
    /// mirando.** Un Track con recorrido restante sigue moviéndose mientras otro
    /// está topado.
    func testATrackWithHeadroomKeepsMovingWhileAnotherIsClamped() {
        var offset = CtrlAllOffset()
        var source = Pattern()
        source = source.replacing(Track(cycle(pulses: 16)), at: 0)
        source = source.replacing(Track(cycle(pulses: 1)), at: 1)

        var moved = source
        for _ in 0..<5 { moved = offset.apply(1, to: .pulses, in: moved) }

        XCTAssertEqual(pulses(moved, track: 0), 16, "el topado se movió")
        XCTAssertEqual(pulses(moved, track: 1), 6, "el que tenía recorrido se quedó parado")
    }

    /// **Rotate no se acota**: su desplazamiento crece libre y sigue produciendo
    /// movimiento indefinidamente, porque envuelve.
    func testRotateIsNotLimited() {
        var offset = CtrlAllOffset()
        var moved = Pattern().replacing(Track(cycle(steps: 16, rotate: 0)), at: 0)

        for _ in 0..<40 { moved = offset.apply(1, to: .rotate, in: moved) }

        XCTAssertEqual(offset.amount(of: .rotate), 40, "se acotó un parámetro que envuelve")
        XCTAssertEqual(moved.track(at: 0)?.cycle(at: 0)?.shape.rotate.amount, 40 % 16)
    }

    /// **El tope no rompe la restauración.** Con el desplazamiento saturado,
    /// soltar devuelve exactamente la base.
    func testTheLimitDoesNotBreakRestoration() {
        var offset = CtrlAllOffset()
        let source = pattern(pulsesPerTrack: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])

        var moved = source
        for _ in 0..<40 { moved = offset.apply(1, to: .pulses, in: moved) }

        XCTAssertEqual(offset.restored(into: moved), source)
    }
}

/// Tests de la restauración: soltar devuelve el Pattern, y nada más.
///
/// **Es lo que más importa que no falle.** Ctrl All promete no escribir en el
/// Pattern, y esta es la única pieza que cumple la promesa: si aquí se pierde
/// algo, el gesto habrá destruido material que costó construir y no hay deshacer.
final class CtrlAllRestoreTests: XCTestCase {

    private func cycle(
        pulses: Int = 5, velocity: Int = 64, steps: Int = 16, rotate: Int = 0
    ) -> Cycle {
        Cycle(
            shape: Shape(
                steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate)),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: Velocity(velocity)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!,
                timing: Timing(percent: 60)!,
                delay: Delay(percent: 0)!
            )
        )
    }

    /// Un Pattern con los doce Tracks distintos y varios Cycles distintos dentro.
    private func layered() -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            var track = Track(cycle(pulses: index + 1)).withActiveCount(3)
            for cycleIndex in 0..<3 {
                track = track.replacing(
                    cycle(pulses: index + 1 + cycleIndex, velocity: 40 + cycleIndex * 10),
                    at: cycleIndex)
            }
            pattern = pattern.replacing(track, at: index)
        }
        return pattern
    }

    // MARK: - Cada Cycle a su valor

    /// **Cada Cycle de cada Track recupera el suyo**, que es la razón de guardar
    /// la base por posición y no un valor único.
    func testEveryCycleOfEveryTrackComesBackToItsOwnValue() {
        var offset = CtrlAllOffset()
        let source = layered()

        let moved = offset.apply(2, to: .pulses, in: source)
        XCTAssertNotEqual(moved, source, "el gesto no movió nada")

        XCTAssertEqual(offset.restored(into: moved), source)
    }

    /// Y con varios parámetros tocados en el mismo hold, todos vuelven.
    func testSeveralTouchedParametersAllComeBack() {
        var offset = CtrlAllOffset()
        let source = layered()

        var moved = offset.apply(3, to: .pulses, in: source)
        moved = offset.apply(-10, to: .velocity, in: moved)
        moved = offset.apply(5, to: .probability, in: moved)

        XCTAssertEqual(offset.restored(into: moved), source)
    }

    /// Steps se restaura antes que Rotate, porque `setting(.rotate, to:)`
    /// envuelve contra el número de Steps que tenga el Cycle en ese momento.
    func testRestoringUsesParameterDeclarationOrder() {
        var offset = CtrlAllOffset()
        let source = Pattern().replacing(Track(cycle(steps: 8, rotate: 7)), at: 0)

        var moved = offset.apply(1, to: .rotate, in: source)
        moved = offset.apply(-4, to: .steps, in: moved)

        XCTAssertEqual(offset.restored(into: moved), source)
    }

    /// **Un parámetro no girado conserva su valor distinto por Track y por
    /// Cycle**, antes, durante y después: el desplazamiento alcanza un parámetro,
    /// no el Cycle entero.
    func testAnUntouchedParameterKeepsItsPerCycleValueThroughout() {
        var offset = CtrlAllOffset()
        let source = layered()

        let moved = offset.apply(2, to: .pulses, in: source)

        for index in 0..<Pattern.trackCount {
            for cycleIndex in 0..<3 {
                XCTAssertEqual(
                    moved.track(at: index)?.cycle(at: cycleIndex)?.groove.velocity.value,
                    40 + cycleIndex * 10,
                    "Track \(index + 1), Cycle \(cycleIndex + 1) durante el hold")
            }
        }

        XCTAssertEqual(offset.restored(into: moved), source)
    }

    // MARK: - Lo que la restauración no toca

    /// **Los cursores no retroceden.** El de reproducción avanzó durante el hold
    /// y no puede volver: restaurar el Pattern entero rebobinaría la música, que
    /// es por lo que el snapshot guarda parámetros y no Tracks.
    func testRestoringDoesNotRewindTheCursors() {
        var offset = CtrlAllOffset()
        let source = layered()

        var moved = offset.apply(2, to: .pulses, in: source)

        // La música sigue durante el hold: los cursores avanzan.
        for index in 0..<Pattern.trackCount {
            guard let track = moved.track(at: index) else { continue }
            moved = moved.replacing(track.advanced().withEditing(2), at: index)
        }

        let restored = offset.restored(into: moved)

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(restored.track(at: index)?.cursor, 1, "Track \(index + 1)")
            XCTAssertEqual(restored.track(at: index)?.editing, 2, "Track \(index + 1)")
        }
    }

    /// Y con los cursores movidos, los valores siguen volviendo a su sitio: la
    /// base se guarda por posición, no por «el Cycle que estaba sonando».
    func testValuesStillComeBackWithTheCursorsMoved() {
        var offset = CtrlAllOffset()
        let source = layered()

        var moved = offset.apply(2, to: .pulses, in: source)
        for index in 0..<Pattern.trackCount {
            guard let track = moved.track(at: index) else { continue }
            moved = moved.replacing(track.advanced(), at: index)
        }

        let restored = offset.restored(into: moved)

        for index in 0..<Pattern.trackCount {
            for cycleIndex in 0..<3 {
                XCTAssertEqual(
                    restored.track(at: index)?.cycle(at: cycleIndex)?.shape.pulses.count,
                    index + 1 + cycleIndex,
                    "Track \(index + 1), Cycle \(cycleIndex + 1)")
            }
        }
    }

    /// **Un Cycle inactivo no se toca ni al aplicar ni al restaurar.**
    func testInactiveCyclesSurviveUntouched() {
        var offset = CtrlAllOffset()
        var track = Track(cycle(pulses: 5)).withActiveCount(2)
        track = track.replacing(cycle(pulses: 13), at: 2)
        let source = Pattern().replacing(track, at: 0)

        let moved = offset.apply(2, to: .pulses, in: source)
        let restored = offset.restored(into: moved)

        XCTAssertEqual(restored.track(at: 0)?.cycle(at: 2)?.shape.pulses.count, 13)
        XCTAssertEqual(restored, source)
    }

    // MARK: - Tras un hold, el Pattern es el de partida

    /// **El criterio de aceptación entero** (AC7): tras un hold completo, el
    /// Pattern es igual al de partida salvo los cursores. Se compara el valor
    /// entero y no campo a campo, para que nada se escape por no haberlo
    /// enumerado.
    func testAfterAFullHoldThePatternEqualsTheStartingOne() {
        var offset = CtrlAllOffset()
        let source = layered()

        var moved = source
        for _ in 0..<7 { moved = offset.apply(1, to: .pulses, in: moved) }
        for _ in 0..<3 { moved = offset.apply(-1, to: .velocity, in: moved) }
        moved = offset.apply(4, to: .rotate, in: moved)

        XCTAssertEqual(offset.restored(into: moved), source)
    }

    /// Y también cuando el desplazamiento llegó a saturar (FR5b): el tope no
    /// rompe la promesa, porque lo que se guarda es la base.
    func testTheHoldIsReversibleEvenAfterSaturating() {
        var offset = CtrlAllOffset()
        let source = layered()

        var moved = source
        for _ in 0..<60 { moved = offset.apply(1, to: .pulses, in: moved) }
        for _ in 0..<60 { moved = offset.apply(-1, to: .pulses, in: moved) }

        XCTAssertEqual(offset.restored(into: moved), source)
    }
}
