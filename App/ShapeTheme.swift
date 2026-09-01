import Engine
import SwiftUI

/// Los colores de la interfaz, en un solo sitio.
///
/// **El color codifica qué tipo de parámetro es; nunca decora.**
/// `product-guidelines.md` asigna un acento por familia funcional —Shape, Groove
/// y Tonal— consistente en toda la app.
///
/// **Fondo oscuro y alto contraste son requisito de uso, no estética:** la
/// pantalla se lee de reojo, en movimiento y a veces con poca luz.
///
/// Las tres familias tienen ya su acento: Shape desde la rebanada 1, Tonal desde
/// la 4 y Groove desde la 5. Ninguno se pobló antes de que existieran sus
/// parámetros, para que no quedara un color suelto que alguien usara como
/// decoración — que es justo lo que la guía dice que el color no es.
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

    /// Acento de la familia **Tonal**.
    static let tonal = Color(red: 0x7c / 255, green: 0x5f / 255, blue: 0xd9 / 255)

    /// Acento de la familia **Groove**.
    ///
    /// Ámbar cálido: se separa del verde de Shape y del violeta de Tonal por
    /// tono, no solo por luminosidad, para que las tres sigan distinguiéndose de
    /// reojo y con poca luz — el criterio de uso de `product-guidelines.md`.
    static let groove = Color(red: 0xd9 / 255, green: 0x9a / 255, blue: 0x4e / 255)

    /// El acento que le toca a una familia de parámetros.
    ///
    /// **La correspondencia vive aquí y la clasificación en `Engine`.** Qué tipo
    /// de parámetro es lo dice el motor (`TrackParameter.family`); qué color le
    /// Selects the accent color for a parameter family.
    /// - Parameter family: The parameter family whose accent color is needed.
    /// - Returns: The corresponding accent color.
    static func accent(for family: ParameterFamily) -> Color {
        switch family {
        case .shape: shape
        case .groove: groove
        case .tonal: tonal
        }
    }
}
