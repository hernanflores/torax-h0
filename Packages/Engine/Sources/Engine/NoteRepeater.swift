/// Cuántos triggers extra genera cada Pulse.
///
/// Término de la Pre Spec. El Pulse original **no** cuenta: con Repeats en 3
/// suenan cuatro eventos, el Pulse en su instante y tres repeticiones detrás.
///
/// **0–8, y la Pre Spec dice «0–48; máximo clockwise = infinito».** La
/// desviación está fechada el 2026-09-07 en `Pre Spec Torax H-0.md` y su razón
/// es el techo de coste en el hilo del scheduler: con doce Tracks, ocho
/// repeticiones son 108 eventos por Step como peor caso, contra los 588 de 48.
/// La medición de jitter está suspendida desde el 2026-09-02, así que el techo
/// se **razona** en vez de medirse, y razonar sobre 108 es defendible donde
/// sobre 588 no lo es. Ampliarlo después es cambiar esta constante y volver a
/// mirar el techo.
///
/// **El cero es el default y no un extremo incómodo**: es lo que hace que la
/// rebanada no cambie nada de lo entregado.
///
/// Valida en el inicializador, como `Velocity` y `Steps`.
public struct Repeats: Equatable, Sendable {

    /// Rango admitido. El extremo superior es la desviación documentada.
    public static let validRange: ClosedRange<Int> = 0...8

    /// Default del producto: ninguna repetición. Con él, la salida es la de
    /// antes de la rebanada — instantes, velocities, gates y consumo de
    /// aleatoriedad.
    public static let `default` = Repeats(unchecked: 0)

    public let count: Int

    /// Devuelve `nil` si la cuenta cae fuera de `validRange`.
    public init?(_ count: Int) {
        guard Self.validRange.contains(count) else { return nil }
        self.count = count
    }

    /// Vía interna para valores ya acotados, como los que produce un giro de
    /// knob. Ver `Velocity.init(unchecked:)`.
    init(unchecked count: Int) {
        self.count = count
    }
}

/// Separación entre repeticiones, como valor de nota.
///
/// Término de la Pre Spec: «Time — separación entre repeticiones». El tipo se
/// llama `RepeatTime` y no `Time` por desambiguación de Swift, no por
/// vocabulario: `Time` a secas colisiona con el vocabulario temporal del motor
/// —`MusicalTime`, `MusicalTimeline`—. **Lo que el usuario lee sigue siendo
/// `Time`.**
///
/// **Valor de nota absoluto, no fracción del Step.** Un Track en 1/4 y otro en
/// 1/16 con el mismo Time repiten al mismo ritmo, que es lo que «expresado como
/// valor de nota» significa. Quien calcula el hueco lo hace como múltiplo de la
/// duración del Step —`hueco = duraciónDelStep × (Time / Division)`— para no
/// inventar una vía nueva al tempo.
///
/// **Envuelve una `Division` y no amplía `Division.ordered`.** La lista de Time
/// es suya: mete tresillos, y meterlos en la de Division cambiaría por dónde
/// pasa otro knob.
public struct RepeatTime: Equatable, Sendable {

    /// La fracción de redonda que separa una repetición de la siguiente.
    public let fraction: Division

    /// Devuelve `nil` si numerador o denominador no son positivos, con el mismo
    /// criterio que `Division`.
    public init?(numerator: Int, denominator: Int) {
        guard let fraction = Division(numerator: numerator, denominator: denominator) else {
            return nil
        }
        self.fraction = fraction
    }

    /// Vía interna para las constantes de abajo, cuyos valores son literales
    /// conocidos. Ver `Division.init(unchecked:denominator:)`.
    init(unchecked denominator: Int) {
        self.fraction = Division(unchecked: 1, denominator: denominator)
    }

    /// Los valores por los que recorre el knob, **de más lenta a más rápida**:
    /// nueve posiciones, los rectos y sus tresillos.
    ///
    /// Alterna recto y tresillo —1/8, 1/12, 1/16, 1/24…— así que un clic pasa de
    /// binario a ternario y dos clics duplican la velocidad de la tirada. Es la
    /// misma lectura que `Division.ordered` ofrece con los rectos solos.
    public static let ordered: [RepeatTime] = [
        RepeatTime(unchecked: 8),
        RepeatTime(unchecked: 12),
        RepeatTime(unchecked: 16),
        RepeatTime(unchecked: 24),
        RepeatTime(unchecked: 32),
        RepeatTime(unchecked: 48),
        RepeatTime(unchecked: 64),
        RepeatTime(unchecked: 96),
        RepeatTime(unchecked: 128),
    ]

    /// Default del producto: 1/32. Cae en mitad de la lista, con margen a los
    /// dos lados para que el primer giro del knob se oiga en cualquier sentido.
    public static let `default` = RepeatTime(unchecked: 32)

