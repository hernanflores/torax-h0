/// Reparto euclidiano de Pulses sobre un anillo de Steps.
///
/// **El criterio viene de la Pre Spec:** «el H-0 reparte los Pulses lo más
/// uniformemente posible entre los Steps». El algoritmo que esa frase nombra es
/// el de Bjorklund, que es el que se implementa aquí. La Pre Spec ilustra el
/// resultado con tres casos —16/4 «muy regular», 16/5 «equilibrio con
/// asimetría», 12/7 «más denso»— pero no escribe los patrones, así que los
/// tests de `EuclideanRhythmTests` son el registro canónico del proyecto.
///
/// **Por qué una máscara de bits.** El patrón se calcula una sola vez, al
/// construir el valor, y se guarda en un `UInt16`. Consultarlo es entonces un
/// desplazamiento y una comparación: sin array que recorrer y sin nada que
/// asignar, que es lo que exige el camino del scheduler
/// (`conductor/code_styleguides/swift.md`).
///
/// Que quepa en 16 bits no es casualidad ni una optimización arriesgada: `Steps`
/// está acotado a 1–16 en v1, así que el tipo del almacén y el rango del dominio
/// son la misma decisión. Si Steps creciera a los 64 de la Pre Spec, esto pasa a
/// `UInt64` y nada más cambia.
public struct EuclideanRhythm: Equatable, Sendable {

    public let steps: Steps

    /// Pulses **pretendidos**: lo que el usuario pidió.
    ///
    /// Puede exceder el número de Steps. Lo que suena es `effectivePulses`.
    public let pulses: Pulses

    public let rotate: Rotate

    /// Pulses que realmente se reparten sobre el anillo: los que caben.
    ///
    /// Es `min(pulses, steps)`. La diferencia entre este valor y `pulses` es
    /// justo lo que se recupera al volver a subir Steps.
    public var effectivePulses: Int { min(pulses.count, steps.count) }

    /// Un bit por Step: el bit *i* está a uno si el Step *i* dispara.
    ///
    /// Guarda el patrón **ya girado**. Rotate es una permutación del anillo, no
    /// una consulta distinta: aplicarlo una vez aquí deja `triggers(atStep:)`
    /// como un único desplazamiento de bits, que es lo que el camino del
    /// scheduler necesita.
    let pattern: UInt16

    /// Reparte los Pulses sobre el anillo y lo gira.
    ///
    /// **Si se piden más Pulses de los que hay Steps, se reparten los que
    /// caben.** El valor de `pulses` es la intención del usuario y se conserva
    /// tal cual; lo que se acota es el reparto. Así, bajar Steps y volver a
    /// subirlo devuelve el patrón original en vez de haber perdido el valor.
    ///
    /// **No es código de tiempo real:** el reparto asigna memoria. Se construye
    /// en el hilo principal, al publicar un snapshot, nunca dentro del bucle del
    /// scheduler.
    public init(steps: Steps, pulses: Pulses, rotate: Rotate = .none) {
        self.steps = steps
        self.pulses = pulses
        self.rotate = rotate
        self.pattern = Self.rotate(
            Self.distribute(pulses: min(pulses.count, steps.count), over: steps.count),
            by: rotate.amount,
            over: steps.count
        )
    }

    /// Indica si el Step dado dispara.
    ///
    /// El índice **envuelve sobre el anillo**: el scheduler cuenta Steps hacia
    /// arriba sin parar y nunca vuelve a cero, así que acotar el índice aquí
    /// evita que cada sitio de uso tenga que hacerlo. Los índices negativos
    /// también envuelven, porque `MusicalTimeline` ya los admite para Delay.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func triggers(atStep index: Int) -> Bool {
        let remainder = index % steps.count
        let position = remainder < 0 ? remainder + steps.count : remainder
        return (pattern >> UInt16(position)) & 1 == 1
    }

    /// Cuántos Pulses dispararon antes que el Step dado.
    ///
    /// **Sin estado y sin acumular.** Es la misma disciplina que
    /// `MusicalTimeline`: el offset de un Step se calcula multiplicando su
    /// índice, nunca sumando paso a paso. Un contador de Pulses que avanzara
    /// solo derivaría en cuanto se descartara una lectura del snapshot o se
    /// reiniciara el transporte, y esa deriva no se vería hasta oírla.
    ///
    /// **Sigue contando al dar la vuelta.** El anillo se cierra pero los Pulses
    /// no vuelven a empezar: que la vuelta siguiente continúe el arpegio en vez
    /// de reiniciarlo es lo que hace que un pool de tres notas sobre un anillo
    /// de ocho no repita siempre la misma altura en la misma posición.
    ///
    /// El índice se descompone en vueltas completas más el resto, así que el
    /// coste es constante aunque el Step esté muy lejos del origen.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func pulseOrdinal(atStep index: Int) -> Int {
        let count = steps.count
        let remainder = index % count
        let position = remainder < 0 ? remainder + count : remainder
        let laps = (index - position) / count

        // Bits encendidos por debajo de la posición: los Pulses de esta vuelta
        // que ya dispararon. `nonzeroBitCount` es una instrucción.
        let mask: UInt16 = position == 0 ? 0 : (1 << UInt16(position)) - 1
        return laps * effectivePulses + (pattern & mask).nonzeroBitCount
    }

    /// Algoritmo de Bjorklund.
    ///
    /// Reparte los Pulses emparejando repetidamente grupos «con trigger» y
    /// grupos «sin trigger», igual que el algoritmo de Euclides empareja restos.
    /// El resultado es el patrón máximamente uniforme, y siempre empieza en un
    /// Pulse: el punto de entrada del anillo lo desplaza Rotate, no el reparto.
    private static func distribute(pulses: Int, over steps: Int) -> UInt16 {
        var triggered: [[Bool]] = Array(repeating: [true], count: pulses)
        var rest: [[Bool]] = Array(repeating: [false], count: steps - pulses)

        while rest.count > 1 {
            let pairs = min(triggered.count, rest.count)
            let merged = (0..<pairs).map { triggered[$0] + rest[$0] }
            rest = Array(triggered[pairs...]) + Array(rest[pairs...])
            triggered = merged
            if triggered.count <= 1 { break }
        }

        return (triggered + rest)
            .flatMap { $0 }
            .enumerated()
            .reduce(into: UInt16(0)) { mask, entry in
                if entry.element { mask |= 1 << UInt16(entry.offset) }
            }
    }

    /// Gira la máscara sobre el anillo.
    ///
    /// Es una rotación circular de bits acotada al ancho del anillo, no al de
    /// `UInt16`: los bits por encima de `steps` no forman parte del anillo y no
    /// pueden recibir el desbordamiento. Por eso se enmascara al final.
    ///
    /// El giro se normaliza antes: un Rotate mayor que Steps da la vuelta, y uno
    /// negativo gira en sentido contrario. Ambos son musicalmente
    /// significativos, así que `Rotate` no los rechaza y es aquí —donde se
    /// conoce el tamaño del anillo— donde se envuelven.
    private static func rotate(_ pattern: UInt16, by amount: Int, over steps: Int) -> UInt16 {
        let remainder = amount % steps
        let shift = UInt16(remainder < 0 ? remainder + steps : remainder)
        guard shift > 0 else { return pattern }

        let ringMask: UInt16 = steps >= 16 ? .max : (1 << UInt16(steps)) - 1
        return ((pattern << shift) | (pattern >> (UInt16(steps) - shift))) & ringMask
    }
}
