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
