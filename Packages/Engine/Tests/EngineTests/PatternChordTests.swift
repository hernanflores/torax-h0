import XCTest

@testable import Engine

/// Tests de la regla del acorde de dos dedos sobre la rejilla de Patterns.
///
/// **La regla vive aquí y no en la vista** (NFR1). La pantalla traduce toques a
/// eventos y no decide nada; decidir es lo que se puede probar, y `App` no se
/// mide. Es el mismo movimiento que hizo `PatternSlotState` el 2026-09-07.
///
/// El gesto: mantener el origen y tocar el destino copia en el acto. Se consume
/// en el `down` del segundo dedo —no al levantar—, que es lo que hace que el
/// orden de levantada dé igual (FR17).
final class PatternChordTests: XCTestCase {

    /// Un solo `down` no hace nada todavía: aún no se sabe si es un toque o la
    /// primera mitad de un acorde.
    func testALoneDownHasNoEffectYet() {
        var chord = PatternChord()
        XCTAssertEqual(chord.pressing(3), .none)
    }

    /// Y al levantar, selecciona: es el comportamiento de siempre (FR20).
    func testALoneTouchSelectsOnTheWayUp() {
        var chord = PatternChord()
        _ = chord.pressing(3)
        XCTAssertEqual(chord.releasing(3), .select(3))
    }

    /// **El acorde copia en el `down` del segundo dedo**, no al levantar.
    func testTheSecondDownCopies() {
        var chord = PatternChord()
        _ = chord.pressing(0)
        XCTAssertEqual(chord.pressing(2), .copy(from: 0, to: 2))
    }

    /// **El orden de levantada es indiferente** (FR17): consumido el acorde,
    /// ningún `up` tiene efecto. Ni el del origen primero, ni el del destino.
    func testTheReleaseOrderDoesNotMatter() {
        var originFirst = PatternChord()
        _ = originFirst.pressing(0)
        _ = originFirst.pressing(2)
        XCTAssertEqual(originFirst.releasing(0), .none)
        XCTAssertEqual(originFirst.releasing(2), .none)

        var destinationFirst = PatternChord()
        _ = destinationFirst.pressing(0)
        _ = destinationFirst.pressing(2)
        XCTAssertEqual(destinationFirst.releasing(2), .none)
        XCTAssertEqual(destinationFirst.releasing(0), .none)
    }

    /// Un tercer dedo con dos ya abajo se ignora: el acorde son dos.
    func testAThirdDownIsIgnored() {
        var chord = PatternChord()
        _ = chord.pressing(0)
        _ = chord.pressing(2)
        XCTAssertEqual(chord.pressing(5), .none)
    }

    /// Dos dedos en la misma celda no copian sobre sí misma.
    func testTwoFingersOnTheSameSlotDoNotCopy() {
        var chord = PatternChord()
        _ = chord.pressing(4)
        XCTAssertEqual(chord.pressing(4), .none)
    }

    /// **Levantados todos los dedos, el gesto siguiente empieza limpio.**
    func testTheNextGestureStartsFresh() {
        var chord = PatternChord()
        _ = chord.pressing(0)
        _ = chord.pressing(2)
        _ = chord.releasing(0)
        _ = chord.releasing(2)

        XCTAssertEqual(chord.pressing(7), .none)
        XCTAssertEqual(chord.releasing(7), .select(7))
    }

    /// Un toque que se cancela —se levanta fuera de su celda— no selecciona
    /// (FR21).
    func testACancelledTouchDoesNotSelect() {
        var chord = PatternChord()
        _ = chord.pressing(3)
        XCTAssertEqual(chord.cancelling(3), .none)
    }

    /// Y después de una cancelación el gesto siguiente vuelve a empezar limpio.
    func testAfterACancellationTheNextGestureStartsFresh() {
        var chord = PatternChord()
        _ = chord.pressing(3)
        _ = chord.cancelling(3)

        XCTAssertEqual(chord.pressing(9), .none)
        XCTAssertEqual(chord.releasing(9), .select(9))
    }

    /// Cancelar el segundo dedo después de que el acorde copiara no deshace
    /// nada: la copia ya ocurrió y no hay vuelta atrás en esta regla.
    func testCancellingAfterTheChordHasNoEffect() {
        var chord = PatternChord()
        _ = chord.pressing(0)
        _ = chord.pressing(2)
        XCTAssertEqual(chord.cancelling(2), .none)
        XCTAssertEqual(chord.releasing(0), .none)
    }

    /// Levantar una celda que nunca se pulsó no hace nada.
    func testReleasingAnUntouchedSlotDoesNothing() {
        var chord = PatternChord()
        XCTAssertEqual(chord.releasing(6), .none)

        _ = chord.pressing(1)
        XCTAssertEqual(chord.releasing(8), .none)
    }

    /// El acorde entre dos huecos cualesquiera, en las dos direcciones.
    func testTheChordCopiesInEitherDirection() {
        var upwards = PatternChord()
        _ = upwards.pressing(1)
        XCTAssertEqual(upwards.pressing(15), .copy(from: 1, to: 15))

        var downwards = PatternChord()
        _ = downwards.pressing(15)
        XCTAssertEqual(downwards.pressing(1), .copy(from: 15, to: 1))
    }
}
