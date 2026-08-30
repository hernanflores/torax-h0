import XCTest
@testable import Engine

/// Tests de qué parámetro de Shape cambió, conservados del renombrado.
///
/// **Eran `ShapeChangeTests` y comparaban dos Shapes.** Al renombrar
/// `ShapeChange` a `ParameterChange` en la rebanada 5 la comparación subió a
/// `Track`, porque Groove vive ahí. Estos tests se conservan enteros —mismas
/// aserciones, mismos valores esperados— envolviendo cada Shape en un Track:
/// el criterio del renombrado era que el comportamiento de Shape no cambiara, y
/// esto es lo que lo demuestra.
///
/// **Existe para el valor grande transitorio.** `product-guidelines.md` pide que
/// al girar un knob aparezca su valor en grande; para eso hay que saber cuál se
/// movió. El dato está en el dominio —dos Shapes y su diferencia—, no en la
/// vista, así que se resuelve donde hay tests.
final class ParameterChangeShapeTests: XCTestCase {

    private let base = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    /// Envuelve un Shape en un Track con el Groove por defecto, para comparar al
    /// nivel al que `ParameterChange` compara ahora.
    private func change(from previous: Shape, to current: Shape) -> ParameterChange? {
        ParameterChange(from: Track(shape: previous), to: Track(shape: current))
    }

    // MARK: - Qué cambió

    func testAChangeInStepsIsReported() {
        let moved = base.applying(-3, to: .steps)
        XCTAssertEqual(change(from: base, to: moved)?.parameter, .steps)
    }

    func testAChangeInPulsesIsReported() {
        let moved = base.applying(2, to: .pulses)
        XCTAssertEqual(change(from: base, to: moved)?.parameter, .pulses)
    }

    func testAChangeInRotateIsReported() {
        let moved = base.applying(1, to: .rotate)
        XCTAssertEqual(change(from: base, to: moved)?.parameter, .rotate)
    }

    func testAChangeInDivisionIsReported() {
        let moved = base.applying(-1, to: .division)
        XCTAssertEqual(change(from: base, to: moved)?.parameter, .division)
    }

    /// Cada parámetro se detecta al moverlo, y **solo** él: mover uno no puede
    /// hacer que se anuncie otro.
    func testEveryParameterIsDetectedAndOnlyItself() {
        for parameter in [TrackParameter.steps, .pulses, .rotate, .division] {
            for delta in [-2, -1, 1, 2] {
                let moved = base.applying(delta, to: parameter)
                guard moved != base else { continue }
                XCTAssertEqual(
                    change(from: base, to: moved)?.parameter,
                    parameter,
                    "\(parameter) con delta \(delta)"
                )
            }
        }
    }

    // MARK: - Cuando no cambió nada

    func testNoChangeIsNotAChange() {
        XCTAssertNil(change(from: base, to: base))
    }

    /// Girar contra un extremo no mueve nada, así que no hay valor que anunciar:
    /// enseñar un overlay ahí sería decir que pasó algo cuando no pasó.
    func testHittingALimitIsNotAChange() {
        let atTop = Shape(steps: Steps(16)!, pulses: Pulses(16)!)
        XCTAssertNil(change(from: atTop, to: atTop.applying(1, to: .pulses)))
    }

    // MARK: - Qué se muestra

    /// El texto es el término de la Pre Spec y el valor, sin adornos:
    /// `product-guidelines.md` pide informar, no conversar.
    func testTheChangeReadsAsTheParameterAndItsValue() {
        XCTAssertEqual(
            change(from: base, to: base.applying(2, to: .pulses))?.description, "Pulses 7")
        XCTAssertEqual(
            change(from: base, to: base.applying(-4, to: .steps))?.description, "Steps 12")
        XCTAssertEqual(
            change(from: base, to: base.applying(3, to: .rotate))?.description, "Rotate 3")
    }

    /// Division se lee como valor musical, no como un índice de la lista.
    func testDivisionReadsAsAMusicalValue() {
        let slower = Shape(steps: Steps(16)!, pulses: Pulses(5)!, division: .sixteenth)
            .applying(-1, to: .division)
        XCTAssertEqual(change(from: base, to: slower)?.description, "Division 1/8")
    }

    /// **Pulses anuncia lo que pediste, no lo que cabe.** Con Steps 4 y Pulses
    /// 9 suenan cuatro, pero el knob está en 9 y es lo que tiene que leerse: lo
    /// contrario haría creer que el valor se perdió.
    func testPulsesAnnouncesTheIntendedValueNotTheEffectiveOne() {
        let narrow = Shape(steps: Steps(4)!, pulses: Pulses(8)!)
        let change = change(from: narrow, to: narrow.applying(1, to: .pulses))
        XCTAssertEqual(change?.description, "Pulses 9")
    }
}
