import Engine

/// Qué se está aprendiendo: el destino que espera a que alguien mueva un
/// control.
///
/// **Se aprende destino a destino** (`midi-learn_20260908`, FR6): se elige uno,
/// se mueve el control físico, y ese control queda asignado. No hay recorrido
/// guiado de los cuarenta y ocho — aprender uno es el gesto, y repetirlo es el
/// recorrido.
///
/// **Los cuatro casos no son cuatro familias, y conviene ver por qué.** Un
/// parámetro se asigna uno a uno porque cada knob mueve una cosa distinta; los
/// otros tres son **bloques**, porque el hardware los presenta en fila y los
/// dieciséis van seguidos desde el primero. Aprender «el primer pad» mueve los
/// dieciséis, que es lo que uno quiere al cambiar de controlador y lo que el
/// preset ya declaraba.
public enum LearnTarget: Equatable, Sendable {

    /// Un parámetro del Cycle, que se mueve con un knob y espera un CC.
    case parameter(TrackParameter)

    /// El primer knob de la fila. Con él se mueve la familia entera y, con
    /// ella, **el knob del Cycle en edición**: no está en la tabla de
    /// parámetros, sale del bloque más un desplazamiento.
    case knobBlock

    /// El primer pad. Espera una nota, no un CC.
    case padBlock

    /// El primer step button. Espera un CC de conmutación.
    case stepButtonBlock

    /// Si este destino se aprende con una nota en vez de con un CC.
    ///
    /// **El número no significa lo mismo en las dos familias**, así que un pad
    /// no puede aprender un knob ni al revés. Un mensaje de la familia
    /// equivocada no asigna y deja el aprendizaje abierto, esperando al control
    /// correcto: tratarlo como un fallo obligaría a volver a elegir el destino
    /// por haber rozado un pad.
    var expectsNote: Bool { self == .padBlock }
}
