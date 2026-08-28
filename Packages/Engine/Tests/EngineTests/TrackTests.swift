import XCTest
@testable import Engine

/// Tests del estado del Track y de la familia Shape.
///
/// La Pre Spec ordena el modelo así: el Track «es donde residen los parámetros
/// generativos», y Shape es la familia que «decide *cuándo* y con qué densidad
/// ocurren eventos» — Steps, Pulses, Rotate y Division. Estos tests fijan esa
/// jerarquía y comprueban que el Track resuelve qué Steps disparan.
final class TrackTests: XCTestCase {

    private func shape(
        steps stepCount: Int,
        pulses pulseCount: Int,
        rotate amount: Int = 0,
        division: Division = .sixteenth
    ) -> Shape {
        let steps = Steps(stepCount)!
        return Shape(
            steps: steps,
            pulses: Pulses(pulseCount)!,
            rotate: Rotate(amount),
            division: division
        )
    }

    // MARK: - Shape expone los parámetros de la Pre Spec

    func testShapeCarriesItsFourParameters() {
        let shape = shape(steps: 12, pulses: 7, rotate: 3, division: .eighth)
        XCTAssertEqual(shape.steps.count, 12)
        XCTAssertEqual(shape.pulses.count, 7)
        XCTAssertEqual(shape.rotate, Rotate(3))
        XCTAssertEqual(shape.division, .eighth)
    }

    /// Default del producto, según la Pre Spec: «Division. Default: 1/16».
    func testShapeDefaultsToSixteenthDivision() {
        let steps = Steps(16)!
        let shape = Shape(steps: steps, pulses: Pulses(4)!)
        XCTAssertEqual(shape.division, .sixteenth)
        XCTAssertEqual(shape.rotate, .none)
    }

    // MARK: - El Track resuelve qué Steps disparan

    /// El caso 16/4 de la Pre Spec, leído a través del Track.
    func testTrackResolvesTheEuclideanPattern() {
        let track = Track(shape: shape(steps: 16, pulses: 4))
        XCTAssertEqual(triggerPattern(of: track), "x...x...x...x...")
    }

    /// El Track combina Shape y Rotate: no se queda con el reparto sin girar.
    func testTrackCombinesShapeAndRotate() {
        let track = Track(shape: shape(steps: 16, pulses: 5, rotate: 2))
        XCTAssertEqual(triggerPattern(of: track), "..x..x..x..x..x.")
    }

    /// El Track hereda la envoltura del anillo: el scheduler cuenta Steps hacia
    /// arriba sin volver a cero.
    func testTrackWrapsTheStepIndexOverTheRing() {
        let track = Track(shape: shape(steps: 12, pulses: 7, rotate: 4))
        for index in 0..<12 {
            XCTAssertEqual(track.triggers(atStep: index + 12), track.triggers(atStep: index))
            XCTAssertEqual(track.triggers(atStep: index - 12), track.triggers(atStep: index))
        }
    }

    // MARK: - Valor inmutable

    /// Semántica de valor: copiar un Track y cambiar la copia no toca al
    /// original. Es lo que permite publicar snapshots al scheduler sin lock.
    func testTrackHasValueSemantics() {
        let original = Track(shape: shape(steps: 16, pulses: 4))
        var copy = original
        copy = Track(shape: shape(steps: 16, pulses: 5))

        XCTAssertEqual(triggerPattern(of: original), "x...x...x...x...")
        XCTAssertEqual(triggerPattern(of: copy), "x..x..x..x..x...")
        XCTAssertNotEqual(original, copy)
    }

    func testEqualTracksAreEqual() {
        XCTAssertEqual(
            Track(shape: shape(steps: 12, pulses: 7, rotate: 3)),
            Track(shape: shape(steps: 12, pulses: 7, rotate: 3))
        )
    }

    func testTracksDifferingOnlyInDivisionAreNotEqual() {
        XCTAssertNotEqual(
            Track(shape: shape(steps: 16, pulses: 4, division: .sixteenth)),
            Track(shape: shape(steps: 16, pulses: 4, division: .eighth))
        )
    }

    /// Comprobación en tiempo de compilación: el estado tiene que poder cruzar
    /// al hilo del scheduler como valor.
    func testTrackAndShapeAreSendable() {
        assertSendable(Track.self)
        assertSendable(Shape.self)
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    // MARK: - Determinismo

    /// No hay aleatorio en esta rebanada: mismo Track, misma salida siempre.
    func testTrackIsDeterministic() {
        let track = Track(shape: shape(steps: 12, pulses: 7, rotate: 5))
        let first = triggerPattern(of: track)
        for _ in 0..<100 {
            XCTAssertEqual(triggerPattern(of: track), first)
        }
    }

    // MARK: - Helper

    private func triggerPattern(of track: Track) -> String {
        (0..<track.shape.steps.count)
            .map { track.triggers(atStep: $0) ? "x" : "." }
            .joined()
    }
}
