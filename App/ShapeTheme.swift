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

    // MARK: - La escala neutra
    //
    // **Todo lo que no es acento sale de una sola rampa neutra**, con el mismo
    // matiz verdoso mínimo del fondo del handoff (`#111211`: el verde un punto
    // por encima del rojo y el azul). Antes eran violetas, derivados de un fondo
    // `#211823` que ya no existe; ver la enmienda del 2026-09-06 en
    // `product-guidelines.md`.
    //
    // Los escalones se eligieron **conservando el contraste que cada token tenía
    // contra su fondo anterior**, no copiando su claridad: el fondo bajó, así que
    // copiar los grises habría cambiado en silencio la separación entre bordes,
    // huecos y texto, que es lo único que estos tokens codifican.

    /// Fondo de la pantalla. **El valor del handoff.**
    static let background = Color(red: 0x11 / 255, green: 0x12 / 255, blue: 0x11 / 255)

    /// El interior de un panel o de un card.
    ///
    /// **Apenas se separa del fondo, y es a propósito.** En el handoff un card no
    /// es una superficie hundida: es el mismo suelo con un trazo de 2 pt
    /// alrededor. Medido en los cuatro PNG, el interior de un card y el fondo se
    /// llevan uno o dos valores — **la separación la hace el borde**, no el
    /// relleno. Un hundido de verdad, como el que había, competiría con el trazo
    /// para decir lo mismo.
    static let inset = Color(red: 0x0d / 255, green: 0x0e / 255, blue: 0x0d / 255)

    /// Una celda o una fila **dentro** de un card.
    ///
    /// El único escalón que sube: en el handoff las filas de dispositivo y las
    /// celdas de una rejilla se levantan del card que las contiene. Sin este
    /// token había que elegir entre dibujarlas del color del card —y perderlas— o
    /// inventar un gris en la vista, que es el fallo que FR1 prohíbe.
    static let surface = Color(red: 0x1a / 255, green: 0x1b / 255, blue: 0x1a / 255)

    /// Separadores y bordes en reposo.
    static let border = Color(red: 0x2a / 255, green: 0x2c / 255, blue: 0x2a / 255)

    /// El borde de lo que pide ser mirado sin llegar a estar activo.
    ///
    /// El handoff da dos valores de borde y usa el claro donde el trazo tiene
    /// que leerse contra un panel. Lo activo no usa ninguno de los dos: lleva el
    /// acento de su familia, o el off-white si no tiene familia.
    static let borderBright = Color(red: 0x3a / 255, green: 0x3d / 255, blue: 0x3a / 255)

    /// Posiciones del anillo que **no** llevan Pulse.
    ///
    /// **No es el color de los bordes, aunque lo parezca.** Se probó con él y las
    /// posiciones vacías desaparecían contra el panel: a un metro el anillo se
    /// leía como cinco puntos sueltos en vez de como dieciséis posiciones de las
    /// que cinco disparan. Que el reparto euclidiano se vea exige ver también los
    /// huecos.
    ///
    /// Sobre el fondo neutro contrasta **3,04 : 1** contra el 2,71 : 1 que tenía
    /// sobre el violeta. El hueco se ve algo mejor que antes, no peor.
    static let step = Color(red: 0x5f / 255, green: 0x62 / 255, blue: 0x5f / 255)

    /// El hueco del anillo cuando la banda no es la elegida.
    ///
    /// **Es un token y no `step.opacity(0.55)` escrito en la vista.** El valor es
    /// el mismo; lo que cambia es que derivar un color dentro de un `Canvas` es
    /// exactamente el fallo que FR1 nombra — el día que el hueco haya que
    /// ajustarlo, se ajusta aquí y no buscando una llamada a `opacity` entre el
    /// código de dibujo. Encontrado en la auditoría de la Fase 6.
    static let stepDim = Color(red: 0x3d / 255, green: 0x3f / 255, blue: 0x3d / 255)

    /// Texto secundario: etiquetas y estado en reposo.
    static let muted = Color(red: 0x8a / 255, green: 0x8d / 255, blue: 0x8a / 255)

    /// Texto secundario que todavía tiene que leerse a un metro.
    ///
    /// El escalón entre éste y `muted` es lo que separa «acompaña a un valor» de
    /// «es el valor», sin gastar un acento en algo que no codifica familia.
    static let mutedBright = Color(red: 0xa9 / 255, green: 0xac / 255, blue: 0xa9 / 255)

    // MARK: - El off-white

    /// El texto corriente de la interfaz.
    ///
    /// **No es blanco puro, y esa era una fuga.** `.white` aparecía suelto en tres
    /// vistas —el playhead, la raíz elegida y el color de primer plano de la
    /// pantalla entera— que es exactamente el fallo que FR1 nombra: un color
    /// inventado fuera del sistema. El handoff no usa blanco en ningún sitio.
    static let text = Color(red: 0xe4 / 255, green: 0xe2 / 255, blue: 0xdc / 255)

    /// El relleno de lo seleccionado que **no pertenece a ninguna familia**.
    ///
    /// El Cycle en curso, el Track elegido, el Bank elegido, la raíz elegida, el
    /// subrayado del módulo activo y el playhead. Todos son la misma decisión —
    /// «éste, entre iguales»— y por eso son un solo token y no seis grises.
    ///
    /// Medido en los PNG del handoff: `#f2ede3`, cálido. No es el mismo blanco
    /// roto que `text`, que tira a neutro: uno es un bloque y el otro es tinta.
    static let offWhite = Color(red: 0xf2 / 255, green: 0xed / 255, blue: 0xe3 / 255)

    /// El color del texto **sobre un relleno de acento o de off-white**.
    ///
    /// **Se llamaba `toolbar`** cuando además era el fondo de la barra superior.
    /// En el handoff la barra es el mismo suelo que la página con un borde
    /// inferior, así que ese papel desapareció y el nombre pasó a mentir: nueve de
    /// sus diez usos eran ya éste. Es el fondo de la app porque es el mismo gesto
    /// —lo oscuro— no por coincidencia.
    static let onAccent = background

    // MARK: - Los acentos

    // **Los tres no cambian.** El fondo pasó a neutro el 2026-09-06 y ellos
    // siguen siendo los cerrados el 2026-09-02: el color codifica qué tipo de
    // parámetro es, y cambiar el suelo no cambia esa correspondencia.

    /// Acento de la familia **Shape**. Contrasta 7,6 : 1 contra el fondo.
    static let shape = Color(red: 0x9a / 255, green: 0xab / 255, blue: 0x79 / 255)

    /// Acento de la familia **Tonal**.
    ///
    /// Contrasta 4,0 : 1 contra el fondo neutro, frente a 3,7 : 1 contra el
    /// violeta anterior. Es el más bajo de los tres, y por eso se usa como
    /// **relleno con texto oscuro encima** —donde la ratio que importa es la otra—
    /// y no como tinta pequeña sobre el fondo.
    static let tonal = Color(red: 0x7c / 255, green: 0x5f / 255, blue: 0xd9 / 255)

    /// Acento de la familia **Groove**.
    ///
    /// **Era ámbar `#D99A4E` hasta el 2026-09-01** y pasó al mauve del handoff. El
    /// ámbar se eligió con una razón escrita que no se borra al cambiarlo: se
    /// separaba del verde de Shape y del violeta de Tonal **por tono y no solo por
    /// luminosidad**, para que las tres se distinguieran de reojo y con poca luz.
    ///
    /// **Mauve renuncia a esa separación**: queda del mismo lado del círculo que
    /// el violeta de Tonal, y la diferencia con `#7C5FD9` es más de saturación que
    /// de tono. Entre sí contrastan **1,21 : 1**.
    ///
    /// > **La pregunta se reabrió el 2026-09-06 y se cerró el mismo día.** Se
    /// > había comprobado a un metro que se separaban, **pero contra el fondo
    /// > violeta oscuro**, que arrimaba el ojo hacia el lado violeta del círculo;
    /// > contra el neutro `#111211` esa comprobación no valía.
    /// >
    /// > **Se volvió a mirar con la app delante**, con los cards de Groove y
    /// > Tonal visibles a la vez en la pantalla `track`, y el usuario confirmó
    /// > que el contraste es bueno. El mauve se queda.
    /// >
    /// > Lo que la reapertura enseñó sigue valiendo: **la separación de estos dos
    /// > depende del fondo**, no solo de ellos. Si el fondo vuelve a cambiar, la
    /// > comprobación hay que rehacerla; los 1,21 : 1 que contrastan entre sí no
    /// > dejan margen para darla por hecha.
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
