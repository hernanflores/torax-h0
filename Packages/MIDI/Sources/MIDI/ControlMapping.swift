import Engine

/// El preset del BeatStep Pro: qué significa cada control físico.
///
/// **Describe las tres familias del controlador** —los dieciséis knobs, los
/// dieciséis pads y los dieciséis step buttons— y también lo que
/// deliberadamente no se asigna, que es la mitad de lo que hace útil a un
/// preset: sin decir qué se ignora, cualquier mensaje inesperado parece un
/// defecto.
///
/// **Es fija.** Reasignarla a otro hardware es MIDI Learn, que es la rebanada 8
/// del MVP; hasta entonces los números viven aquí, en un solo sitio, y el
/// preset cargable del repositorio tiene que declarar los mismos.
public struct ControlMapping: Equatable, Sendable {

    /// El preset del BeatStep Pro.
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
    public static let beatStepPro = ControlMapping(assignments: [
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

    /// CC por defecto del primer knob; los dieciséis van seguidos desde ahí.
    ///
    /// **Los nueve primeros son los nueve parámetros del Track**, en el orden de
    /// `TrackParameter`, que es también el orden de la pantalla: la fila de
    /// knobs se lee igual que la lista de parámetros. Los siete restantes
    /// —knobs 10 a 16— se declaran y no se asignan; su sitio es de v2, con
    /// Cycles, Accent, Repeats, Time, Voicing y Range.
    public static let defaultKnobBlock = MIDIController(70)!

    /// CC por defecto del primer step button; los dieciséis van seguidos.
    ///
    /// El bloque 102–117 está sin definir en la especificación MIDI, así que no
    /// pisa nada con significado asignado ni se solapa con los knobs.
    public static let defaultStepButtonBlock = MIDIController(102)!

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

    /// CC del primer knob; los dieciséis son consecutivos desde él.
    public let knobBlock: MIDIController

    /// CC del primer step button; los dieciséis son consecutivos desde él.
    public let stepButtonBlock: MIDIController

    public init(
        assignments: [TrackParameter: Int],
        padBlock: MIDINote = defaultPadBlock,
        knobBlock: MIDIController = defaultKnobBlock,
        stepButtonBlock: MIDIController = defaultStepButtonBlock
    ) {
        self.assignments = assignments
        self.padBlock = padBlock
        self.knobBlock = knobBlock
        self.stepButtonBlock = stepButtonBlock
    }

    /// Cuántos controles lleva cada familia del BeatStep Pro.
    public static let controlsPerFamily = 16

    /// Los números que ocupa cada familia: knobs, pads y step buttons.
    ///
    /// Es la tabla del preset, y lo que permite comprobar de una vez que
    /// ninguna familia pisa a otra.
    var declaredNumbers: (knobs: [Int], pads: [Int], stepButtons: [Int]) {
        let span = { (start: Int) in (0..<Self.controlsPerFamily).map { start + $0 } }
        return (
            knobs: span(knobBlock.number),
            pads: span(Int(padBlock.value)),
            stepButtons: span(stepButtonBlock.number)
        )
    }

    /// Índice 0–15 del step button que envió ese CC, o `nil` fuera del bloque.
    public func stepButtonIndex(for controller: MIDIController) -> Int? {
        let offset = controller.number - stepButtonBlock.number
        guard (0..<Self.controlsPerFamily).contains(offset) else { return nil }
        return offset
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
