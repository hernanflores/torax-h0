/// La forma del movimiento que la modulación imprime a la velocity.
///
/// **Cuatro casos y ninguno más**, tal y como los lista la Pre Spec.
///
/// > **Se llama `waveform` y no `Groove`.** La Pre Spec usa *Groove* para dos
/// > cosas —la familia de Velocity, Sustain, Probability, Timing y Delay, y el
/// > knob que escoge la forma del LFO— y el motor ya gastó el término en la
/// > primera: `Groove` es un tipo de este mismo paquete.
/// > `product-guidelines.md` pide un solo término por concepto, así que la
/// > forma toma el nombre con el que el propio handoff de diseño la rotula.
/// > Desviación fechada el 2026-09-08 en `Pre Spec Torax H-0.md`.
///
/// **El orden de `allCases` es el que dibuja la rejilla 2×2 de la pantalla**
/// (FR11), así que es parte del contrato y no un detalle del compilador.
public enum Waveform: CaseIterable, Equatable, Sendable {

    /// Rampa ascendente con un corte: sube, salta al fondo y vuelve a subir.
    case saw

    /// Subida y bajada simétricas. El default.
    case triangle

    /// La misma forma que `triangle`, redondeada. Se resuelve por tabla entera
    /// —ver `Waveform.value(atStep:of:)`—, nunca con `sin()`.
    case sine

    /// Dos valores y nada entre ellos: media vuelta arriba, media abajo.
    case pulse

    /// Default del producto.
    ///
    /// **`triangle` y no `saw`** porque es la forma que sube y baja
    /// simétricamente, que es la lectura menos sorprendente de «modulación» —y
    /// la única de las cuatro que no introduce ni un salto ni una asimetría que
    /// haya que explicar. Con `accent` en 0 da igual cuál sea, porque ninguna
    /// se aplica; importa el día que se sube el slider sin haber elegido forma.
    public static let `default` = Waveform.triangle
}

extension Waveform: CustomStringConvertible {

    /// **El mismo término en minúscula** (FR2, FR20).
    ///
    /// Vive en `Engine` y no en la vista por la razón de siempre: `workflow.md`
    /// dice que si algo en `App` merece un test está en el sitio equivocado, y
    /// un formato es exactamente eso.
    public var description: String {
        switch self {
        case .saw: "saw"
        case .triangle: "triangle"
        case .sine: "sine"
        case .pulse: "pulse"
        }
    }
}

/// Cuánto se desvía la velocity a lo largo de la vuelta, con signo.
///
/// Término de la Pre Spec: «amplitud de variación de velocity alrededor de
/// Velocity base».
///
/// **Bipolar y simétrico, como `Delay`, `Ramp` y `Pace`**: el cero es el centro
/// y se cruza sin caso especial. El signo invierte la forma, así que un
/// `triangle` con accent negativo empieza bajando — es la misma onda leída del
/// otro lado, no una quinta forma.
///
/// **El 0 está dentro del rango y es el default.** No es un extremo incómodo:
/// es el valor que **apaga** la modulación, y de él depende toda la no regresión
/// de la rebanada. Con `accent = 0` la salida es la de antes — instantes,
/// velocities y consumo de aleatoriedad.
///
/// > **No tiene knob**, a diferencia del resto de parámetros de Groove: se
/// > edita con el dedo en la pantalla `modulation`, que cae del lado táctil de
/// > la frontera del 2026-09-06. El coste está escrito y es real — Ctrl All,
/// > Temp y la lectura transitoria grande no lo alcanzan, porque los tres
/// > operan sobre `TrackParameter`. Desviación fechada el 2026-09-08 en
/// > `Pre Spec Torax H-0.md`.
///
/// Valida en el inicializador, como `Velocity` y `Ramp`: un `Accent` que existe
/// es siempre aplicable.
public struct Accent: Equatable, Sendable {

    /// Rango admitido. Simétrico: la excursión entera hacia cada lado.
    public static let validRange: ClosedRange<Int> = -100...100

    /// Default del producto: sin modulación. Con él, la salida es la de antes de
    /// la rebanada.
    public static let `default` = Accent(unchecked: 0)

    public let percent: Int

    /// Devuelve `nil` si el porcentaje cae fuera de `validRange`.
    public init?(percent: Int) {
        guard Self.validRange.contains(percent) else { return nil }
        self.percent = percent
    }

    /// Vía interna para valores ya acotados. Ver `Velocity.init(unchecked:)`.
    init(unchecked percent: Int) {
        self.percent = percent
    }
}

extension Accent {

    /// El accent resultante de mover el slider `delta` unidades.
    ///
    /// **No lo mueve un knob sino un dedo arrastrando** (FR9, FR18), y por eso
    /// el parámetro se llama `delta` igual que en los demás: la aritmética es la
    /// misma aunque el gesto no lo sea.
    ///
    /// **Se detiene en los extremos, no envuelve.** Ver `Sustain.advanced(by:)`.
    /// Aquí pesa más que en los knobs: un arrastre largo del dedo produce deltas
    /// grandes de golpe, y envolver haría que pasarse del acento máximo devolviera
    /// el mínimo — el cambio más brutal que el parámetro admite, justo donde
    /// `product-guidelines.md` pide «un cambio inmediato y proporcional».
    ///
    /// **El cero no es un punto de parada.** Se cruza como cualquier otro valor;
    /// el imantado cerca del centro (FR18) es de la vista, que sabe cuántos
    /// puntos de pantalla son «cerca», y no del tipo.
    ///
    /// Adjusts the accent by the specified amount while keeping it within the valid range.
    /// - Parameter delta: The amount to add to the accent percentage.
    /// - Returns: A percentage clamped between −100 and 100.
    public func advanced(by delta: Int) -> Accent {
        Accent(unchecked: Self.validRange.clamping(percent + delta))
    }
}
