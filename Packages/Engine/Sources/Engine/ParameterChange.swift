/// Qué parámetro se movió entre dos Tracks, y en cuánto quedó.
///
/// **Existe para el valor grande transitorio.** `product-guidelines.md` pide que
/// al girar un knob su valor aparezca en grande y se desvanezca; para eso hay
/// que saber cuál se movió, y eso es la diferencia entre el Track de antes y el
/// de después. Es dominio, no presentación: la vista solo decide el tamaño de la
/// letra.
///
/// **Se llamaba `ShapeChange` y comparaba dos Shapes.** Groove vive en `Cycle`,
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

    /// El nombre del parámetro: `Pulses`, `Delay`, `Division`.
    ///
    /// **Va aparte del valor desde el 2026-09-06.** El handoff de iPadOS dibuja
    /// la lectura grande en dos renglones y la vista necesita las dos piezas por
    /// separado. Partir `description` buscando el espacio habría funcionado hoy
    /// y se habría roto en silencio el día que un valor lleve uno.
    public let label: String

    /// Cómo quedó, ya escrito y con su unidad si la tiene.
    public let value: String

    /// Las dos cosas pegadas, que es como se venía leyendo.
    ///
    /// El término de la Pre Spec y el valor, sin adornos: la app informa, no
    /// conversa (`product-guidelines.md`).
    public var description: String { "\(label) \(value)" }

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
    public init?(from previous: Cycle, to current: Cycle) {
        guard previous != current else { return nil }

        let previousShape = previous.shape
        let shape = current.shape
        let previousGroove = previous.groove
        let groove = current.groove
        let previousRepeater = previous.noteRepeater
        let repeater = current.noteRepeater

        // **La cadena decide a cuál se le da voz, no cómo se escribe.** Los
        // nueve cuerpos eran idénticos desde que `TrackParameter.value(in:)`
        // existe, así que el orden se queda —es el de `TrackParameter`, primero
        // Shape y después Groove, declarado y no heredado del azar— y la
        // escritura se hace una sola vez debajo.
        let moved: TrackParameter
        if previousShape.steps != shape.steps {
            moved = .steps
        } else if previousShape.pulses != shape.pulses {
            moved = .pulses
        } else if previousShape.rotate != shape.rotate {
            moved = .rotate
        } else if previousShape.division != shape.division {
            moved = .division
        } else if previousRepeater.repeats != repeater.repeats {
            moved = .repeats
        } else if previousRepeater.time != repeater.time {
            moved = .repeatTime
        } else if previousRepeater.ramp != repeater.ramp {
            moved = .ramp
        } else if previousRepeater.pace != repeater.pace {
            moved = .pace
        } else if previousGroove.velocity != groove.velocity {
            moved = .velocity
        } else if previousGroove.sustain != groove.sustain {
            moved = .sustain
        } else if previousGroove.probability != groove.probability {
            moved = .probability
        } else if previousGroove.timing != groove.timing {
            moved = .timing
        } else if previousGroove.delay != groove.delay {
            moved = .delay
        } else {
            // Cambió algo que no es un parámetro ajustable: el pool.
            return nil
        }

        parameter = moved
        label = moved.description
        value = moved.value(in: current)
    }
}
