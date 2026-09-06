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

extension Int {

    /// El número con cero delante cuando tiene una sola cifra: `01`, `12`.
    ///
    /// **Es una convención de dibujo, no de dominio**, y por eso vive aquí y no
    /// en `Engine`. El Track 1 es el Track 1; lo que el handoff decide es cómo se
    /// escribe, y lo decide para que doce etiquetas monoespaciadas ocupen lo
    /// mismo y la fila no dé un salto de medio carácter entre el 9 y el 10.
    ///
    /// Existía dos veces —una en la franja de Tracks y otra en el card de
    /// Cycle— hasta que la auditoría de la Fase 2 las juntó. Dos rellenos con la
    /// misma regla es una regla que puede divergir.
    ///
    /// A partir de tres cifras no rellena: no hay nada en el modelo que llegue
    /// ahí —doce Tracks, dieciséis Cycles, dieciséis Banks— y un `0` de más
    /// mentiría sobre el rango.
    var paddedForDisplay: String { self < 10 && self >= 0 ? "0\(self)" : "\(self)" }
}
