import SwiftUI
import UIKit

/// La tipografía de la interfaz, en un solo sitio.
///
/// **Figtree, la del handoff** (FR10), en los tres pesos que su README nombra:
/// 400 para el texto corriente, 600 para lo que acompaña a un valor y 700 para
/// lo activo. No hay más pesos en el bundle a propósito: cada uno son 57 KB, y
/// un peso que nadie pide es peso muerto que además invita a usarlo.
///
/// **Ninguna vista pide una fuente por su cuenta.** Es la misma regla que
/// `Palette` para el color y que `Brutalist` para el trazo: una vista que llame
/// a `Font.custom` directamente es un fallo de la rebanada, porque el día que la
/// familia cambie habrá que buscarla por todo `App` en vez de en este fichero.
///
/// > **Por qué por nombre PostScript y no por familia y peso.** `Figtree-Bold`
/// > declara familia `Figtree` y subfamilia `Bold`, así que
/// > `Font.custom("Figtree", size:).weight(.bold)` funcionaría para él. Pero
/// > **`Figtree-SemiBold` declara familia `Figtree SemiBold`**, que es una
/// > familia distinta a ojos de Core Text: pedirle a `Figtree` el peso
/// > `.semibold` no lo encontraría y iOS sintetizaría un falso semibold —o
/// > devolvería el regular— **sin avisar**. Nombrar el PostScript de cada cara
/// > es lo único que no depende de cómo el diseñador agrupó las familias.
enum Typography {

    /// Lo activo y las lecturas grandes: peso 700.
    static func bold(_ size: CGFloat) -> Font {
        .custom("Figtree-Bold", size: size)
    }

    /// Lo que acompaña a un valor sin ser el valor: peso 600.
    static func semibold(_ size: CGFloat) -> Font {
        .custom("Figtree-SemiBold", size: size)
    }

    /// El texto corriente: peso 400.
    static func regular(_ size: CGFloat) -> Font {
        .custom("Figtree-Regular", size: size)
    }
}

extension Typography {

    /// Si las tres caras están registradas y se pueden pedir por su nombre.
    ///
    /// **Existe porque el fallo es silencioso.** Cuando una fuente no está en el
    /// bundle o falta en `UIAppFonts`, iOS no avisa: cae a la del sistema y la
    /// pantalla se ve *casi* bien, que es la peor forma de estar rota. La app la
    /// consulta al arrancar y lo dice por consola.
    ///
    /// No es un test —`App` no se mide (`workflow.md`)— sino una comprobación de
    /// arranque. Lo que la sustituye de verdad es la captura del simulador que
    /// la tarea exige: ver la fuente, no suponerla.
    static var isAvailable: Bool {
        ["Figtree-Regular", "Figtree-SemiBold", "Figtree-Bold"]
            .allSatisfy { UIFont(name: $0, size: 12) != nil }
    }
}

extension Typography {

    // MARK: - La escala

    // **Los tamaños viven aquí y no en las vistas.** Una vista que escriba un
    // número de puntos es lo mismo que una que escriba un color: funciona hasta
    // que hay que cambiarlo en catorce sitios. Los nombres dicen qué papel
    // cumple el texto, no qué tamaño tiene, para que ajustar la escala no
    // obligue a releer cada vista y decidir de nuevo.
    //
    // Los valores de partida son los de las fuentes semánticas de iOS que estas
    // vistas ya usaban —34, 28, 22, 20, 17, 16, 13—, así que este barrido no
    // cambia lo que se ve: cambia de qué familia sale. El 46 del handoff para la
    // lectura grande llega con el panel lateral, en la Fase 3.

