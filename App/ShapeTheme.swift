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
/// **El lenguaje visual se cierra aquí, el 2026-09-01.** Hasta hoy este tipo
/// decía de sí mismo que sus colores eran ilustrativos y que estaban en un solo
/// sitio «para poder cambiarlos cuando el lenguaje visual se cierre». Se cierra
/// con la rebanada 2 de la v2: los valores son los de la sección *Design Tokens*
/// de `design_handoff/README.md`, cuyo apartado *Fidelity* los declara
/// definitivos —«Colors … and font (Figtree) are final»— aunque el título de la
/// tabla siga arrastrando el «illustrative» de una versión anterior.
///
/// Que estén en un solo sitio deja de ser provisional y pasa a ser la regla: una
/// vista que invente su propio color es un fallo, igual que una que invente su
/// propio borde (FR9).
enum Palette {

    /// Fondo de la pantalla.
    static let background = Color(red: 0x21 / 255, green: 0x18 / 255, blue: 0x23 / 255)

    /// Fondo de la barra superior.
    ///
    /// **Y el color del texto sobre un relleno de acento**, que es su segundo
    /// papel en el handoff: los estados activos son un bloque de acento plano y
    /// saturado con texto oscuro encima. Es el mismo valor porque es el mismo
    /// gesto —lo oscuro de la app—, no por coincidencia.
    static let toolbar = Color(red: 0x1a / 255, green: 0x14 / 255, blue: 0x20 / 255)

    /// Fondo de los paneles hundidos, como el que sostiene el anillo.
    static let inset = Color(red: 0x0e / 255, green: 0x0a / 255, blue: 0x10 / 255)

    /// Separadores y bordes en reposo.
    static let border = Color(red: 0x3a / 255, green: 0x2c / 255, blue: 0x3d / 255)

    /// El borde de lo que pide ser mirado sin llegar a estar activo.
    ///
    /// El handoff da dos valores de borde y usa el claro donde el trazo tiene
    /// que leerse contra un panel hundido. Lo activo no usa ninguno de los dos:
    /// lleva el acento de su familia.
    static let borderBright = Color(red: 0x4a / 255, green: 0x3d / 255, blue: 0x4d / 255)

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

    /// Texto secundario que todavía tiene que leerse a un metro.
    ///
    /// El escalón entre éste y `muted` es lo que separa «acompaña a un valor» de
    /// «es el valor», sin gastar un acento en algo que no codifica familia.
    static let mutedBright = Color(red: 0xa9 / 255, green: 0x9c / 255, blue: 0xab / 255)

    /// Acento de la familia **Shape**.
    static let shape = Color(red: 0x9a / 255, green: 0xab / 255, blue: 0x79 / 255)

    /// Acento de la familia **Tonal**.
    static let tonal = Color(red: 0x7c / 255, green: 0x5f / 255, blue: 0xd9 / 255)

    /// Acento de la familia **Groove**.
    ///
    /// **Era ámbar `#D99A4E` hasta el 2026-09-01** y pasa al mauve del handoff
    /// (FR11). El ámbar se eligió cuando no había lenguaje visual cerrado, y con
    /// una razón escrita que no se borra al cambiarlo: se separaba del verde de
    /// Shape y del violeta de Tonal **por tono y no solo por luminosidad**, para
    /// que las tres se distinguieran de reojo y con poca luz, que es el criterio
    /// de uso de `product-guidelines.md`.
    ///
    /// **Mauve renuncia a esa separación**: queda del mismo lado del círculo que
    /// el violeta de Tonal, y la diferencia entre `#AA6DA8` y `#7C5FD9` es más
    /// de saturación que de tono. El handoff lo decidió así y esta rebanada lo
    /// adopta, pero **la razón del ámbar sigue siendo la pregunta abierta**: se
    /// vuelve a comprobar a un metro en la Fase 6, en dispositivo y con poca
    /// luz. Si los dos se confunden, se registra y se decide con la app en la
    /// mano — no se revierte por precaución ni se deja pasar por deferencia al
    /// handoff.
    static let groove = Color(red: 0xaa / 255, green: 0x6d / 255, blue: 0xa8 / 255)

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
