/// Qué parámetro se movió entre dos Tracks, y en cuánto quedó.
///
/// **Existe para el valor grande transitorio.** `product-guidelines.md` pide que
/// al girar un knob su valor aparezca en grande y se desvanezca; para eso hay
/// que saber cuál se movió, y eso es la diferencia entre el Track de antes y el
/// de después. Es dominio, no presentación: la vista solo decide el tamaño de la
/// letra.
///
/// **Se llamaba `ShapeChange` y comparaba dos Shapes.** Groove vive en `Track`,
/// así que la comparación sube un nivel. No es una generalización preventiva:
/// con Velocity, Sustain y Probability en el snapshot, comparar Shapes dejaría
/// tres de los siete parámetros sin poder anunciarse.
///
/// **Por qué no lo dice quien recibe el mensaje.** La entrada de control sí sabe
/// qué parámetro mapea un CC, pero también hay giros que no mueven nada —girar
/// contra un extremo— y publicaciones que no vienen de un knob. Comparar los dos
/// Tracks responde por el resultado y no por la intención, que es lo que la
/// pantalla debe reflejar.
public struct ParameterChange: Equatable, Sendable {

    /// Qué se movió.
    public let parameter: TrackParameter

    /// Cómo quedó, listo para leerse.
    ///
    /// El término de la Pre Spec y el valor, sin adornos: la app informa, no
    /// conversa (`product-guidelines.md`).
    public let description: String

    /// Compara dos Tracks. Devuelve `nil` si no se movió ningún parámetro.
    ///
    /// `nil` es el caso común y no es un error: llegan mensajes que no mueven
    /// nada y giros contra un extremo. Anunciar un valor ahí sería decir que
    /// pasó algo cuando no pasó.
    ///
    /// **El pool tampoco se anuncia.** Cambia con los pads, no con un knob, y
    /// tiene su propia representación permanente en pantalla; levantar un valor
    /// grande por él lo trataría como lo que no es.
    ///
    /// **Solo se anuncia el primero que difiera.** Un giro mueve un parámetro,
    /// así que el caso de dos a la vez no se produce por un knob; si el Track
    /// cambiara entero —al cargar un Cycle, algún día— anunciar siete valores
    /// grandes a la vez sería peor que anunciar uno.
    ///
    /// El orden de comparación es el de `TrackParameter`: primero Shape, después
    /// Groove. Va declarado y no heredado del azar.
    public init?(from previous: Track, to current: Track) {
        guard previous != current else { return nil }

        let previousShape = previous.shape
        let shape = current.shape
        let previousGroove = previous.groove
        let groove = current.groove

        if previousShape.steps != shape.steps {
            parameter = .steps
            description = "Steps \(shape.steps.count)"
        } else if previousShape.pulses != shape.pulses {
            parameter = .pulses
            // El valor pedido, no `effectivePulses`: el knob está en este número
            // y mostrar el otro haría creer que se perdió.
            description = "Pulses \(shape.pulses.count)"
        } else if previousShape.rotate != shape.rotate {
            parameter = .rotate
            description = "Rotate \(shape.rotate.amount)"
        } else if previousShape.division != shape.division {
            parameter = .division
            description = "Division \(shape.division)"
        } else if previousGroove.velocity != groove.velocity {
            parameter = .velocity
            // Sin signo de porcentaje: Velocity vive en la unidad MIDI, y
            // ponérselo diría que es un porcentaje de algo.
            description = "Velocity \(groove.velocity.value)"
        } else if previousGroove.sustain != groove.sustain {
            parameter = .sustain
            description = "Sustain \(groove.sustain.percent)%"
        } else if previousGroove.probability != groove.probability {
            parameter = .probability
            description = "Probability \(groove.probability.percent)%"
        } else {
            // Cambió algo que no es un parámetro ajustable: el pool.
            return nil
        }
    }
}
