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
    public let pulses: Pulses

    /// Un bit por Step: el bit *i* está a uno si el Step *i* dispara.
    private let pattern: UInt16

    /// Reparte los Pulses sobre el anillo.
    ///
    /// **No es código de tiempo real:** el reparto asigna memoria. Se construye
    /// en el hilo principal, al publicar un snapshot, nunca dentro del bucle del
    /// scheduler.
    public init(steps: Steps, pulses: Pulses) {
        self.steps = steps
        self.pulses = pulses
        self.pattern = Self.distribute(pulses: pulses.count, over: steps.count)
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
}
