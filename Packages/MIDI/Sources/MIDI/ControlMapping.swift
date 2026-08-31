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
    /// Los cuatro de Shape y los cinco de Groove, en el mismo bloque contiguo:
    /// el orden de los CC sigue al de `TrackParameter`, así que la fila de
    /// knobs se lee igual que la lista de parámetros.
    ///
    /// **Los nueve caben sin salir del rango.** Con Timing y Delay el bloque
    /// llega al 78 y el rango de propósito general termina en el 79: no hay que
    /// invadir controladores con significado asignado, que es lo que habría
    /// obligado a repartir los knobs por criterios ajenos al dominio.
    public static let provisional = ControlMapping(assignments: [
        .steps: 70,
        .pulses: 71,
        .rotate: 72,
        .division: 73,
        .velocity: 74,
        .sustain: 75,
        .probability: 76,
        .timing: 77,
        .delay: 78,
    ])

    /// Nota por defecto del primer pad.
    ///
    /// Los dieciséis van seguidos desde aquí. El número se verifica en
    /// dispositivo antes de darlo por cierto (fase 5 del track): lo que el
    /// código dé por sabido del controlador tiene que haberse visto llegar en el
    /// iPad, que es la lección de la nota del 2026-08-28 sobre los encoders en
    /// `Relative #2`.
    public static let defaultPadBlock = MIDINote(36)!

    private let assignments: [TrackParameter: Int]

    /// Nota del primer pad; los dieciséis son consecutivos desde ella.
    ///
    /// **Es un dato del mapeo y no una constante repartida por el código.** Si
    /// el dispositivo desmiente el número, cambiarlo aquí mueve los dieciséis
    /// pads a la vez, sin tocar nada de dominio: el índice que sale de aquí es
    /// el mismo, y la altura la sigue decidiendo la superficie.
    public let padBlock: MIDINote

    public init(assignments: [TrackParameter: Int], padBlock: MIDINote = defaultPadBlock) {
        self.assignments = assignments
        self.padBlock = padBlock
    }

    /// Índice 0–15 del pad que envió esa nota, o `nil` fuera del bloque.
    ///
    /// **El número no es la altura.** Lo único que dice es qué pad se pulsó;
    /// que el bloque empiece en la nota 36 y el pad 1 suene 48 no es una
    /// contradicción, son dos numeraciones distintas.
    ///
    /// Fuera del bloque devuelve `nil` con el mismo criterio que un CC sin
    /// asignar: no publica y no es un error.
    public func padIndex(for note: MIDINote) -> Int? {
        let offset = Int(note.value) - Int(padBlock.value)
        guard (0..<PadSurface.padCount).contains(offset) else { return nil }
        return offset
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
