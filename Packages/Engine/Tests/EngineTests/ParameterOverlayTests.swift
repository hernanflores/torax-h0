import XCTest

@testable import Engine

/// Tests del snapshot de Temp: qué se superpuso y qué había debajo.
///
/// **Lo que se prueba aquí es la memoria, no el gesto.** `ParameterOverlay`
/// guarda el valor base de los parámetros que la mano toca, por Cycle activo, y
/// no sabe nada de step buttons ni de mensajes MIDI: eso es de `ControlInput`,
/// en la fase siguiente. Aquí solo hay valor puro.
///
/// **Por qué la base se guarda por Cycle y no una sola vez.** El overlay
/// **iguala**: el parámetro girado toma el mismo valor absoluto en todos los
/// Cycles activos, así que lo que había debajo es distinto en cada uno. Un solo
/// valor no podría devolverlos (FR4).
final class ParameterOverlayTests: XCTestCase {

    // MARK: - Material de prueba

    private func cycle(pulses: Int = 5, velocity: Int = 100, pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(pitch)!),
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
    /// edición, así que hacerlo al revés los dejaría a todos iguales — que es
    /// justo lo que estos tests necesitan distinguir.
    private func track(pulsesPerCycle: [Int]) -> Track {
        var track = Track(cycle(pulses: pulsesPerCycle[0]))
            .withActiveCount(pulsesPerCycle.count)
        for (index, pulses) in pulsesPerCycle.enumerated() {
            track = track.replacing(cycle(pulses: pulses), at: index)
        }
        return track
    }

    // MARK: - El reposo

    /// **El snapshot vacío es el estado de reposo**, no un caso degenerado: es
    /// lo que hay mientras nadie mantiene el step 13.
    func testAnEmptyOverlayIsTheRestingState() {
        let overlay = ParameterOverlay()

        XCTAssertTrue(overlay.isEmpty, "el overlay recién creado dice tener algo guardado")
        XCTAssertTrue(
            overlay.parameters.isEmpty, "declara parámetros tocados sin haber tocado ninguno")
    }

    /// Restaurar desde el reposo no cambia nada. Es lo que hace seguro soltar el
    /// step 13 sin haber girado ningún knob: el gesto entero se queda en nada.
    func testRestoringFromAnEmptyOverlayChangesNothing() {
        let original = track(pulsesPerCycle: [5, 7, 9])

        let restored = ParameterOverlay().restored(into: original)

        XCTAssertEqual(restored, original, "restaurar desde el reposo movió el Track")
    }

    // MARK: - Guardar la base

