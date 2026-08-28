import SwiftUI

/// Los colores de la interfaz, en un solo sitio.
///
/// **El color codifica qué tipo de parámetro es; nunca decora.**
/// `product-guidelines.md` asigna un acento por familia funcional —Shape, Groove
/// y Tonal— consistente en toda la app. Hoy solo existe Shape, así que solo hay
/// un acento poblado; los otros dos entran con sus parámetros y no antes, para
/// que nadie los use como color suelto mientras tanto.
///
/// **Fondo oscuro y alto contraste son requisito de uso, no estética:** la
/// pantalla se lee de reojo, en movimiento y a veces con poca luz.
///
/// Los valores salen del handoff de diseño, que se declara a sí mismo *lofi*:
/// estructura e interacción son vinculantes, el color es ilustrativo. Están aquí
/// para poder cambiarlos en un sitio cuando el lenguaje visual se cierre.
enum Palette {

    /// Fondo de la pantalla.
    static let background = Color(red: 0x21 / 255, green: 0x18 / 255, blue: 0x23 / 255)

    /// Fondo de los paneles hundidos, como el que sostiene el anillo.
    static let inset = Color(red: 0x0e / 255, green: 0x0a / 255, blue: 0x10 / 255)

    /// Separadores y bordes.
    static let border = Color(red: 0x3a / 255, green: 0x2c / 255, blue: 0x3d / 255)

    /// Posiciones del anillo que **no** llevan Pulse.
    ///
    /// **No es el color de los bordes, aunque lo parezca.** Se probó con él y
    /// las posiciones vacías desaparecían contra el panel: a un metro el anillo
    /// se leía como cinco puntos sueltos en vez de como dieciséis posiciones de
    /// las que cinco disparan. Que el reparto euclidiano se vea exige ver
    /// también los huecos.
    static let step = Color(red: 0x6b / 255, green: 0x5a / 255, blue: 0x6e / 255)

    /// Texto secundario: etiquetas y estado en reposo.
    static let muted = Color(red: 0x8a / 255, green: 0x7d / 255, blue: 0x8d / 255)

    /// Acento de la familia **Shape**.
    static let shape = Color(red: 0x9a / 255, green: 0xab / 255, blue: 0x79 / 255)
}
