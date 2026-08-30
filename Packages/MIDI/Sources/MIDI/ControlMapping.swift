import Engine

/// Qué controlador mueve qué parámetro del Track.
///
/// **Es fija y provisional.** La sustituyen el preset del BeatStep Pro y MIDI
/// Learn, que son el track siguiente. Hasta entonces los números están aquí, en
/// un solo sitio y declarados como lo que son, en vez de repartidos por el
/// código de recepción.
public struct ControlMapping: Equatable, Sendable {

    /// Mapeo por defecto mientras no exista MIDI Learn.
    ///
    /// Los números salen del rango de controladores de propósito general
    /// (70–79), que es donde la especificación MIDI espera parámetros de
    /// síntesis sin significado fijo — no pisan volumen, paneo ni pedal.
    /// Los cuatro de Shape y los tres de Groove, en el mismo bloque contiguo:
    /// el orden de los CC sigue al de `TrackParameter`, así que la fila de
    /// knobs se lee igual que la lista de parámetros.
    public static let provisional = ControlMapping(assignments: [
        .steps: 70,
        .pulses: 71,
        .rotate: 72,
        .division: 73,
        .velocity: 74,
        .sustain: 75,
        .probability: 76,
    ])

    private let assignments: [TrackParameter: Int]

    public init(assignments: [TrackParameter: Int]) {
        self.assignments = assignments
    }

    /// Finds the MIDI controller assigned to a track parameter.
    ///
    /// - Parameter parameter: The track parameter whose controller assignment to find.
    /// - Returns: The assigned MIDI controller, or `nil` if the parameter is unmapped or its assigned number is invalid.
    public func controller(for parameter: TrackParameter) -> MIDIController? {
        assignments[parameter].flatMap(MIDIController.init)
    }

    /// Parámetro que mueve un controlador.
    ///
    /// Devuelve `nil` para lo que no esté asignado. **No es un error:** en una
    /// sesión real llegan mensajes de todo tipo, y no es asunto del mapeo
    /// Finds the track parameter assigned to a MIDI controller.
    /// - Parameter controller: The MIDI controller to look up.
    /// - Returns: The assigned track parameter, or `nil` if the controller is unassigned.
    public func parameter(for controller: MIDIController) -> TrackParameter? {
        assignments.first { $0.value == controller.number }?.key
    }
}