    /// **La base se guarda por Cycle activo, y son valores distintos.** Es la
    /// razón de ser del tipo: el overlay va a igualarlos, así que si no se
    /// guarda uno por Cycle no hay forma de devolverlos (FR4).
    func testCapturingRecordsTheBaseValueOfEveryActiveCycle() {
        let original = track(pulsesPerCycle: [5, 7, 9])

        let overlay = ParameterOverlay().capturing(.pulses, from: original)

        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 0), 5)
        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 1), 7)
        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 2), 9)
    }

    /// Los Cycles inactivos no entran en el snapshot: el overlay no los toca, así
    /// que no hay nada suyo que devolver (NFR3, el snapshot va acotado).
    func testCapturingIgnoresInactiveCycles() {
        let original = track(pulsesPerCycle: [5, 7])

        let overlay = ParameterOverlay().capturing(.pulses, from: original)

        for index in 2..<Track.cycleCount {
            XCTAssertNil(
                overlay.base(of: .pulses, inCycle: index),
                "guardó la base del Cycle \(index + 1), que no está activo")
        }
    }

    /// **Superponer el mismo parámetro dos veces no re-guarda la base.** Es el
    /// caso normal, no el raro: girar un knob durante el hold produce un mensaje
    /// tras otro, y si cada uno reescribiera la base, el segundo guardaría el
    /// valor ya superpuesto y soltar dejaría el fill puesto para siempre.
    func testCapturingTheSameParameterTwiceKeepsTheFirstBase() {
        let original = track(pulsesPerCycle: [5, 7, 9])
        let overlay = ParameterOverlay().capturing(.pulses, from: original)

        // Entre un mensaje y el siguiente el Track ya lleva el overlay puesto.
        let overlaid = track(pulsesPerCycle: [11, 11, 11])
        let again = overlay.capturing(.pulses, from: overlaid)

        XCTAssertEqual(
            again.base(of: .pulses, inCycle: 0), 5, "la base se reescribió con el valor superpuesto"
        )
        XCTAssertEqual(again.base(of: .pulses, inCycle: 1), 7)
        XCTAssertEqual(again.base(of: .pulses, inCycle: 2), 9)
    }

    /// **Un parámetro que la mano no toca no aparece en el snapshot** (FR3). El
    /// overlay aplana un parámetro, no el Cycle: lo que no se guarda es también
    /// lo que declara no haberse tocado.
    func testAnUntouchedParameterIsNotInTheSnapshot() {
        let original = track(pulsesPerCycle: [5, 7, 9])

        let overlay = ParameterOverlay().capturing(.pulses, from: original)

        XCTAssertEqual(overlay.parameters, [.pulses])
        XCTAssertNil(overlay.base(of: .velocity, inCycle: 0), "guardó un parámetro que nadie giró")
        XCTAssertFalse(overlay.isEmpty)
    }

    /// Dos parámetros tocados conviven, cada uno con su base por Cycle.
    func testTwoTouchedParametersCoexist() {
        let original = track(pulsesPerCycle: [5, 7, 9])

        let overlay = ParameterOverlay()
            .capturing(.pulses, from: original)
            .capturing(.velocity, from: original)

        XCTAssertEqual(Set(overlay.parameters), Set([.pulses, .velocity]))
        XCTAssertEqual(overlay.base(of: .pulses, inCycle: 1), 7)
        XCTAssertEqual(overlay.base(of: .velocity, inCycle: 1), 100)
    }

    // MARK: - Genérico sobre TrackParameter

    /// **El tipo acepta cualquier caso de `TrackParameter`** (FR12), y se barre
    /// `allCases` en vez de enumerar los nueve: Accent, Repeats, Time, Voicing y
    /// Range quedan cubiertos el día que se mapeen, sin volver aquí.
    func testEveryTrackParameterCanBeCaptured() {
        let original = track(pulsesPerCycle: [5, 7, 9])

        for parameter in TrackParameter.allCases {
            let overlay = ParameterOverlay().capturing(parameter, from: original)

            XCTAssertFalse(overlay.isEmpty, "\(parameter) no se pudo superponer")
            XCTAssertEqual(overlay.parameters, [parameter])
            for index in 0..<original.activeCount {
                XCTAssertEqual(
                    overlay.base(of: parameter, inCycle: index),
                    original.cycle(at: index)?.value(of: parameter),
                    "la base guardada de \(parameter) en el Cycle \(index + 1) no es la del Track")
            }
        }
    }

    /// La lectura genérica de un parámetro es la que el knob mueve: para
    /// Division, su posición en el recorrido, y no el denominador de la fracción.
    func testTheGenericReadingIsTheKnobPosition() {
        let cycle = self.cycle(pulses: 5, velocity: 100)

        XCTAssertEqual(cycle.value(of: .steps), 16)
        XCTAssertEqual(cycle.value(of: .pulses), 5)
        XCTAssertEqual(cycle.value(of: .rotate), 0)
        XCTAssertEqual(
            cycle.value(of: .division), Division.ordered.firstIndex(of: .sixteenth),
            "Division no se lee como posición del recorrido")
        XCTAssertEqual(cycle.value(of: .velocity), 100)
        XCTAssertEqual(cycle.value(of: .sustain), 50)
        XCTAssertEqual(cycle.value(of: .probability), 100)
        XCTAssertEqual(cycle.value(of: .timing), 50, "Timing recto es 50%, no 0")
        XCTAssertEqual(cycle.value(of: .delay), 0)
    }
}
