import XCTest

@testable import Engine

/// Tests del distintivo de Temp en el panel de lectura (FR10, NFR1).
///
/// **La pantalla ya enseña lo que suena sin hacer nada.** El overlay se escribe
/// en el `Pattern` publicado, así que la lectura, el anillo y el valor grande
/// transitorio recogen los valores superpuestos por el camino de siempre. Lo que
/// falta es decir que son **temporales**: sin distintivo, un fill puesto y una
/// edición permanente se leen exactamente igual, y el usuario no puede saber si
/// lo que ve sobrevivirá a soltar el botón.
///
/// **El distintivo se decide aquí y no en la vista** (NFR1). Es texto de
/// dominio, y `workflow.md` manda que lo calculable no viva en `App`, donde no
/// hay tests.
final class FamilyReadoutTempTests: XCTestCase {

    private let track = Cycle(
        shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
        pool: PitchPool().inserting(Pitch(48)!),
        frame: TonalFrame(scale: .minor, root: .c)
    )

    // MARK: - Con overlay y sin él

    /// **En reposo no hay distintivo.** Es el estado normal, y marcar algo que
    /// no es temporal sería peor que no marcar nada.
    func testWithoutTheOverlayThereIsNoMarker() {
        for family in ParameterFamily.allCases {
            let readout = FamilyReadout(track: track, family: family)

            XCTAssertNil(readout.marker, "\(family) sacó distintivo sin overlay puesto")
        }
    }

    /// **Con el overlay puesto, el distintivo aparece en las tres familias.**
    /// Temp alcanza a los nueve parámetros, así que no puede depender de qué tab
    /// se esté mirando.
    func testWithTheOverlayEveryFamilyShowsTheMarker() {
        for family in ParameterFamily.allCases {
            let readout = FamilyReadout(track: track, family: family, gesture: .temp)

            XCTAssertEqual(readout.marker, "Temp", "\(family) no sacó el distintivo")
        }
    }

    /// **El término es «Temp»** (NFR6), el mismo que la Pre Spec ancla: ni
    /// «momentary», ni «override», ni «latch». Un concepto, un nombre — y el
    /// nombre que se lee en pantalla es el que el usuario va a usar para
    /// pensarlo.
    func testTheMarkerUsesTheAnchoredTerm() {
        let readout = FamilyReadout(track: track, family: .shape, gesture: .temp)

        XCTAssertEqual(readout.marker, "Temp")
    }

    // MARK: - Lo que el distintivo no cambia

    /// **El distintivo no toca la lectura.** Los valores que se enseñan son los
    /// superpuestos, que son los que suenan (FR10), y se escriben igual que
    /// cualquier otro: el overlay ya está dentro del Cycle que llega aquí.
    func testTheMarkerDoesNotChangeTheReading() {
        for family in ParameterFamily.allCases {
            let resting = FamilyReadout(track: track, family: family)
            let temporary = FamilyReadout(track: track, family: family, gesture: .temp)

            XCTAssertEqual(
                temporary.headline, resting.headline, "\(family) cambió la lectura grande")
            XCTAssertEqual(temporary.detail, resting.detail, "\(family) cambió la línea de detalle")
        }
    }

    /// Y la lectura sigue siendo la del Cycle que se le pasa: con el overlay
    /// puesto, el Cycle ya lleva los valores superpuestos, así que enseñarlos no
    /// exige ningún camino aparte.
    func testTheReadingIsAlwaysThatOfTheCycleGiven() {
        let overlaid = track.setting(.pulses, to: 9)

        let readout = FamilyReadout(track: overlaid, family: .shape, gesture: .temp)

        XCTAssertEqual(readout.headline, "Pulses 9")
    }
}
