import SwiftUI

/// El único sitio donde el texto de la interfaz se pasa a minúsculas.
///
/// **Cambia la caja, no el término** (enmienda del 2026-09-06 en
/// `product-guidelines.md`). El vocabulario de la Pre Spec sigue capitalizado en
/// código, tests y documentación: `Steps` es `Steps` en `Engine` y se dibuja
/// `steps`. La regla de «un solo término por concepto en UI, código y
/// documentación» sigue intacta porque el término no cambia — cambia cómo se
/// pinta.
///
/// **Por qué existe una función y no `.lowercased()` esparcido.** Dos razones,
/// y la segunda es la que importa:
///
/// 1. Buena parte de las cadenas visibles **no las escribe esta capa**. Los
///    nombres de dispositivo llegan de CoreMIDI (`Beatstep Pro`) y los estados
///    vacíos del paquete `MIDI` (`No MIDI device`), que es código sin vistas y
///    donde bajar la minúscula sería traducir el modelo para complacer al
///    dibujo.
/// 2. Una llamada con nombre **se puede buscar**. La auditoría de la Fase 6
///    tiene que poder comprobar que ninguna cadena visible se escapó, y
///    `grep lowercasedForDisplay` responde eso; `grep lowercased` no distingue
///    una decisión de interfaz de un `lowercased()` de comparación.
///
/// > **No usa el locale.** `lowercased()` sin argumento aplica las reglas de
/// > Unicode, no las del idioma del iPad, que es lo que se quiere: la interfaz
/// > va en inglés y sin traducir (`product-guidelines.md`), y una
/// > `lowercased(with: .current)` haría que la misma cadena se dibujara distinta
/// > en un iPad turco — la `I` sin punto — por un idioma que la app no habla.
extension String {

    /// La cadena tal y como se dibuja: en minúsculas.
    var lowercasedForDisplay: String { lowercased() }
}

extension Text {

    /// Un texto de interfaz, ya en minúsculas.
    ///
    /// Escribir `Text(display: model.sourceStatus)` en vez de
    /// `Text(model.sourceStatus.lowercasedForDisplay)` deja el sitio de llamada
    /// diciendo qué es —texto de interfaz— y no qué se le hace.
    init(display string: String) {
        self.init(string.lowercasedForDisplay)
    }
}
