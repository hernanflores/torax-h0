import SwiftUI

/// El lenguaje neo-brutalista del handoff, como sistema.
///
/// **Es un sistema, no un estilo por vista** (FR9). `Palette` decide el color y
/// `Typography` la fuente; esto decide el trazo, el radio, la sombra y qué
/// aspecto tiene «no disponible». Las tres reglas son la misma: *una vista que
/// invente su propio botón es un fallo de la rebanada*, porque el día que el
/// radio cambie habrá que buscarlo por todo `App` en vez de aquí.
///
/// Los valores salen de *Component Styling* en `design_handoff/README.md`:
///
/// - trazos sólidos de **2px** en todo lo interactivo, **3px** en la raíz
///   elegida — nunca un borde tenue;
/// - radios de **3 a 8px**, nunca pastilla completa y nunca 0;
/// - rellenos de acento **planos y saturados**, sin degradados ni tintes;
/// - sombras duras `2px 2px 0` **sin blur** en lo seleccionado, `6px 6px 0` en
///   un modal;
/// - **borde discontinuo** de 2px para lo no disponible;
/// - **peso 700** en lo activo.
///
/// > **Por qué nunca pastilla completa.** El handoff lo dice y conviene saber
/// > qué se gana: una pastilla lee como un control blando de sistema, y el
/// > radio pequeño y constante es lo que hace que la pantalla se lea como un
/// > aparato. El botón de transporte era una pastilla —`.borderedProminent`— y
/// > es el primer sitio donde se nota el cambio.
enum Brutalist {

    // MARK: - Trazo

    /// El grosor de todo lo interactivo.
    static let stroke: CGFloat = 2

    /// El grosor de lo que tiene que destacar entre iguales, como la raíz
    /// elegida entre las notas de la escala.
    static let strokeEmphasis: CGFloat = 3

    // MARK: - Radio

    /// Lo pequeño: pastillas de canal, celdas.
    static let radiusSmall: CGFloat = 4

    /// Lo corriente: botones y pastillas.
    static let radius: CGFloat = 6

    /// Lo grande: paneles y tarjetas. **El techo de la escala.**
    static let radiusLarge: CGFloat = 8

    // MARK: - Sombra

    /// El desplazamiento de la sombra dura.
    static let shadowOffset: CGFloat = 2

    /// El de un modal, que tiene que despegarse del fondo.
    static let shadowOffsetModal: CGFloat = 6

    /// El color de la sombra. **Sin blur**: es un bloque desplazado, no una
    /// difuminación, y ahí está la diferencia con una sombra de sistema.
    static let shadow = Color.black.opacity(0.4)
}

// MARK: - Modificadores

extension View {

    /// Una sombra dura, sin blur.
    ///
    /// `shadow(radius:)` de SwiftUI difumina siempre, así que la sombra se
    /// dibuja como una copia desplazada de la propia forma. Es la única manera
    /// de conseguir el bloque que el handoff pide.
    @ViewBuilder
    func brutalistShadow(_ shape: RoundedRectangle, when applies: Bool = true, modal: Bool = false)
        -> some View
    {
        if applies {
            let offset = modal ? Brutalist.shadowOffsetModal : Brutalist.shadowOffset
            background(
                shape
                    .fill(Brutalist.shadow)
                    .offset(x: offset, y: offset)
            )
        } else {
            self
        }
    }

    /// Un control: relleno, trazo de 2px y, si está elegido, sombra dura.
    ///
    /// **El estado elegido es un bloque de acento plano**, no un tinte ni un
    /// contorno solo. Lo que no está elegido lleva el fondo hundido y su trazo,
    /// que puede ser el acento —para decir «tiene material»— o el borde en
    /// reposo.
    ///
    /// - Parameters:
    ///   - accent: el color de la familia a la que pertenece el control.
    ///   - isSelected: si es el elegido.
    ///   - isPopulated: si tiene algo dentro, para los que no están elegidos.
    ///   - radius: el radio, dentro de la escala.
    func brutalistControl(
        accent: Color,
        isSelected: Bool,
        isPopulated: Bool = false,
        radius: CGFloat = Brutalist.radius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return
            self
            .background(isSelected ? accent : Palette.inset, in: shape)
            .overlay(
                shape.stroke(
                    isSelected ? accent : (isPopulated ? accent : Palette.border),
                    lineWidth: Brutalist.stroke
                )
            )
            // **Solo lo elegido lleva sombra.** El handoff la reserva para lo
            // seleccionado y lo primario; dársela a todo la convertiría en
            // textura de fondo y dejaría de señalar nada.
            .brutalistShadow(shape, when: isSelected)
    }

    /// Un panel hundido: el que sostiene los anillos, o una sección.
    func brutalistPanel(radius: CGFloat = Brutalist.radiusLarge) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return
            self
            .background(Palette.inset, in: shape)
            .overlay(shape.stroke(Palette.border, lineWidth: Brutalist.stroke))
    }

    /// Lo que existe pero todavía no se puede usar.
    ///
    /// **El borde discontinuo es el signo, y es el único.** El handoff lo usa
    /// para la fila de Bank vacía, para la escala `+User` y para los controles
    /// fuera de alcance; esta rebanada lo necesita para las tres pestañas que no
    /// existen (FR8). Enseñar la forma completa de la app y marcar qué falta es
    /// más honesto que fingir que la app tiene dos pantallas.
    func brutalistUnavailable(radius: CGFloat = Brutalist.radius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return
            self
            .foregroundStyle(Palette.muted)
            .overlay(
                shape.strokeBorder(
                    Palette.borderBright,
                    style: StrokeStyle(lineWidth: Brutalist.stroke, dash: [6, 4])
                )
            )
            .allowsHitTesting(false)
    }
}
