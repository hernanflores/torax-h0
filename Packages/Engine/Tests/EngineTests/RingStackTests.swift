import XCTest

@testable import Engine

/// Tests de la geometría de los dieciséis anillos concéntricos.
///
/// **Es dominio, no presentación.** `workflow.md`: «si algo en `App` merece un
/// test, está en el sitio equivocado». Qué radio ocupa cada anillo, cuánto mide
/// una marca y dónde acaba el hueco central son invariantes que se rompen en
/// silencio —dos anillos que se solapan siguen dibujándose— así que se escriben
/// donde hay tests y no donde hay píxeles.
///
/// Todo se expresa como **fracción del radio disponible**, por la misma razón
/// que `Ring.Position.turn` es una fracción de vuelta: quien dibuja conoce el
/// tamaño de la pantalla y este tipo no.
final class RingStackTests: XCTestCase {

    // MARK: - El orden y los radios

    /// **Exterior → interior, Track 1 al 16** (FR1).
    func testTheOutermostBandIsTrackOneAndTheInnermostIsSixteen() {
        let stack = RingStack(pattern: .initial)

        XCTAssertEqual(stack.bands.count, 16)
        XCTAssertEqual(stack.bands.first?.track, 0)
        XCTAssertEqual(stack.bands.last?.track, 15)
    }

    func testRadiiDecreaseFromTheOutsideIn() {
        let stack = RingStack(pattern: .initial)

        for (outer, inner) in zip(stack.bands, stack.bands.dropFirst()) {
            XCTAssertGreaterThan(
                outer.radius, inner.radius,
                "el Track \(outer.track + 1) debería quedar por fuera del \(inner.track + 1)")
        }
    }

    /// **El hueco central no se invade.** El handoff dibuja un punto oscuro en
    /// el centro, y el playhead nace de ahí: si el anillo más interior llegara
    /// al centro, la aguja saldría de debajo de una marca.
    func testTheInnermostBandLeavesTheCentreAlone() {
        let stack = RingStack(pattern: .initial)

        XCTAssertGreaterThanOrEqual(stack.bands.last!.radius, RingStack.centreHole)
    }

    /// **Y nada se sale por fuera.** El radio disponible es 1 e incluye la marca,
    /// que se dibuja centrada sobre el anillo y sobresale medio diámetro.
    func testTheOutermostBandAndItsMarkFitInsideTheAvailableRadius() {
        let stack = RingStack(pattern: .initial)

        XCTAssertLessThanOrEqual(stack.bands.first!.radius + RingStack.pulseMarkRadius, 1)
    }

    /// **Dos anillos contiguos no se tocan.** Es la invariante que hace legible
    /// el conjunto: con dieciséis bandas, un solape de un píxel convierte el mapa
    /// en una mancha, y se rompería sin que nada fallara.
    func testAdjacentBandsDoNotOverlap() {
        XCTAssertLessThanOrEqual(RingStack.pulseMarkRadius * 2, RingStack.spacing)
    }

    // MARK: - Los radios no dependen del material

    /// **Un Track vacío ocupa su sitio igual** (FR1). Si los anillos aparecieran
    /// y desaparecieran con el material, los demás se moverían de sitio — y eso
    /// es movimiento no derivado del reloj musical, que la guía prohíbe.
    func testRadiiAreTheSameWhateverTheMaterial() {
        let empty = RingStack(pattern: Pattern())
        let populated = RingStack(pattern: .initial)

        XCTAssertEqual(empty.bands.map(\.radius), populated.bands.map(\.radius))
        XCTAssertEqual(empty.bands.count, populated.bands.count)
    }

    /// El material sí decide **cómo** se dibuja, y por eso viaja en la banda: la
    /// vista no tiene que ir a buscarlo al Pattern por su cuenta.
    func testABandKnowsWhetherItsTrackHasMaterial() {
        let stack = RingStack(pattern: .initial)

        XCTAssertTrue(stack.bands[0].hasMaterial, "el Track 1 arranca con pool")
        for band in stack.bands.dropFirst() {
            XCTAssertFalse(band.hasMaterial, "el Track \(band.track + 1) arranca vacío")
        }
    }

    // MARK: - Cada anillo reparte lo suyo

