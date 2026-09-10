/// La regla del acorde de dos dedos sobre la rejilla de Patterns.
///
/// **Mantener el origen y tocar el destino copia en el acto.** Es el equivalente
/// por Pattern de lo que `reload` hace por Banco: dejar una copia del que suena
/// antes de experimentar encima, sin parar y sin mirar la pantalla.
///
/// **Se consume en el `down` del segundo dedo, no al levantar.** Da respuesta
/// inmediata y deja el orden de levantada sin importancia (FR17), que es la
/// condición que un gesto de directo tiene que cumplir: nadie puede pedirle a
/// quien toca que levante los dedos en un orden concreto.
///
/// **Es una regla y no una vista** (NFR1). La pantalla traduce toques a eventos
/// y no decide nada; decidir es lo que se puede probar, y `App` no se mide. Es
/// el mismo movimiento que hizo `PatternSlotState` el 2026-09-07. Por eso aquí
/// no hay ni `UIKit` ni `SwiftUI`, ni índices que este tipo valide: el rango de
/// los huecos lo acota el `Bank`, que es de quien son.
///
/// **Quien lo usa decide cuándo escucharla.** El acorde solo actúa con el
/// transporte corriendo (FR15); parado, el toque sencillo carga el Pattern de
/// inmediato y el `down` del primer dedo ya habría cambiado el material antes de
/// saber si era un acorde.
public struct PatternChord: Equatable, Sendable {

    /// Lo que un toque produce.
    public enum Effect: Equatable, Sendable {

        /// Nada que hacer todavía, o nunca.
        case none

        /// Seleccionar ese hueco: el toque sencillo de siempre (FR20).
        case select(Int)

        /// Copiar el Pattern de `from` en `to`, ya.
        case copy(from: Int, to: Int)
    }

    /// Los dedos que están abajo, en el orden en que bajaron.
    ///
    /// Se guarda la lista y no una cuenta porque el primero es el origen de la
    /// copia. Dos dedos en la misma celda son dos entradas iguales: son dos
    /// toques, aunque no formen acorde.
    private var pressed: [Int] = []

    /// El gesto ya dio lo que tenía que dar y no dará nada más hasta que se
    /// levanten todos los dedos.
    ///
    /// **Cubre las dos formas de agotarse**: haber copiado —el acorde queda
    /// consumido y ningún `up` posterior selecciona— y haberse cancelado, que no
    /// selecciona por FR21. Las dos dicen lo mismo, así que son una.
    private var spent = false

    /// Una regla sin ningún dedo abajo.
    public init() {}

    /// Un dedo baja sobre ese hueco.
    ///
    /// El primero no hace nada: aún no se sabe si es un toque o la primera mitad
    /// de un acorde. El segundo, sobre un hueco distinto, copia. Del tercero en
    /// adelante se ignoran, y también el segundo sobre el mismo hueco, que
    /// copiaría una celda sobre sí misma.
    public mutating func pressing(_ index: Int) -> Effect {
        defer { pressed.append(index) }

        guard !spent, let origin = pressed.first, pressed.count == 1, origin != index else {
            return .none
        }

        spent = true
        return .copy(from: origin, to: index)
    }

    /// Un dedo se levanta de ese hueco.
    ///
    /// Selecciona **solo si el gesto fue un toque sencillo**: sin acorde, sin
    /// cancelación y con ese dedo siendo el último que quedaba abajo.
    public mutating func releasing(_ index: Int) -> Effect {
        guard let lone = lifting(index) else { return .none }

        let wasSpent = spent
        reset()
        return wasSpent ? .none : .select(lone)
    }

    /// Un toque se cancela: empezó en una celda y se levantó fuera de ella.
    ///
    /// **No selecciona nunca** (FR21), y deja el gesto agotado para que tampoco
    /// seleccione lo que quede abajo.
    public mutating func cancelling(_ index: Int) -> Effect {
        guard pressed.contains(index) else { return .none }

        if lifting(index) != nil {
            reset()
        } else {
            spent = true
        }
        return .none
    }

    /// Quita ese dedo y devuelve el hueco si era el único que quedaba abajo.
    ///
    /// `nil` significa que aún quedan dedos, o que ese hueco no estaba pulsado —
    /// un `up` sin su `down`, que no es un error y no hace nada.
    private mutating func lifting(_ index: Int) -> Int? {
        guard let position = pressed.lastIndex(of: index) else { return nil }

        pressed.remove(at: position)
        return pressed.isEmpty ? index : nil
    }

    /// Sin dedos abajo, el gesto siguiente empieza limpio.
    private mutating func reset() {
        pressed = []
        spent = false
    }
}