    /// Devuelve la Time que está `delta` posiciones más adelante en la lista;
    /// hacia delante es más rápida.
    ///
    /// **Se detiene en los extremos, no envuelve**, y una Time que no esté en la
    /// lista se devuelve intacta: es literalmente el criterio de
    /// `Division.advanced(by:)`, y por la misma razón — el recorrido no puede
    /// inventar un punto de partida que no existe.
    public func advanced(by delta: Int) -> RepeatTime {
        guard let index = Self.ordered.firstIndex(of: self) else { return self }
        let target = min(max(index + delta, 0), Self.ordered.count - 1)
        return Self.ordered[target]
    }
}

/// Curva de velocity a través de las repeticiones.
///
/// Término de la Pre Spec: «curva ascendente/descendente de velocity a través de
/// las repeticiones», y «relativo a la Velocity general del Track» — mover el
/// knob de VELOCITY mueve la rampa entera con él.
///
/// **Bipolar y simétrico, como `Delay`**: el cero es el centro y el knob lo cruza
/// sin caso especial. Positivo sube hacia 127; negativo baja hacia **1 y no
/// hacia 0**, porque velocity 0 es note-off en MIDI 1.0 y una rampa no debe
/// poder emitir un apagado disfrazado de nota — la misma razón por la que
/// `Velocity` excluye el cero.
///
/// **El Pulse original queda fuera de la rampa**: suena siempre a la Velocity
/// del Track. La curva recorre solo las repeticiones.
public struct Ramp: Equatable, Sendable {

    /// Rango admitido. Simétrico: la curva entera hacia cada lado.
    public static let validRange: ClosedRange<Int> = -100...100

    /// Default del producto: sin curva. Todas las repeticiones suenan a la
    /// Velocity del Track.
    public static let `default` = Ramp(unchecked: 0)

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

/// Cambio del espaciado a lo largo de la tirada.
///
/// Término de la Pre Spec: «acelera o frena gradualmente la separación entre
/// repeticiones».
///
/// **Bipolar y simétrico, como `Ramp` y `Delay`.** El factor que sale de aquí es
/// exactamente recíproco entre `+p` y `−p` —+50 da ×1,5 y −50 da ÷1,5— y es
/// aritmética racional, sin exponenciales en el camino de tiempo real.
///
/// **Pace cambia cuánto dura la tirada**, así que interactúa con el corte: un
/// Pace positivo alto entrega menos repeticiones de las pedidas, porque el Pulse
/// siguiente llega antes de que quepan todas. Es visible y deliberado.
public struct Pace: Equatable, Sendable {

    /// Rango admitido. Simétrico: el último hueco llega a durar el doble o la
    /// mitad del primero.
    public static let validRange: ClosedRange<Int> = -100...100

    /// Default del producto: espaciado recto. Todos los huecos valen Time.
    public static let `default` = Pace(unchecked: 0)

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

extension Repeats {

    /// Cuenta resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Es el criterio de `Steps`,
    /// `Division` y `Velocity`: envolver convertiría un giro de más en pasar de
    /// ocho repeticiones a ninguna, que es lo contrario del «cambio inmediato y
    /// proporcional» que pide `product-guidelines.md`.
    ///
    /// Adjusts the repeat count by the specified amount within its valid range.
    /// - Parameter delta: The amount to add to the repeat count.
    /// - Returns: A count clamped between 0 and 8.
    public func advanced(by delta: Int) -> Repeats {
        Repeats(unchecked: Self.validRange.clamping(count + delta))
    }
}

extension Ramp {

