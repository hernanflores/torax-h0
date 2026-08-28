/// Los parámetros de Shape que se pueden ajustar.
///
/// **Vive en `Engine` y no en la capa de entrada** porque nombra conceptos del
/// dominio, no del transporte: *qué* se puede ajustar es una propiedad del
/// motor; *por dónde* llega la orden —un knob, un mensaje MIDI, un test— es
/// otra cosa, y cambiará más veces que esta lista.
///
/// Cuando lleguen Tonal y Groove añadirán los suyos: Velocity, Sustain, Timing,
/// Delay, Probability, Pitch.
public enum ShapeParameter: Equatable, Sendable, CaseIterable {
    case steps
    case pulses
    case rotate
    case division
}

extension ShapeParameter: CustomStringConvertible {

    /// Los términos de la Pre Spec, en inglés y sin traducir, como exige
    /// `product-guidelines.md`.
    public var description: String {
        switch self {
        case .steps: "Steps"
        case .pulses: "Pulses"
        case .rotate: "Rotate"
        case .division: "Division"
        }
    }
}
