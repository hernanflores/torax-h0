import XCTest

@testable import Engine

/// Tests del distintivo de Ctrl All en el panel de lectura (FR16, NFR1).
///
/// **La pantalla ya enseña lo que suena sin hacer nada**, igual que con Temp: el
/// desplazamiento se escribe en el `Pattern` publicado, así que la lectura, los
/// anillos y el valor grande lo recogen por el camino de siempre. Lo que falta es
/// decir **qué gesto** lo puso.
///
/// **Y aquí un distintivo compartido no serviría.** Temp y Ctrl All son
/// reversibles los dos, así que marcar «esto es temporal» no distingue lo único
/// que el usuario necesita saber con las manos ocupadas: si lo que está moviendo
/// es un Track o los doce. Por eso el marcador deja de salir de un `Bool`.
final class FamilyReadoutCtrlAllTests: XCTestCase {

    private let track = Cycle(
        shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
        pool: PitchPool().inserting(Pitch(48)!),
        frame: TonalFrame(scale: .minor, root: .c)
    )

    // MARK: - Los tres estados

    /// En reposo no hay distintivo.
    func testAtRestThereIsNoMarker() {
        for family in ParameterFamily.allCases {
            XCTAssertNil(FamilyReadout(track: track, family: family, gesture: .none).marker)
        }
    }

    /// Con Temp, el distintivo es «Temp» — el término que ancla la Pre Spec.
    func testTempKeepsItsMarker() {
        for family in ParameterFamily.allCases {
            XCTAssertEqual(
                FamilyReadout(track: track, family: family, gesture: .temp).marker, "Temp",
                "\(family)")
        }
    }

    /// **Con Ctrl All, el distintivo es «Ctrl All»**, literal (NFR7). No
    /// «global», no «all», no un icono: lo que se lee es lo que el usuario usará
    /// para pensarlo.
    func testCtrlAllHasItsOwnMarker() {
        for family in ParameterFamily.allCases {
            XCTAssertEqual(
                FamilyReadout(track: track, family: family, gesture: .ctrlAll).marker, "Ctrl All",
                "\(family)")
        }
    }

    /// **Y los dos distintivos son distintos**, que es el requisito entero: un
    /// marcador compartido no diría si se está moviendo un Track o los doce.
    func testTheTwoMarkersAreDistinguishable() {
        let temp = FamilyReadout(track: track, family: .shape, gesture: .temp).marker
        let ctrlAll = FamilyReadout(track: track, family: .shape, gesture: .ctrlAll).marker

        XCTAssertNotNil(temp)
        XCTAssertNotNil(ctrlAll)
        XCTAssertNotEqual(temp, ctrlAll, "los dos gestos se leen igual en pantalla")
    }

    /// **Sale en las tres familias**, porque el gesto alcanza a los nueve
    /// parámetros: depender del tab que se esté mirando lo dejaría sin marcar en
    /// dos de cada tres pantallas.
    func testTheMarkerAppearsInEveryFamily() {
        for family in ParameterFamily.allCases {
            XCTAssertNotNil(
                FamilyReadout(track: track, family: family, gesture: .ctrlAll).marker, "\(family)")
        }
    }

    /// El gesto no cambia el texto de la lectura: lo que se lee es el valor, que
    /// ya llega desplazado por el Pattern publicado.
    func testTheGestureDoesNotChangeTheReadingItself() {
        let resting = FamilyReadout(track: track, family: .shape, gesture: .none)
        let moved = FamilyReadout(track: track, family: .shape, gesture: .ctrlAll)

        XCTAssertEqual(resting.headline, moved.headline)
        XCTAssertEqual(resting.detail, moved.detail)
    }

    /// **Ningún gesto se queda sin decidir su marca.** Si algún día hay un
    /// cuarto modificador, este test obliga a elegirle una.
    func testEveryGestureDeclaresWhetherItMarks() {
        for gesture in ReadoutGesture.allCases {
            let marker = FamilyReadout(track: track, family: .shape, gesture: gesture).marker
            if gesture == .none {
                XCTAssertNil(marker)
            } else {
                XCTAssertNotNil(marker, "\(gesture) no declara distintivo")
            }
        }
    }
}