    /// La lectura grande del panel: el valor en reposo y el transitorio.
    ///
    /// **Eran 64 puntos y se bajan a 44 el 2026-09-01.** Los 64 se eligieron
    /// cuando el panel de lectura era la columna ancha; al invertir el reparto
    /// (FR14) el panel pasó a ser el estrecho y el tamaño dejó de caber:
    /// `Probability 100` se cortaba en `Probabilit…` en el iPad. 44 es además lo
    /// que el handoff usa —46px— para esta lectura.
    ///
    /// Sigue siendo el texto más grande de la pantalla, que es lo que la
    /// legibilidad a un metro pide de él.
    static var readout: Font { bold(44) }

    /// La misma lectura cuando comparte columna con los cards.
    ///
    /// **38 y no 44 desde el 2026-09-06.** Con los tres cards de familia y el de
    /// Cycle apilados debajo, los 44 dejaban la franja de Tracks fuera de la
    /// pantalla: se vio en captura, con la fila M/S cortada por el borde. Sigue
    /// siendo con diferencia el texto más grande de la pantalla, que es lo que la
    /// legibilidad a un metro le pide.
    static var readoutCompact: Font { bold(38) }

    /// El botón de transporte, que es el control más grande de la pantalla.
    ///
    /// **Se llamaba `appTitle`** y lo usaba el nombre de la app, que se quitó de
    /// la interfaz el 2026-09-01: el handoff no lo dibuja en ninguna de sus cinco
    /// pantallas. El tamaño se queda porque el transporte se toca de pie y de
    /// lejos; el nombre cambia para que no describa algo que ya no existe.
    static var transportLabel: Font { semibold(34) }

    /// Cabecera de sección: Tracks, Tonal, Channel.
    static var sectionTitle: Font { semibold(22) }

    // MARK: - El chrome compartido

    // **Tres papeles que antes no existían.** La barra y la navegación se
    // dibujaban con `captionStrong` y `captionBold`, que son etiquetas de 13
    // puntos: valían cuando las pestañas eran `1 · Track` en una fila que además
    // llevaba el estado y el transporte. El handoff les da una fila propia y un
    // tamaño de lectura, así que piden un nombre propio en vez de reusar el de
    // otra cosa.

    /// El módulo activo, centrado en la barra superior.
    static var moduleTitle: Font { semibold(22) }

    /// Una entrada de la navegación persistente.
    static var navigationItem: Font { regular(20) }

    /// La entrada activa, la que lleva el subrayado de 3 pt.
    static var navigationItemActive: Font { bold(20) }

    // MARK: - Los símbolos

    // **Los iconos no son Figtree, y aun así sus tamaños viven aquí.** Un SF
    // Symbol se dimensiona con la fuente del sistema —pedirle Figtree devolvería
    // la del sistema igualmente— pero el número de puntos es una decisión de
    // escala como cualquier otra, y escribirlo en la vista es el mismo fallo que
    // escribir un color. La auditoría de la Fase 6 encontró tres.

    /// Un icono dentro de un control pequeño: los escalones del tempo.
    static let symbolSmall: CGFloat = 13

    /// Un icono que es el control: el transporte, el indicador de encadenamiento.
    static let symbol: CGFloat = 18

    /// Un renglón de parámetros, que es una lista de valores y no prosa.
    static var parameterLine: Font { regular(20) }

    /// El mismo renglón cuando es el que importa.
    static var parameterLineStrong: Font { semibold(20) }

    /// Un valor suelto que encabeza su grupo.
    static var valueTitle: Font { bold(20) }

    /// Texto corriente.
    static var body: Font { regular(17) }

    /// Texto corriente que pesa: el botón de transporte, la pastilla elegida.
    static var bodyStrong: Font { bold(17) }

    /// Texto corriente con énfasis medio.
    static var bodyMedium: Font { semibold(17) }

    /// Una lectura numérica dentro de un renglón de texto.
    static var reading: Font { regular(16) }

    /// Etiquetas y estado en reposo.
    static var caption: Font { regular(13) }

    /// Etiquetas que tienen que leerse: el canal de una pastilla, un titular.
    static var captionStrong: Font { semibold(13) }

    /// La misma etiqueta cuando su pastilla está elegida.
    static var captionBold: Font { bold(13) }
}
