import Engine
import SwiftUI

/// El anillo del Track: dónde cae cada Step, cuáles disparan y dónde está el
/// tiempo.
///
/// **Es el protagonista de la pantalla.** `product-guidelines.md`: lo expresivo
/// es el material musical, y todo lo demás es soporte. La forma circular hace
/// evidentes la naturaleza cíclica del Track y la simetría del reparto
/// euclidiano — 16/4 se ve regular, 16/5 equilibrado pero asimétrico.
///
/// **No calcula nada.** Las posiciones y las marcas vienen de `Ring`, y el
/// playhead de `Playhead`, ambos en `Engine` y cubiertos por tests. Aquí solo se
/// convierte fracción de vuelta en ángulo y se dibuja.
struct RingView: View {

    let ring: Ring
    let playhead: Playhead?

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ringRadius = radius * 0.82
            let stepRadius = radius * 0.075
            let pulseRadius = radius * 0.13

            for position in ring.positions {
                let point = point(at: position.turn, center: center, radius: ringRadius)
                let size = position.isPulse ? pulseRadius : stepRadius
                let box = CGRect(
                    x: point.x - size, y: point.y - size, width: size * 2, height: size * 2
                )
                context.fill(
                    Path(ellipseIn: box),
                    with: .color(position.isPulse ? Palette.shape : Palette.border)
                )
            }

            if let playhead {
                drawPlayhead(
                    playhead, in: &context, center: center, radius: ringRadius, size: radius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// El playhead es una aguja desde el centro, no otra marca sobre el anillo.
    ///
    /// Una marca más entre las marcas obligaría a distinguirla por color, y a un
    /// metro eso no se lee. La aguja se ve por forma, que es lo que sobrevive a
    /// la distancia.
    private func drawPlayhead(
        _ playhead: Playhead,
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        size: CGFloat
    ) {
        var needle = Path()
        needle.move(to: center)
        needle.addLine(to: point(at: playhead.turn, center: center, radius: radius))
        context.stroke(needle, with: .color(.white.opacity(0.75)), lineWidth: size * 0.02)

        let hub = size * 0.035
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2
                )),
            with: .color(.white.opacity(0.75))
        )
    }

    /// Convierte fracción de vuelta en un punto de la circunferencia.
    ///
    /// **El Step 0 arriba y el giro en sentido horario.** Es la convención del
    /// reloj, que es la metáfora que la forma circular pide prestada: si el
    /// tiempo girase al revés, la representación contradiría lo que significa.
    private func point(at turn: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = turn * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}