    /// Curva resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Ver `Repeats.advanced(by:)`.
    ///
    /// Adjusts the ramp percentage by the specified amount within its valid range.
    /// - Parameter delta: The amount to add to the ramp percentage.
    /// - Returns: A percentage clamped between −100 and 100.
    public func advanced(by delta: Int) -> Ramp {
        Ramp(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension Pace {

    /// Espaciado resultante de desplazar el knob `delta` posiciones.
    ///
    /// **Se frena en los extremos, no envuelve.** Ver `Repeats.advanced(by:)`.
    ///
    /// Adjusts the pace percentage by the specified amount within its valid range.
    /// - Parameter delta: The amount to add to the pace percentage.
    /// - Returns: A percentage clamped between −100 and 100.
    public func advanced(by delta: Int) -> Pace {
        Pace(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension RepeatTime: CustomStringConvertible {

    /// Se lee como la fracción que es: `1/32`. Mismo criterio que `Division`.
    public var description: String { fraction.description }
}

extension Ramp {

    /// Velocity de la repetición `k` de una tirada de `n`.
    ///
    /// **El Pulse original es `k = 0` y devuelve la Velocity del Track intacta**,
    /// en los dos sentidos: la curva recorre solo las repeticiones, que van de 1
    /// a `n`. Es lo que hace que con Repeats en 0 no cambie nada de lo entregado.
    ///
    /// La curva es la de la Pre Spec, «relativo a la Velocity general del
    /// Track»: mover el knob de VELOCITY mueve la rampa entera con él.
    ///
    /// ```
    /// objetivo = ramp > 0 ? 127 : 1
    /// v(k) = V + (objetivo − V) × (|ramp| / 100) × (k / n)
    /// ```
    ///
    /// **Con Ramp negativo el objetivo es 1 y no 0.** Velocity 0 es note-off en
    /// MIDI 1.0, así que una rampa que llegara a cero emitiría un apagado
    /// disfrazado de nota — la misma razón por la que `Velocity` excluye el cero.
    ///
    /// Aritmética entera y multiplicando antes de dividir, como
    /// `Sustain.gateNanoseconds(forStep:)`: esto acaba corriendo en el hilo del
    /// scheduler. La división trunca hacia cero, así que el redondeo acerca la
    /// curva a la Velocity del Track por menos de una unidad — inaudible, y
    /// simétrico entre subir y bajar.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    ///
    /// Calculates the velocity of one repetition along the ramp.
    /// - Parameters:
    ///   - k: The repetition index, from 1 to `n`; 0 is the originating pulse.
    ///   - n: How many repetitions the burst has.
    ///   - base: The velocity of the track.
    /// - Returns: A velocity clamped to `Velocity.validRange`.
    public func velocity(forRepetition k: Int, of n: Int, from base: Velocity) -> Velocity {
        guard k > 0, n > 0, percent != 0 else { return base }
        let target = percent > 0 ? Velocity.validRange.upperBound : Velocity.validRange.lowerBound
        let travel = (target - base.value) * abs(percent) * k / (100 * n)
        return Velocity(unchecked: Velocity.validRange.clamping(base.value + travel))
    }
}

extension RepeatTime {

    /// Hueco entre dos repeticiones, en nanosegundos, dado lo que dura un Step.
    ///
    /// **Múltiplo de la duración del Step y no una vuelta al tempo:**
    /// `hueco = duraciónDelStep × (Time / Division)`. La duración del Step ya
    /// está calculada donde esto se usa, y hacerlo así hereda —sin inventar una
    /// vía nueva— la rejilla que la `MusicalTimeline` fija al pulsar Play.
    ///
    /// Es lo que hace que Time sea un **valor de nota absoluto**: un Track en 1/4
    /// y otro en 1/16 con el mismo Time repiten al mismo ritmo, porque la
    /// Division entra dividiendo y sale del resultado.
    ///
    /// Entera y multiplicando antes de dividir, como
    /// `Sustain.gateNanoseconds(forStep:)`.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    ///
    /// Calculates the spacing between two repetitions.
    /// - Parameters:
    ///   - stepDurationNanoseconds: How long one step lasts.
    ///   - division: The division of the track the repetitions belong to.
    /// - Returns: The gap in nanoseconds.
    public func gapNanoseconds(forStep stepDurationNanoseconds: Int64, division: Division) -> Int64
    {
        stepDurationNanoseconds * Int64(fraction.numerator) * Int64(division.denominator)
            / (Int64(fraction.denominator) * Int64(division.numerator))
    }
}

extension Pace {

    /// Hueco de la repetición `i` de una tirada de `n`, estirando o encogiendo
    /// el hueco que Time mide.
    ///
    /// ```
    /// r = pace ≥ 0 ? (100 + pace) / 100 : 100 / (100 − pace)
    /// hueco(i) = Time × (1 + (r − 1) × (i − 1) / (n − 1))     con n > 1
    /// hueco(1) = Time                                         con n = 1
    /// ```
    ///
    /// **`r` es exactamente recíproco entre `+p` y `−p`** —+50 da ×1,5 y −50 da
    /// ÷1,5—, y por eso se calcula como fracción y no con una exponencial:
    /// girar el knob a un lado y al otro la misma cantidad es el mismo gesto, y
    /// no hay coma flotante en el camino de tiempo real.
    ///
    /// **El primer hueco vale siempre Time.** La curva arranca donde Time dice y
    /// se separa después, así que subir Pace no desplaza la primera repetición.
    ///
    /// **Con `n = 1` el hueco es Time**, sea cual sea Pace: la interpolación
    /// divide por `n − 1` y con una sola repetición no hay tirada que recorrer.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    ///
    /// Calculates the spacing of one repetition along the pace curve.
    /// - Parameters:
    ///   - i: The repetition index, from 1 to `n`.
    ///   - n: How many repetitions the burst has.
    ///   - base: The gap that Time measures, in nanoseconds.
    /// - Returns: The gap in nanoseconds.
    public func gapNanoseconds(forRepetition i: Int, of n: Int, base: Int64) -> Int64 {
        guard n > 1, percent != 0 else { return base }
        let numerator = percent > 0 ? Int64(100 + percent) : 100
        let denominator = percent > 0 ? 100 : Int64(100 - percent)
        let span = Int64(n - 1)
        return base * (span * denominator + (numerator - denominator) * Int64(i - 1))
            / (denominator * span)
    }
}