    /// **16/5 y 12/7 en dos anillos distintos dan dos repartos distintos y
    /// correctos.** Es lo que separa dieciséis anillos de un anillo repetido
    /// dieciséis veces.
    func testEachBandDistributesItsOwnSteps() {
        let pattern = Pattern()
            .replacing(Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)), at: 0)
            .replacing(Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!)), at: 1)
        let stack = RingStack(pattern: pattern)

        XCTAssertEqual(stack.bands[0].ring.positions.count, 16)
        XCTAssertEqual(stack.bands[1].ring.positions.count, 12)

        XCTAssertEqual(stack.bands[0].ring.positions.filter(\.isPulse).count, 5)
        XCTAssertEqual(stack.bands[1].ring.positions.filter(\.isPulse).count, 7)
    }

    /// El anillo de cada banda es exactamente el que `Ring` construye para ese
    /// Shape: aquí no se reparte nada otra vez, que es la regla que `Ring` ya
    /// documenta —dos algoritmos podrían discrepar—.
    func testTheBandsRingIsTheOneRingBuildsForThatShape() {
        let shape = Shape(steps: Steps(12)!, pulses: Pulses(7)!, rotate: Rotate(3))
        let pattern = Pattern().replacing(Cycle(shape: shape), at: 4)

        XCTAssertEqual(RingStack(pattern: pattern).bands[4].ring, Ring(shape: shape))
    }

    // MARK: - Escalar

    /// **La geometría es una fracción, así que escalar es multiplicar.**
    ///
    /// El tipo no guarda ningún píxel: todos sus radios caben en `(0, 1]`, y
    /// dibujar a cualquier tamaño es multiplicar por el radio disponible. Si
    /// alguna vez alguien mete aquí un valor en puntos, este test lo ve.
    func testEveryRadiusIsAFractionOfTheAvailableRadius() {
        for band in RingStack(pattern: .initial).bands {
            XCTAssertGreaterThan(band.radius, 0, "Track \(band.track + 1)")
            XCTAssertLessThanOrEqual(band.radius, 1, "Track \(band.track + 1)")
        }

        XCTAssertLessThanOrEqual(RingStack.pulseMarkRadius, 1)
        XCTAssertLessThanOrEqual(RingStack.centreHole, 1)
    }

    /// **Las bandas quedan repartidas a paso constante**, que es lo que hace que
    /// dieciséis anillos se lean como una escala y no como un montón. El paso es
    /// el mismo entre cualquier par contiguo.
    func testTheBandsAreEvenlySpaced() {
        let radii = RingStack(pattern: .initial).bands.map(\.radius)

        for (outer, inner) in zip(radii, radii.dropFirst()) {
            XCTAssertEqual(outer - inner, RingStack.spacing, accuracy: 0.000_001)
        }
    }

    /// Las marcas de Pulse son mayores que las de Step vacío: es lo que hace que
    /// el reparto se lea antes que el conteo.
    func testAPulseMarkIsLargerThanAnEmptyStepMark() {
        XCTAssertGreaterThan(RingStack.pulseMarkRadius, RingStack.stepMarkRadius)
        XCTAssertGreaterThan(RingStack.stepMarkRadius, 0)
    }

    /// **El arco de una banda no llega a tocar el de la de al lado.** Es la misma
    /// invariante que `testAdjacentBandsDoNotOverlap`, sobre el grosor con el que
    /// se dibuja de verdad: la separación oscura entre bandas es lo que las hace
    /// contables, y sin ella dieciséis anillos son un disco.
    func testABandsArcLeavesADarkGapToTheNextOne() {
        XCTAssertLessThan(RingStack.bandWidth, RingStack.spacing)
        XCTAssertGreaterThan(RingStack.bandWidth, 0)
    }

    /// Un índice fuera de rango no existe: las bandas son exactamente dieciséis,
    /// como los Tracks, y no hay una decimoséptima que dibujar.
    func testThereIsNoSeventeenthBand() {
        XCTAssertEqual(RingStack(pattern: .initial).bands.count, Pattern.trackCount)
        XCTAssertNil(RingStack(pattern: .initial).bands.first { $0.track >= Pattern.trackCount })
    }
}
