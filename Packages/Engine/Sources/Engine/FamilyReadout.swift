/// Qué dice el panel de lectura cuando no se está girando nada.
///
/// **La forma es la del handoff**: una lectura grande y una línea pequeña
/// debajo. La grande se escribe **con el mismo formato que un valor
/// transitorio** —el término de la Pre Spec y el valor, sin adornos— para que
/// reposo y giro no se lean como dos idiomas distintos: girar el knob de Pulses
/// hasta 6 y estar en reposo con Pulses 6 producen exactamente el mismo texto.
///
/// **Vive en `Engine` porque es texto de dominio.** Qué valor encabeza cada
/// familia y cómo se escribe son decisiones que se rompen en silencio —una
/// etiqueta mal puesta se sigue dibujando— y `workflow.md` manda que eso no esté
/// en `App`, donde no hay tests. La vista compone; no elige palabras.
///
/// > **Qué valor encabeza, y por qué ése.** Una familia tiene varios parámetros
/// > y la lectura grande es uno solo, así que hay una elección y conviene que
/// > esté escrita:
/// >
/// > - **Shape → Pulses.** Es lo que el propio handoff pone en su mock
/// >   («PULSES 5») y es el parámetro que define el carácter del reparto una vez
/// >   fijados los Steps: 16/4 y 16/5 son dos patrones distintos, 16/5 y 12/5 son
/// >   el mismo gesto a otra escala.
/// > - **Groove → Velocity.** Es el único de los cinco que se oye en cada nota
/// >   sin depender de nada más; Sustain, Probability, Timing y Delay modifican
/// >   *cómo* o *cuándo*, no *cuánto* suena.
/// > - **Tonal → el marco.** No hay elección: TONAL no tiene parámetros de knob
/// >   detrás (FR4), y Scale y Root son lo que restringe todo lo demás.
public struct FamilyReadout: Equatable, Sendable {

    /// La lectura grande, la que se lee a un metro.
    public let headline: String

    /// El resto de la familia, en una línea pequeña.
    public let detail: String

    public init(track: Track, family: ParameterFamily) {
        switch family {
        case .shape:
            let shape = track.shape
            headline = "Pulses \(shape.pulses.count)"
            detail =
                "Steps \(shape.steps.count) · Rotate \(shape.rotate.amount) "
                + "· Division \(shape.division)"

        case .groove:
            let groove = track.groove
            headline = "Velocity \(groove.velocity.value)"
            detail =
                "Sustain \(groove.sustain.percent)% · Probability \(groove.probability.percent)% "
                + "· Timing \(groove.timing.percent)% · Delay \(groove.delay.percent)%"

        case .tonal:
            headline = "\(track.frame.root) \(Self.name(of: track.frame.scale))"
            detail = "Pool · \(Self.pool(track.pool.count))"
        }
    }

    /// **El pool vacío se dice, no se disimula.** Es el estado de quince Tracks
    /// al arrancar: disparan sus Pulses y no tienen material que emitir. Escribir
    /// «Pool · 0 pitches» sería contar algo que no hay; `product-guidelines.md`
    /// pide comunicar el estado, y el estado es que está vacío.
    ///
    /// El singular no es un detalle de estilo: una plantilla que dijera
    /// «1 pitches» delataría que la app rellena huecos en vez de informar.
    private static func pool(_ count: Int) -> String {
        switch count {
        case 0: "empty"
        case 1: "1 pitch"
        default: "\(count) pitches"
        }
    }

    /// Los nombres van en inglés y sin traducir, como el resto del vocabulario de
    /// interfaz (`product-guidelines.md`, NFR7).
    private static func name(of scale: Scale) -> String {
        switch scale {
        case .minor: "Minor"
        case .major: "Major"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .pentatonic: "Pentatonic"
        }
    }
}
