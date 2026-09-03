import Engine
import SwiftUI

/// Los dieciséis Tracks como anillos concéntricos.
///
/// **Es el protagonista de la pantalla** y el núcleo de esta rebanada: la
/// diferencia entre un panel de estado y un instrumento. Hoy hay que leer para
/// saber qué Track está seleccionado y qué tiene dentro; aquí se ve de un
/// vistazo cuáles tienen material, cuál está elegido y por dónde va el tiempo.
///
/// `product-guidelines.md`: lo expresivo es el material musical, y todo lo demás
/// es soporte. La forma circular hace evidentes la naturaleza cíclica del Track
/// y la simetría del reparto euclidiano — 16/4 se ve regular, 16/5 equilibrado
/// pero asimétrico.
///
/// **No calcula nada.** Los radios y el reparto vienen de `RingStack`, y el
/// playhead de `Playhead`, ambos en `Engine` y cubiertos por tests. Aquí solo se
/// convierte fracción de vuelta en ángulo y fracción de radio en puntos.
///
/// **Un solo `Canvas` para los dieciséis** (NFR4). Dieciséis Tracks de hasta 64
/// Steps son mil posiciones por fotograma: una vista de SwiftUI por posición
/// sería mil vistas que el sistema tendría que diffear en cada redibujado, y el
/// redibujado ocurre al ritmo del reloj.
struct RingStackView: View {

    let stack: RingStack
    let selected: Int

    /// Dónde está el tiempo en cada Track, o `nil` con el transporte parado.
    ///
    /// **Uno por Track y no uno solo**: cada Track tiene su Division y sus
    /// Steps, así que sus anillos no van en fase y un playhead compartido
    /// mentiría en quince de los dieciséis.
    let playheads: [Playhead?]

    /// Cuáles se oyen. Un Track inaudible se dibuja atenuado **y su playhead
    /// sigue girando**: corre y no suena, que es exactamente lo que hace.
    ///
    /// Llega decidido desde fuera —la regla de audibilidad vive en `MIDI`, donde
    /// se testea— porque aquí solo se dibuja.
    let audible: [Bool]

