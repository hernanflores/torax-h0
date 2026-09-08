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

extension Accent: CustomStringConvertible {

    /// Cómo se lee `accent` en pantalla: `+34`, `-12`, `0`.
    ///
    /// **El signo se ve también en el positivo.** Es la convención que `Rotate`
    /// y `Delay` ya siguen para lo bipolar, y aquí es lo que separa «sube 34» de
    /// «el valor es 34»: sin él, la lectura grande de la pantalla no diría hacia
    /// dónde se desvía la velocity.
    ///
    /// **El 0 va sin signo.** No es un valor pequeño hacia ningún lado — es el
    /// que apaga la modulación—, y escribirlo `+0` le inventaría una dirección
    /// que no tiene.
    ///
    /// **Sin `%`.** El rango es −100…100 pero no es un porcentaje de nada
    /// nombrable: lo que desplaza son unidades MIDI, y el factor está en FR6.
    /// Ponerle el signo diría que es un porcentaje de la Velocity base, que es
    /// justo lo que no es.
    ///
    /// **Vive en `Engine` y no en la vista** (NFR6), por la razón de siempre:
    /// `workflow.md` dice que si algo en `App` merece un test está en el sitio
    /// equivocado, y un formato es exactamente eso.
    public var description: String {
        percent > 0 ? "+\(percent)" : "\(percent)"
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

extension Waveform {

    /// La excursión de la modulación, muestreada en el Step `step` de una vuelta
    /// de `stepCount` (FR4, FR5). Devuelve −100…100.
    ///
    /// **La fase sale del índice de Step dentro de la vuelta**, `p = step /
    /// stepCount`, y ahí está todo el diseño de la rebanada: un ciclo dura
    /// exactamente una vuelta del anillo porque así se calcula la fase, no
    /// porque nadie lo vigile. No hay reloj de modulación ni estado que
    /// mantener, y cada Track modula a su velocidad porque cada uno tiene sus
    /// Steps y su Division.
    ///
    /// **El índice envuelve sobre la vuelta**, como `Cycle.triggers(atStep:)`.
    ///
    /// **Todo pasa por `t = 400 · step / stepCount`**, la fase en cuartos de
    /// vuelta por cien: 0 en el arranque, 100 en el cuarto, 200 en la mitad, 300
    /// en los tres cuartos. Las cuatro formas son cuatro lecturas de ese mismo
    /// número, que es lo que garantiza que todas tengan el pico en el mismo
    /// sitio — cambiar de forma cambia el recorrido, no dónde cae el acento.
    ///
    /// - `triangle`: `t` mientras sube, `200 − t` mientras baja, `t − 400` en el
    ///   último cuarto. Los tres tramos coinciden en sus fronteras, así que la
    ///   forma es continua sin caso especial.
    /// - `saw`: la misma subida hasta el cuarto, y después **un solo corte** —
    ///   cae al fondo y vuelve a subir a un tercio de la pendiente, porque le
    ///   quedan tres cuartos de vuelta para recorrer lo que la subida hizo en
    ///   uno. El corte va en `p=¼` y no a media vuelta para que su pico coincida
    ///   con el de las otras tres.
    /// - `sine`: `sin(2πp)` **por tabla escrita de un cuarto de onda**, con las
    ///   otras tres cuartas partes por simetría. No se calcula con `sin()`:
    ///   `Engine` no importa nada fuera de la stdlib (NFR5) y esto corre en el
    ///   hilo del scheduler (NFR1).
    /// - `pulse`: arriba mientras la fase no llega a la mitad, abajo después.
    ///   **Con Steps impares el Step del medio cae en la mitad alta** —`t < 200`
    ///   equivale a `2·step < stepCount`— así que acentúa `ceil(steps/2)` de
    ///   `steps`. Es la misma regla, no un caso especial.
    ///
    /// **`pulse` es la excepción a «empieza en el centro» y no puede no serlo:**
    /// una onda de dos valores no pasa por el centro. Empieza arriba, que es lo
    /// que hace la forma útil para lo que sirve — acentuar media vuelta entera.
    ///
    /// Con `stepCount` no positivo devuelve el centro en vez de dividir por
    /// cero. `Steps` valida 1…64 y no puede producirlo, pero esto corre en el
    /// hilo del scheduler y ahí una división por cero es un crash.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Samples the modulation waveform at one step of a turn.
    /// - Parameters:
    ///   - step: The step index; it wraps around the turn.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The excursion, from −100 to 100.
    public func value(atStep step: Int, of stepCount: Int) -> Int {
        guard stepCount > 0 else { return 0 }

        // El módulo de Swift conserva el signo del dividendo, así que un índice
        // negativo se lleva de vuelta al anillo sumando una vuelta.
        let wrapped = ((step % stepCount) + stepCount) % stepCount
        let t = 400 * wrapped / stepCount

        switch self {
        case .triangle:
            if t <= 100 { return t }
            if t <= 300 { return 200 - t }
            return t - 400

        case .saw:
            if t <= 100 { return t }
            return -100 + (t - 100) / 3

        case .sine:
            if t <= 100 { return Self.quarterSine[t] }
            if t <= 200 { return Self.quarterSine[200 - t] }
            if t <= 300 { return -Self.quarterSine[t - 200] }
            return -Self.quarterSine[400 - t]

        case .pulse:
            return t < 200 ? 100 : -100
        }
    }

    /// Un cuarto de onda de seno, escrito y no calculado (NFR5).
    ///
    /// `quarterSine[i] = round(100 · sin(π·i/200))` para `i` de 0 a 100, que es
    /// el recorrido de la fase de 0 a un cuarto de vuelta. Las otras tres
    /// cuartas partes salen de esta por simetría, así que la tabla cuesta 101
    /// enteros y no 400.
    ///
    /// **La forma es una aproximación entera**, y a 16 Steps o menos —donde el
    /// muestreo pasa por una de cada seis entradas— es indistinguible de la
    /// curva exacta. Es la limitación que la spec del track anota.
    ///
    /// > **Es un global de inicialización perezosa, y eso se lee desde el hilo
    /// > del scheduler.** Leer una entrada no asigna nada, pero la **primera**
    /// > lectura del proceso corre el `swift_once` que construye el array. Es
    /// > exactamente el mismo idioma que `RepeatTime.ordered`, que la rebanada 5
    /// > ya lee desde ese hilo, así que no se inventa aquí un patrón nuevo. Si
    /// > algún día se quiere quitar del todo, la vía es una tupla de tamaño fijo
    /// > leída con `withUnsafePointer` — más barata y bastante menos legible, y
    /// > no se paga hasta que haya un motivo medido para pagarla.
    static let quarterSine: [Int] = [
        0, 2, 3, 5, 6, 8, 9, 11, 13, 14,
        16, 17, 19, 20, 22, 23, 25, 26, 28, 29,
        31, 32, 34, 35, 37, 38, 40, 41, 43, 44,
        45, 47, 48, 50, 51, 52, 54, 55, 56, 58,
        59, 60, 61, 63, 64, 65, 66, 67, 68, 70,
        71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
        81, 82, 83, 84, 84, 85, 86, 87, 88, 88,
        89, 90, 90, 91, 92, 92, 93, 94, 94, 95,
        95, 96, 96, 96, 97, 97, 98, 98, 98, 99,
        99, 99, 99, 99, 100, 100, 100, 100, 100, 100,
        100,
    ]
}

/// Los dos parámetros de la modulación de un Cycle.
///
/// **Vive dentro del `Cycle`**, junto a Shape, Groove, el pool y el Note
/// Repeater, por la misma razón que ellos: el hilo del scheduler necesita los
/// dos para decidir con cuánta fuerza emite un Step, y lo único que ese hilo lee
/// es el snapshot publicado. Cada Cycle tiene el suyo, así que un desarrollo A/B
/// puede acentuar solo en el B.
///
/// **Guarda un `Int8` y no un `Accent`**, que es el idioma que `NoteRepeater` ya
/// fijó: el campo cuesta dos bytes por Cycle —la onda es un `enum` sin carga—
/// contra los dieciséis que costaría almacenar los dos tipos enteros. Con doce
/// Tracks × dieciséis Cycles la diferencia son ~2,7 KB sobre los ~37 KB del
/// snapshot, y NFR2 presupone que este campo no se nota.
///
/// **Con el neutro no cambia nada de lo entregado**: `accent` en 0 devuelve la
/// Velocity base sin tocarla, igual que Repeats en 0 no ejecuta nada del camino
/// del Note Repeater.
public struct Modulation: Equatable, Sendable {

    /// El neutro: sin modulación, sobre `triangle`. Con él, la salida es la de
    /// antes de la rebanada — instantes, velocities y consumo de aleatoriedad.
    public static let `default` = Modulation()

    /// La forma del movimiento.
    public let waveform: Waveform

    private let storedAccent: Int8

    public init(waveform: Waveform = .default, accent: Accent = .default) {
        self.waveform = waveform
        storedAccent = Int8(accent.percent)
    }

    /// Cuánto se desvía la velocity, con signo.
    public var accent: Accent { Accent(unchecked: Int(storedAccent)) }

    /// La misma `Modulation` con lo que se le cambie, y todo lo demás intacto.
    ///
    /// Mismo idioma que `Cycle.with(...)` y `NoteRepeater.with(...)`, y por la
    /// misma razón: reconstruirla a mano pierde en silencio lo que no se nombre.
    public func with(waveform: Waveform? = nil, accent: Accent? = nil) -> Modulation {
        Modulation(waveform: waveform ?? self.waveform, accent: accent ?? self.accent)
    }
}

extension Modulation {

    /// Cuánto se desvía la velocity en el Step `step` de una vuelta de
    /// `stepCount`, en unidades MIDI con signo (FR6).
    ///
    /// ```
    /// offset = wave(p) · accent · 63 / 10000      // wave ∈ −100…100
    /// ```
    ///
    /// **El 63 es media excursión del rango MIDI**, así que `accent = ±100`
    /// sobre el pico de la onda desplaza media escala. Con la Velocity en el
    /// centro del rango, un accent al extremo barre prácticamente 1…127 sin
    /// recortar; con la Velocity por defecto —100— recorta arriba, y enseñar ese
    /// recorte es justo para lo que sirve el panel `velocity response` (FR12).
    ///
    /// **La división trunca hacia cero, que es lo que hace simétrico el signo.**
    /// Truncar hacia abajo separaría `+n` de `−n` en una unidad sobre la mitad
    /// de los Steps, y el criterio 4 pide que uno sea el complemento exacto del
    /// otro. Multiplicando antes de dividir, como
    /// `Sustain.gateNanoseconds(over:)`.
    ///
    /// El producto no puede desbordar: 100 · 100 · 63 son 630.000.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Calculates the velocity offset of one step of the turn.
    /// - Parameters:
    ///   - step: The step index within the turn; it wraps around it.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The offset in MIDI units, from −63 to 63.
    public func offset(atStep step: Int, of stepCount: Int) -> Int {
        guard accent.percent != 0 else { return 0 }
        let excursion = waveform.value(atStep: step, of: stepCount)
        return excursion * accent.percent * 63 / 10000
    }

    /// La velocity que se emite en el Step `step` de una vuelta de `stepCount`,
    /// partiendo de la del Cycle (FR6, FR7).
    ///
    /// **El acotado a 1…127 lo hace `Velocity.advanced(by:)`**, que ya existe y
    /// ya está cubierto: la modulación lo reutiliza en vez de escribir un
    /// segundo acotado que pudiera discrepar. El extremo inferior sigue
    /// excluyendo el 0 por la razón de siempre — un note-on con velocity 0 es un
    /// note-off, y para no sonar está Probability.
    ///
    /// **Con `accent` en 0 devuelve la base intacta**, sin pasar por la onda ni
    /// por el acotado. Es la no regresión de la rebanada, y es también lo que
    /// hace que el camino nuevo no cueste nada a quien no lo pide.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Calculates the velocity emitted at one step of the turn.
    /// - Parameters:
    ///   - step: The step index within the turn; it wraps around it.
    ///   - stepCount: How many steps the turn has.
    ///   - base: The velocity of the cycle.
    /// - Returns: A velocity clamped to `Velocity.validRange`.
    public func velocity(atStep step: Int, of stepCount: Int, from base: Velocity) -> Velocity {
        guard accent.percent != 0 else { return base }
        return base.advanced(by: offset(atStep: step, of: stepCount))
    }
}

extension Groove {

    /// El mismo Groove con la velocity que le toca a este Step de la vuelta.
    ///
    /// **Es el único punto donde la modulación se aplica**, y por eso vive aquí
    /// y no en el scheduler: `workflow.md` dice que si algo merece un test está
    /// donde se testea, y una velocity mal compuesta se oye como un acento que
    /// no está donde debería.
    ///
    /// **Solo toca la velocity.** Sustain, Probability, Timing y Delay salen
    /// intactos: la modulación cambia con cuánta fuerza suena un Step, no cuándo
    /// suena ni cuánto dura. Es lo que sostiene NFR3 —no mueve ningún instante,
    /// así que no hay jitter que medir—.
    ///
    /// **Con `accent` en 0 devuelve `self`**, sin construir nada: es el criterio
    /// 1 de la rebanada, y hace que el camino nuevo no cueste nada a quien no lo
    /// pide.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Applies the modulation to this groove's velocity at one step of the turn.
    /// - Parameters:
    ///   - modulation: The waveform and accent of the cycle.
    ///   - step: The step index within the turn.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The same groove with the velocity of that step.
    public func modulated(by modulation: Modulation, atStep step: Int, of stepCount: Int) -> Groove
    {
        guard modulation.accent.percent != 0 else { return self }
        return Groove(
            velocity: modulation.velocity(atStep: step, of: stepCount, from: velocity),
            sustain: sustain,
            probability: probability,
            timing: timing,
            delay: delay
        )
    }
}
