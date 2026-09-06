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
/// Qué gesto momentáneo está puesto, si hay alguno.
///
/// **Existe porque un `Bool` dejó de bastar el 2026-09-05.** Hasta entonces el
/// panel solo tenía que distinguir «temporal» de «permanente», y `isTemporary`
/// lo decía. Con Ctrl All hay dos gestos temporales, y lo que el usuario necesita
/// saber con las manos ocupadas no es si el cambio sobrevivirá a soltar —los dos
/// son reversibles— sino **si está moviendo un Track o los doce**. Un distintivo
/// compartido no lo diría.
///
/// **Los dos nunca están puestos a la vez**: con el step 13 y el 14 hundidos
/// manda Temp, y quien resuelve el empate es `ControlInput`, no la vista. Por eso
/// esto es un caso y no un juego de banderas.
public enum ReadoutGesture: Equatable, Sendable, CaseIterable {

    /// Nada puesto: lo que se lee es el Pattern, y sobrevivirá.
    case none

    /// Temp: superpuesto sobre el Track seleccionado.
    case temp

    /// Ctrl All: desplazado en los doce Tracks.
    case ctrlAll

    /// El texto del distintivo, o `nil` si no hay gesto.
    ///
    /// Los términos son los que ancla la Pre Spec —«Temp» y «Ctrl All»— y no se
    /// inventan sinónimos para pantalla (NFR7): lo que se lee es lo que el
    /// usuario usará para pensarlo.
    var marker: String? {
        switch self {
        case .none: nil
        case .temp: "Temp"
        case .ctrlAll: "Ctrl All"
        }
    }
}

public struct FamilyReadout: Equatable, Sendable {

    /// El nombre del parámetro que encabeza la familia: `Pulses`, `Velocity`,
    /// `Scale`.
    ///
    /// **Va aparte del valor desde el 2026-09-06**, porque el handoff de iPadOS
    /// dibuja la lectura en dos renglones: el nombre pequeño encima y el valor
    /// grande debajo. Partir `headline` en la vista buscando el espacio habría
    /// funcionado hoy y se habría roto en silencio el día que un valor lleve uno
    /// —`1/16` no lo lleva, pero nadie lo garantiza—. Aquí no hay que buscar
    /// nada: se construyen por separado.
    public let label: String

    /// El valor, ya escrito. Es lo que se lee a un metro.
    public let value: String

    /// Las dos cosas pegadas, que es como lo escribe un valor transitorio.
    ///
    /// Se conserva porque reposo y giro tienen que leerse en el mismo idioma:
    /// girar Pulses hasta 6 y estar en reposo con Pulses 6 producen el mismo
    /// texto. **En Shape ya no coinciden del todo**: la lectura en reposo añade
    /// el denominador, y `headline` se queda con la forma corta.
    public let headline: String

    /// El resto de la familia, en una línea pequeña.
    public let detail: String

    /// El distintivo del gesto que está puesto, o `nil` en reposo.
    ///
    /// > **Por qué hace falta.** Con Temp puesto, la lectura, el anillo y el
    /// > valor grande ya enseñan los valores superpuestos sin ningún camino
    /// > aparte: el overlay se escribe en el `Pattern` publicado y llega por el
    /// > de siempre. Eso resuelve *qué* se ve y deja sin resolver lo otro — un
    /// > fill puesto y una edición permanente se leen **exactamente igual**, así
    /// > que nadie puede saber si lo que tiene delante sobrevivirá a soltar el
    /// > botón. El distintivo es lo único que los separa.
    ///
    /// **Sale en las tres familias**, porque Temp alcanza a los nueve
    /// parámetros: depender del tab que se esté mirando dejaría el fill sin
    /// marcar en dos de cada tres pantallas.
    ///
    /// **Y desde el 2026-09-05 dice *cuál* de los dos gestos**, no solo que hay
    /// uno. Temp y Ctrl All son reversibles los dos, así que «esto es temporal»
    /// no distinguiría lo único que importa con las manos ocupadas: si lo que se
    /// mueve es un Track o los doce. El texto lo decide `ReadoutGesture`.
    public let marker: String?

    public init(track: Cycle, family: ParameterFamily, gesture: ReadoutGesture = .none) {
        marker = gesture.marker
        switch family {
        case .shape:
            let shape = track.shape
            label = "Pulses"
            // **Sobre cuántos Steps reparte, que es lo que el handoff escribe.**
            // Pulses solo significa algo contra su denominador: 5 de 16 y 5 de 12
            // son dos densidades distintas, y el número solo no las separa.
            //
            // Es el valor **pedido**, no `effectivePulses`. La enmienda del
            // 2026-08-27 separó los dos: el knob está en este número y la lectura
            // acompaña al knob; lo que suena —`min(pulses, steps)`— lo enseña el
            // anillo, que es donde se ve.
            value = "\(shape.pulses.count) / \(shape.steps.count)"
            headline = "Pulses \(shape.pulses.count)"
            detail =
                "Steps \(shape.steps.count) · Rotate \(shape.rotate.amount) "
                + "· Division \(shape.division)"

        case .groove:
            let groove = track.groove
            label = "Velocity"
            value = "\(groove.velocity.value)"
            headline = "Velocity \(groove.velocity.value)"
            detail =
                "Sustain \(groove.sustain.percent)% · Probability \(groove.probability.percent)% "
                + "· Timing \(groove.timing.percent)% · Delay \(groove.delay.percent)%"

        case .tonal:
            // **Aquí la etiqueta se añade, no se extrae.** En Shape y Groove el
            // nombre del parámetro ya estaba dentro del `headline` y partirlo lo
            // separa; en Tonal no hay nombre que separar, porque el marco *es* el
            // valor —TONAL no tiene knob detrás— y el `headline` siempre fue
            // `C Minor` a secas.
            //
            // Así que `value` repite el `headline` y `label` es una etiqueta
            // nueva que solo existe para el renglón pequeño del handoff. La
            // consecuencia, escrita para que nadie la tome por un descuido: en
            // Tonal `label + value` **no** reconstruye el `headline`, y el test
            // que comprueba esa identidad excluye la familia a propósito.
            label = "Scale"
            value = "\(track.frame.root) \(Self.name(of: track.frame.scale))"
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