    var body: some View {
        Canvas { context, size in
            let available = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            for band in stack.bands {
                draw(band, in: &context, centre: centre, available: available)
            }

            drawHub(in: &context, centre: centre, available: available)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Un anillo

    /// **El elegido en su acento; los quince restantes en gris tenue con el
    /// mismo patrón de arcos**, como el handoff especifica.
    ///
    /// Y entre los no elegidos, los que tienen material se distinguen de los
    /// vacíos sin leer texto: es la tercera lectura que la pantalla tiene que
    /// dar de un vistazo, junto a «cuál está elegido» y «por dónde va el
    /// tiempo».
    private func draw(
        _ band: RingStack.Band,
        in context: inout GraphicsContext,
        centre: CGPoint,
        available: CGFloat
    ) {
        let isSelected = band.track == selected
        let radius = available * band.radius
        let width = available * RingStack.bandWidth
        // **Atenuar el anillo, no borrarlo.** Un anillo que desapareciera diría
        // que el Track se paró, y lo que ocurre es lo contrario: sigue
        // corriendo. El playhead se dibuja aparte y a plena intensidad, que es
        // donde se ve esa diferencia.
        let heard = audible.indices.contains(band.track) ? audible[band.track] : true
        let dim = heard ? 1.0 : 0.3
        let pulseColour = pulseColour(isSelected: isSelected, hasMaterial: band.hasMaterial)
            .opacity(dim)
        let gapColour =
            (isSelected ? Palette.step.opacity(0.55) : Palette.border.opacity(0.55))
            .opacity(dim)

        // **Arcos y no puntos.** Se dibujó primero con una marca por Step, como
        // el anillo único de la v1, y con dieciséis anillos no funciona: los
        // dieciséis Tracks arrancan con los mismos 16 Steps, así que sus marcas
        // se alinean radialmente y el ojo lee dieciséis **radios** en lugar de
        // dieciséis círculos. El arco ocupa su tramo de vuelta, y un tramo
        // continuo se lee como anillo aunque el de al lado empiece en el mismo
        // ángulo. Es también lo que el handoff especifica: «a conic-gradient of
        // colored arcs vs dark gaps».
        let count = band.ring.positions.count
        let slice = 1.0 / Double(count)
        // Un respiro entre arcos para que se cuenten los Steps sin contarlos.
        let gap = min(slice * 0.18, 0.006)

        for position in band.ring.positions {
            var arc = Path()
            arc.addArc(
                center: centre,
                radius: radius,
                startAngle: .radians(angle(at: position.turn + gap / 2)),
                endAngle: .radians(angle(at: position.turn + slice - gap / 2)),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(position.isPulse ? pulseColour : gapColour),
                style: StrokeStyle(lineWidth: width, lineCap: .butt)
            )
        }

        if let playhead = playheads.indices.contains(band.track) ? playheads[band.track] : nil {
            drawPlayhead(
                playhead,
                in: &context,
                centre: centre,
                radius: radius,
                width: width,
                isSelected: isSelected
            )
        }
    }

    /// El color de un Pulse, que es donde se leen los tres estados.
    ///
    /// El acento solo lo lleva el elegido: si lo llevaran los dieciséis, el
    /// color dejaría de codificar «cuál estoy editando» y volvería a ser
    /// decoración, que es lo que `product-guidelines.md` dice que el color no es.
    private func pulseColour(isSelected: Bool, hasMaterial: Bool) -> Color {
        if isSelected { return Palette.shape }
        return hasMaterial ? Palette.step : Palette.border
    }

    // MARK: - El playhead

    /// El playhead es un arco corto **sobre su propio anillo**, no una aguja
    /// desde el centro.
    ///
    /// **Con un anillo la aguja funcionaba; con dieciséis, no.** Una aguja
    /// desde el centro cruza los dieciséis anillos y solo dice la posición del
    /// suyo, así que en cuanto dos Tracks están en Divisions distintas se ven
    /// dieciséis agujas girando a velocidades distintas sobre el mismo centro —
    /// y ninguna se puede atribuir a su anillo. El arco se lee sobre la banda a
    /// la que pertenece, que es la información que hace falta.
    ///
    /// **La legibilidad a un metro es el riesgo declarado de la rebanada**
    /// (FR2), y se juzga en dispositivo en la Fase 6. Si no se lee, la respuesta
    /// escrita es dibujar el anillo del Track elegido aparte y grande — no
    /// reducir el número de anillos.
    private func drawPlayhead(
        _ playhead: Playhead,
        in context: inout GraphicsContext,
        centre: CGPoint,
        radius: CGFloat,
        width: CGFloat,
        isSelected: Bool
    ) {
        let sweep = 0.02 * 2 * Double.pi
        let centreAngle = angle(at: playhead.turn)

        var arc = Path()
        arc.addArc(
            center: centre,
            radius: radius,
            startAngle: .radians(centreAngle - sweep / 2),
            endAngle: .radians(centreAngle + sweep / 2),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .color(.white.opacity(isSelected ? 0.95 : 0.4)),
            style: StrokeStyle(lineWidth: width, lineCap: .butt)
        )
    }

    /// El punto oscuro del centro, que el handoff dibuja y que el hueco central
    /// de `RingStack` reserva.
    private func drawHub(in context: inout GraphicsContext, centre: CGPoint, available: CGFloat) {
        let hub = available * RingStack.centreHole * 0.5
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: centre.x - hub, y: centre.y - hub, width: hub * 2, height: hub * 2
                )),
            with: .color(Palette.toolbar)
        )
    }

    // MARK: - Geometría

    /// Convierte fracción de vuelta en un ángulo.
    ///
    /// **El Step 0 arriba y el giro en sentido horario.** Es la convención del
    /// reloj, que es la metáfora que la forma circular pide prestada: si el
    /// tiempo girase al revés, la representación contradiría lo que significa.
    private func angle(at turn: Double) -> Double {
        turn * 2 * .pi - .pi / 2
    }
}
