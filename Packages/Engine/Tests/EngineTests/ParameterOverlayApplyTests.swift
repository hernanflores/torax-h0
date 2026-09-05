import XCTest

@testable import Engine

/// Tests de lo que Temp le hace al Track: superponer e igualar, acumular, y
/// devolver a cada Cycle **el suyo**.
///
/// **Lo que más importa que no falle es la reversión.** Un fill que entra y no
/// se va destruye el Pattern que costó construir, y no hay deshacer. De ahí que
/// la mitad de estos tests miren lo que *no* cambia.
///
/// El gesto —quién mantiene el step 13— es de `ControlInput`, en la fase
/// siguiente. Aquí solo hay valor puro.
final class ParameterOverlayApplyTests: XCTestCase {

    // MARK: - Material de prueba

    private func cycle(
        pulses: Int = 5,
        velocity: Int = 100,
        pool: PitchPool = PitchPool().inserting(Pitch(48)!)
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: pool,
            groove: Groove(
                velocity: Velocity(velocity)!,
                sustain: Sustain(percent: 50)!,
                probability: Probability(percent: 100)!,
                timing: Timing(percent: 50)!,
                delay: Delay(percent: 0)!
            )
        )
    }

    /// Un Track con un Cycle distinto en cada hueco activo. Ver la nota del
    /// helper homónimo en `ParameterOverlayTests`: el orden importa.
    private func track(pulsesPerCycle: [Int], velocityPerCycle: [Int]? = nil) -> Track {
        let velocities = velocityPerCycle ?? Array(repeating: 100, count: pulsesPerCycle.count)
        var track = Track(cycle()).withActiveCount(pulsesPerCycle.count)
        for (index, pulses) in pulsesPerCycle.enumerated() {
            track = track.replacing(cycle(pulses: pulses, velocity: velocities[index]), at: index)
        }
        return track
    }

    // MARK: - Igualar, que no es aplanar

    /// **FR2 — el overlay iguala.** Un delta produce un valor absoluto calculado
    /// desde el **Cycle en edición**, y ese valor se escribe igual en todos los
    /// activos. Es lo que hace que el fill se oiga aunque el cursor cruce de
    /// Cycle a media vuelta.
    func testApplyingWritesTheSameAbsoluteValueInEveryActiveCycle() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        var overlay = ParameterOverlay()

        // El Cycle en edición es el 0, con Pulses 5: +2 apunta a 7.
        let overlaid = overlay.apply(2, to: .pulses, in: original)

        for index in 0..<3 {
            XCTAssertEqual(
                overlaid.cycle(at: index)?.value(of: .pulses), 7,
                "el Cycle \(index + 1) no quedó igualado")
        }
    }

    /// El valor absoluto sale del Cycle **en edición**, no del que suena ni del
    /// primero. Es donde está la mano.
    func testTheAbsoluteValueIsComputedFromTheEditingCycle() {
        let original = track(pulsesPerCycle: [5, 7, 9]).withEditing(2)
        var overlay = ParameterOverlay()

        // El Cycle en edición es el 2, con Pulses 9: +1 apunta a 10.
        let overlaid = overlay.apply(1, to: .pulses, in: original)

        for index in 0..<3 {
            XCTAssertEqual(overlaid.cycle(at: index)?.value(of: .pulses), 10)
        }
    }

    /// **Los Cycles inactivos no se tocan.** El overlay alcanza a lo que se
    /// recorre; el resto es material que nadie pidió mover.
    func testInactiveCyclesAreUntouched() {
        let original = track(pulsesPerCycle: [5, 7])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(3, to: .pulses, in: original)

        for index in 2..<Track.cycleCount {
            XCTAssertEqual(
                overlaid.cycle(at: index), original.cycle(at: index),
                "el Cycle inactivo \(index + 1) se movió")
        }
    }

    /// **FR3 — solo lo que la mano toca.** Un parámetro no girado conserva su
    /// valor distinto en cada Cycle **durante** el hold: el overlay aplana un
    /// parámetro, no el Cycle.
    func testAnUntouchedParameterKeepsItsPerCycleValueDuringTheHold() {
        let original = track(pulsesPerCycle: [5, 7, 9], velocityPerCycle: [80, 100, 120])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(2, to: .pulses, in: original)

        XCTAssertEqual(overlaid.cycle(at: 0)?.value(of: .velocity), 80)
        XCTAssertEqual(overlaid.cycle(at: 1)?.value(of: .velocity), 100)
        XCTAssertEqual(overlaid.cycle(at: 2)?.value(of: .velocity), 120)
    }

    // MARK: - Acumular

    /// **FR2 — girar dos veces acumula sobre el valor superpuesto**, no sobre el
    /// base. Si acumulara sobre el base, seguir girando no movería nada después
    /// del primer clic.
    func testTurningTwiceAccumulatesOnTheOverlaidValue() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        var overlay = ParameterOverlay()

        let once = overlay.apply(2, to: .pulses, in: original)
        let twice = overlay.apply(3, to: .pulses, in: once)

        // 5 -> 7 -> 10, y no 5 -> 7 -> 8.
        for index in 0..<3 {
            assertOverlaidPulses(twice, inCycle: index, are: 10)
        }
    }

    /// Y la base sigue siendo la de antes del hold, no la del giro intermedio.
    func testAccumulatingKeepsTheOriginalBase() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        var overlay = ParameterOverlay()

        let once = overlay.apply(2, to: .pulses, in: original)
        _ = overlay.apply(3, to: .pulses, in: once)

        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 0), 5)
        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 1), 7)
        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 2), 9)
    }

    // MARK: - Los extremos

    /// **FR9 — un delta contra un extremo no cambia el Track**, y se puede
    /// detectar sin publicar: comparar el Track de antes con el de después es la
    /// misma prueba que ya usa `ParameterChange`.
    func testADeltaAgainstAnExtremeChangesNothing() {
        // Pulses tope en 16, y los tres Cycles ya están ahí.
        let original = track(pulsesPerCycle: [16, 16, 16])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(1, to: .pulses, in: original)

        XCTAssertEqual(overlaid, original, "girar contra el tope movió el Track")
    }

    /// Un delta nulo tampoco mueve nada.
    func testAZeroDeltaChangesNothing() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(0, to: .pulses, in: original)

        XCTAssertEqual(overlaid, original)
    }

    /// **Igualar sigue al Cycle en edición: si él no se mueve, no se mueve
    /// nadie.** Con el Cycle en edición ya en el tope y los otros dos abajo, un
    /// giro más no los sube hasta él.
    ///
    /// Es la decisión que hace verdad a FR9 con el overlay puesto. Igualar de
    /// todas formas aplanaría dos Cycles sin que nadie hubiera girado nada — un
    /// cambio que el usuario no pidió y no vería venir — y además obligaría a
    /// publicar en un giro contra el tope, que hoy no publica. No se pierde
    /// nada: la igualación ya ocurrió en el giro que sí movió el Cycle en
    /// edición.
    func testATurnAgainstTheExtremeDoesNotEqualiseTheOthers() {
        let original = track(pulsesPerCycle: [16, 7, 9])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(1, to: .pulses, in: original)

        XCTAssertEqual(
            overlaid, original, "un giro que no mueve el Cycle en edición movió los otros")
        XCTAssertTrue(overlay.isEmpty, "un giro que no cambia nada guardó una base")
    }

    /// Y en cuanto el Cycle en edición sí se mueve, los otros lo alcanzan —
    /// incluso si el destino es el tope.
    func testTheOthersCatchUpAsSoonAsTheEditingCycleMoves() {
        let original = track(pulsesPerCycle: [15, 7, 9])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(1, to: .pulses, in: original)

        for index in 0..<3 {
            XCTAssertEqual(overlaid.cycle(at: index)?.value(of: .pulses), 16)
        }
    }

    // MARK: - Restaurar

    /// **FR4 — cada Cycle recupera EL SUYO.** Es la razón por la que la base se
    /// guarda por Cycle, y el test que la justifica: con un valor único, los
    /// tres volverían a 5.
    func testRestoringReturnsEachCycleToItsOwnValue() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        var overlay = ParameterOverlay()

        let overlaid = overlay.apply(2, to: .pulses, in: original)
        let restored = overlay.restored(into: overlaid)

        XCTAssertEqual(restored.cycle(at: 0)?.value(of: .pulses), 5)
        XCTAssertEqual(restored.cycle(at: 1)?.value(of: .pulses), 7)
        XCTAssertEqual(restored.cycle(at: 2)?.value(of: .pulses), 9)
    }

    /// **FR5 — tras un hold completo el Track es el de partida.** Varios giros,
    /// varios parámetros, y al soltar no queda rastro.
    func testAFullHoldLeavesTheTrackAsItWas() {
        let original = track(pulsesPerCycle: [5, 7, 9], velocityPerCycle: [80, 100, 120])
        var overlay = ParameterOverlay()

        var held = overlay.apply(2, to: .pulses, in: original)
        held = overlay.apply(-3, to: .pulses, in: held)
        held = overlay.apply(20, to: .velocity, in: held)
        let restored = overlay.restored(into: held)

        XCTAssertEqual(restored, original, "el hold dejó rastro en el Track")
    }

    /// **Un parámetro no tocado conserva su valor por Cycle antes, durante y
    /// después** (FR3). El de arriba lo comprueba durante; éste, después.
    func testAnUntouchedParameterSurvivesTheWholeHold() {
        let original = track(pulsesPerCycle: [5, 7, 9], velocityPerCycle: [80, 100, 120])
        var overlay = ParameterOverlay()

        let held = overlay.apply(2, to: .pulses, in: original)
        let restored = overlay.restored(into: held)

        XCTAssertEqual(restored.cycle(at: 0)?.value(of: .velocity), 80)
        XCTAssertEqual(restored.cycle(at: 1)?.value(of: .velocity), 100)
        XCTAssertEqual(restored.cycle(at: 2)?.value(of: .velocity), 120)
    }

    /// **FR4 — restaurar devuelve los parámetros tocados y NADA MÁS.**
    ///
    /// El cursor de reproducción avanzó durante el hold y no puede retroceder:
    /// un snapshot literal del Track rebobinaría la música. Aquí se avanza el
    /// cursor a propósito entre superponer y restaurar, que es lo que pasa de
    /// verdad si el transporte está corriendo.
    func testRestoringTouchesNeitherCursorNorMaterial() {
        let pool = PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!)
        var original = Track(
            cycle(pool: pool)
        ).withActiveCount(3).withEditing(1)
        original = original.replacing(
            original.editingCycle.with(channel: Channel(10)!, padOctaveShift: 2), at: 1)

        var overlay = ParameterOverlay()
        let held = overlay.apply(2, to: .pulses, in: original)

        // El scheduler mueve el cursor mientras dura el hold.
        let advanced = held.advanced().advanced()
        let restored = overlay.restored(into: advanced)

        XCTAssertEqual(
            restored.cursor, advanced.cursor, "restaurar rebobinó el cursor de reproducción")
        XCTAssertEqual(restored.editing, 1, "restaurar movió el cursor de edición")
        XCTAssertEqual(restored.activeCount, 3, "restaurar cambió cuántos Cycles se recorren")

        let cycle = restored.cycle(at: 1)
        XCTAssertEqual(cycle?.pool, pool, "restaurar tocó el pool")
        XCTAssertEqual(cycle?.frame, original.cycle(at: 1)?.frame, "restaurar tocó el marco tonal")
        XCTAssertEqual(cycle?.channel, Channel(10)!, "restaurar tocó el canal")
        XCTAssertEqual(cycle?.padOctaveShift, 2, "restaurar tocó el registro de pads")
    }

    // MARK: - Genérico

    /// El ciclo completo —superponer y restaurar— funciona con **cualquier**
    /// `TrackParameter` (FR12), no solo con los que resultan cómodos de probar.
    func testTheWholeCycleWorksForEveryTrackParameter() {
        let original = track(pulsesPerCycle: [5, 7, 9], velocityPerCycle: [80, 100, 120])

        for parameter in TrackParameter.allCases {
            var overlay = ParameterOverlay()
            let held = overlay.apply(1, to: parameter, in: original)
            let restored = overlay.restored(into: held)

            XCTAssertEqual(restored, original, "\(parameter) no volvió a su sitio al restaurar")
        }
    }

    // MARK: - Ayudas

    private func assertOverlaidPulses(
        _ track: Track, inCycle index: Int, are expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            track.cycle(at: index)?.value(of: .pulses), expected,
            "el Cycle \(index + 1) no acumuló sobre el valor superpuesto",
            file: file, line: line)
    }
}
