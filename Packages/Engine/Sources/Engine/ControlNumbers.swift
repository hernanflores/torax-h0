/// El mapeo del controlador, expresado en números.
///
/// **Es el mapeo, pero sin los tipos de CoreMIDI.** Qué knob mueve qué
/// parámetro es cosa de `MIDI`, que sí puede ver `MIDIController` y `MIDINote`;
/// aquí solo llegan los números, que es lo único que hay que guardar en disco.
/// Es el mismo criterio con el que `Project` guarda `destinationName` y no un
/// `MIDIEndpointRef`: **este paquete no puede ver CoreMIDI**, y la frontera está
/// vigilada por `DependencyBoundaryTests`.
///
/// **No es un sinónimo de «mapeo»**, es el mapeo escrito en la única forma que
/// este paquete puede sostener. `MIDI` lo convierte en las dos direcciones.
///
/// **Ausente significa el preset de fábrica** (`midi-learn_20260908`, FR17). Un
/// `Project` sin números es un usuario que nunca aprendió nada, que es un estado
/// válido y no un campo que falte — el mismo criterio que `destinationName`.
public struct ControlNumbers: Equatable, Sendable {

    /// Qué número de controlador mueve cada parámetro.
    ///
    /// **Lo que no está, no está**: un parámetro sin entrada no tiene control, y
    /// eso es un estado válido. Es lo mismo que dice `ControlMapping` de los
    /// controles sin asignar.
    public let assignments: [TrackParameter: Int]

    /// Nota del primer pad; los dieciséis van seguidos desde ella.
    public let padBlock: Int

    /// Número del primer knob; los dieciséis van seguidos desde él.
    public let knobBlock: Int

    /// Número del primer step button; los dieciséis van seguidos desde él.
    public let stepButtonBlock: Int

    public init(
        assignments: [TrackParameter: Int],
        padBlock: Int,
        knobBlock: Int,
        stepButtonBlock: Int
    ) {
        self.assignments = assignments
        self.padBlock = padBlock
        self.knobBlock = knobBlock
        self.stepButtonBlock = stepButtonBlock
    }
}
