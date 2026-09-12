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
    /// Los números no pisan controladores con significado asignado en la
    /// especificación MIDI: ni volumen, ni paneo, ni pedal. Los cuatro de Shape
    /// y los cinco de Groove, en un bloque contiguo desde el 70.
    ///
    /// > **Nota del 2026-09-05 — la regla era «no pisar nada asignado», no
    /// > «70–79».** Esto decía que los números salen «del rango de controladores
    /// > de propósito general (70–79)» y que los nueve «caben sin salir del
    /// > rango». Las dos frases describían la tabla de entonces, no la regla: el
    /// > 79 no tiene nada de especial y los CC 80–85 tampoco están asignados en
    /// > la especificación. Se reescribe al mover el knob del Cycle al 82, que
    /// > con el texto viejo habría parecido una excepción cuando no lo es.
    ///
    /// > **Nota del 2026-09-05 — el orden de los CC ya no sigue al de
    /// > `TrackParameter`.** Esto decía que sí, y de ahí que «la fila de knobs se
    /// > lea igual que la lista de parámetros». Con Delay en el 76 y Probability
    /// > en el 78 deja de ser cierto. **La pantalla conserva el orden del
    /// > dominio** —`Velocity · Sustain · Probability · Timing · Delay`—: el
    /// > orden de lectura es del dominio y el de los knobs es de la mano, y desde
    /// > esta fecha son dos cosas distintas. Quien busque la correspondencia
    /// > tiene la tabla en `preset/README.md`, que es donde debía estar.
    public static let beatStepPro = ControlMapping(assignments: [
        .steps: 70,
        .pulses: 71,
        .rotate: 72,
        .division: 73,
        .velocity: 74,
        .sustain: 75,
        .delay: 76,
        .timing: 77,
        .probability: 78,
        // Los cuatro del Note Repeater, desde el 2026-09-07. El 79 lo dejó libre
        // a propósito `ctrl-all_20260905` al mover el knob del Cycle al 82; el
        // 80, el 81 y el 83 no pisan nada con significado asignado en la
        // especificación MIDI. El 82 se salta porque es el knob del Cycle.
        .repeats: 79,
        .repeatTime: 80,
        .ramp: 81,
        .pace: 83,
    ])

    /// CC por defecto del primer knob; los dieciséis van seguidos desde ahí.
    ///
    /// **Catorce de los dieciséis están asignados**: trece parámetros del Track
    /// y el knob del Cycle en edición, que es el 13.
    ///
    /// > **Decía «los nueve primeros, en el orden de `TrackParameter`» y que los
    /// > siete restantes eran de v2, «con Cycles, Accent, Repeats, Time, Voicing
    /// > y Range».** De esa lista ya entraron tres: el Cycle en edición el
    /// > 2026-09-05 y Repeats y Time el 2026-09-07, con Ramp y Pace detrás. El
    /// > orden dejó de seguir al de `TrackParameter` el 2026-09-05, cuando Delay
    /// > y Probability se intercambiaron — la nota de `beatStepPro` lo explica.
    ///
    /// **Quedan libres el 15 y el 16** (CC 84 y 85), declarados a propósito: su
    /// sitio es de v2, con Accent, Voicing y Range. Girarlos no hace nada y no es
    /// un error.
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

    /// La tabla entera, para quien tenga que reconstruir el mapeo cambiando otra
    /// cosa.
    ///
    /// **Existe porque los bloques y las asignaciones se editan por separado**:
    /// aprender el primer pad mueve un bloque y tiene que dejar la tabla igual.
    /// Sin esto, quien mueve un bloque tendría que elegir entre exponer el
    /// diccionario o perder las asignaciones.
    var allAssignments: [TrackParameter: Int] { assignments }

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

    /// Posición del knob del Cycle en edición dentro del bloque, contando desde
    /// cero: el decimosexto.
    ///
    /// **Es un dato del mapeo y no un desplazamiento escondido en el código.**
    /// Hasta el 2026-09-05 el CC se calculaba como `knobBlock.number + 9` dentro
    /// de la propiedad de abajo, y eso hacía que mover un knob fuera un cambio de
    /// aritmética en vez de un cambio de tabla — que es exactamente lo que un
    /// mapeo existe para evitar.
    public static let editingCycleKnobOffset = 15

    /// CC del knob que mueve el Cycle en edición: el último del bloque.
    ///
    /// **No es un `TrackParameter`, y por eso no está en `assignments`.** Los
    /// trece primeros knobs mueven parámetros del Cycle; este mueve *a cuál* de
    /// ellos se está apuntando, que es una operación de otro orden. Meterlo en
    /// la tabla obligaría a inventarle un caso al enum que el modelo no tiene.
    ///
    /// > **Nota del 2026-09-12 — se fue al knob 16, CC 85.** Estaba en el 13
    /// > desde el 2026-09-05, pegado a los parámetros, y la nota de aquel día
    /// > decía que separarlo «dice con la mano lo que el modelo ya decía». Lo
    /// > decía a medias: el knob de al lado sigue siendo el knob de al lado, y
    /// > con los cuatro del Note Repeater dentro la fila ya no tenía frontera
    /// > visible donde acababan los parámetros.
    /// >
    /// > En la esquina del bloque lo separan **dos knobs libres**, que es un
    /// > hueco que la mano nota sin mirar, y el CC 82 queda para Delay — que es
    /// > lo que el reordenamiento de `knob-layout_20260912` necesitaba: la fila
    /// > de abajo entera para el card Groove.
    ///
    /// > **Nota del 2026-09-05 — se movió del knob 10 al 13.** Estaba en el 79,
    /// > pegado a los nueve parámetros, y este comentario decía que «el sitio
    /// > sigue siendo el correcto» porque el 79 cerraba el rango de propósito
    /// > general. Ninguna de las dos cosas se sostiene: el rango no era la regla
    /// > —ver la nota de `beatStepPro`— y estar pegado a los nueve era
    /// > precisamente lo que confundía la fila. Separarlo dice con la mano lo que
    /// > el modelo ya decía. **El CC 79 queda libre**, declarado a propósito
    /// > como los otros cinco.
    ///
    /// > **Desviación de la Pre Spec, anotada el 2026-09-02.** La tabla de Shape
    /// > dice «Cycles: selecciona/edita el Cycle actual; **con CTRL** ajusta 1–16
    /// > Cycles activos». El BeatStep Pro no tiene CTRL, así que el knob se queda
    /// > con la mitad primaria —mover el Cycle en edición— y cuántos hay activos
    /// > se ajusta táctilmente, que es donde `product-guidelines.md` pone la
    /// > configuración. La nota fechada está en la Pre Spec.
    public var editingCycleController: MIDIController? {
        MIDIController(knobBlock.number + Self.editingCycleKnobOffset)
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

    /// El mismo mapeo con ese controlador moviendo ese parámetro.
    ///
    /// **Es la operación de MIDI Learn** (`midi-learn_20260908`, FR4), y su
    /// regla es que un destino tiene un control y un control mueve un destino.
    /// Las dos mitades, porque solo una deja el mapeo mintiendo:
    ///
    /// - El parámetro **suelta el controlador que tuviera**. Reasignar Steps del
    ///   70 al 20 deja el 70 sin dueño, no a Steps con dos knobs.
    /// - El controlador **desasigna al parámetro que lo tuviera**. Aprender el
    ///   knob de Steps para Pulses deja a Steps sin control, no a los dos
    ///   escuchando el mismo giro.
    ///
    /// **Un destino sin control es un estado válido** (FR5), no un error. Se
    ///  puede preguntar por `parametersWithoutController`, que es lo que la
    ///  pantalla necesita para decir en voz alta lo que acaba de quedarse mudo.
    ///
    /// Los tres bloques no se tocan: no son de `assignments`, y aprender un knob
    /// no puede mover los pads de sitio.
    public func assigning(
        _ controller: MIDIController, to parameter: TrackParameter
    ) -> ControlMapping {
        var updated = assignments
        updated = updated.filter { $0.value != controller.number }
        updated[parameter] = controller.number

        return ControlMapping(
            assignments: updated,
            padBlock: padBlock,
            knobBlock: knobBlock,
            stepButtonBlock: stepButtonBlock
        )
    }

    /// Los parámetros que no tienen control, **en el orden del dominio**.
    ///
    /// El orden lo da `TrackParameter.allCases` y no el diccionario: un listado
    /// que baila entre ejecuciones haría que la pantalla se reordenara sola.
    ///
    /// Con el preset de fábrica está vacío, y esa es la condición que lo hace
    /// útil como respuesta: si aparece algo, es que alguien aprendió encima.
    public var parametersWithoutController: [TrackParameter] {
        TrackParameter.allCases.filter { controller(for: $0) == nil }
    }

    /// El mapeo en números, para que el `Project` lo guarde.
    ///
    /// **`Engine` no puede ver CoreMIDI**, así que lo que cruza la frontera son
    /// enteros. Es el mismo reparto por el que el destino se recuerda por su
    /// nombre y no por su `MIDIEndpointRef`.
    public var numbers: ControlNumbers {
        ControlNumbers(
            assignments: assignments,
            padBlock: Int(padBlock.value),
            knobBlock: knobBlock.number,
            stepButtonBlock: stepButtonBlock.number
        )
    }

    /// El mapeo que describen esos números.
    ///
    /// **Lo imposible se descarta en vez de impedir la apertura**, con el mismo
    /// criterio que una escala desconocida cayendo en `minor`: un `Int` del
    /// disco no promete ser un controlador válido. Una asignación fuera de rango
    /// se pierde —el destino se queda sin control, que es un estado válido— y un
    /// bloque fuera de rango cae en el de fábrica, porque un mapeo sin pads no
    /// lo es.
    public init(_ numbers: ControlNumbers) {
        let restored = ControlMapping(
            assignments: numbers.assignments.filter { MIDIController($0.value) != nil },
            padBlock: MIDINote(numbers.padBlock) ?? Self.defaultPadBlock,
            knobBlock: MIDIController(numbers.knobBlock) ?? Self.defaultKnobBlock,
            stepButtonBlock: MIDIController(numbers.stepButtonBlock)
                ?? Self.defaultStepButtonBlock
        )
        self = restored.hasConflict ? .beatStepPro : restored
    }

    /// Si algún control significaría dos cosas.
    ///
    /// **Un mapeo aprendido sí puede provocarlo.** Knobs y step buttons son los
    /// dos CC, y el preset de fábrica solo evita el choque porque alguien lo
    /// escribió mirando la tabla; construyendo el mapeo control a control esa
    /// garantía desaparece. Los pads son notas y viven en otro espacio de
    /// numeración, así que no entran en la comparación.
    ///
    /// > **Lo que un conflicto provoca está medido en dispositivo, no supuesto**
    /// > (2026-09-09). Se aprendió un bloque con un knob, el de step buttons
    /// > aterrizó encima de los CC de los knobs, y desde entonces **cada giro
    /// > cambiaba de Track**: `receive` despacha los step buttons antes que los
    /// > knobs. Y se guardaba con la sesión, así que sobrevivía a relanzar la
    /// > app; la única salida era el botón de fábrica.
    ///
    /// Son dos formas del mismo choque, y las dos tienen el mismo síntoma:
    ///
    /// - **Dos bloques encima**, que hace step buttons de una fila de knobs.
    /// - **Un parámetro dentro del bloque de step buttons**, que deja a ese
    ///   parámetro sin poder moverse nunca — el despacho no llega a él.
    public var hasConflict: Bool {
        let numbers = declaredNumbers
        if !Set(numbers.knobs).isDisjoint(with: Set(numbers.stepButtons)) { return true }
        if assignments.values.contains(where: { numbers.stepButtons.contains($0) }) {
            return true
        }
        guard let editingCycleController else { return false }
        return assignments.values.contains(editingCycleController.number)
    }
}
