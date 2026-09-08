/// Lo que se armó, esperando a que el scheduler diga que lo adoptó.
///
/// **El scheduler no conoce índices** (FR8). Con el transporte corriendo, el
/// material entra en el límite de compás dentro del hilo del scheduler, que solo
/// sabe de Patterns y publica una palabra atómica —`PatternHandoff.adoptionCount`—
/// diciendo que adoptó. Quién armó qué hueco lo recuerda este lado, que es quien
/// tiene los índices de Bank y de Pattern.
///
/// **Vive en `MIDI` y no en `App` porque `App` no se mide** (`workflow.md`,
/// NFR3). Lo de arriba es una decisión con casos límite —armar dos veces, armar
/// encima de algo que ya aterrizó, un contador que ya venía movido— y una
/// decisión sin tests estaría en el sitio equivocado.
///
/// **Se consulta al dibujar, no por callback** (FR9), con el mismo criterio que
/// `playhead` y `cycleInCourse`: publicar hacia el modelo sería trabajo en el
/// camino de tiempo real. Lo que suena entra exacto en el compás; lo que la
/// pantalla y el `Project` reflejan puede llegar hasta un cuadro después, y
/// nadie lo oye.
public final class PendingAdoption {

    /// Qué hueco espera al compás, si alguno.
    ///
    /// **Lo consume la pantalla**: es lo que pinta el hueco como `queued` y lo
    /// que sostiene la cuenta atrás. Que se vacíe al aterrizar es la mitad de
    /// FR10.
    public private(set) var armedPatternIndex: Int?

    /// El contador de adopciones que había cuando se armó. Lo que dispara es que
    /// se mueva **después** de eso.
    private var armedAtCount: UInt64 = 0

    /// Un hueco que ya aterrizó y que nadie ha leído todavía.
    ///
    /// Solo se llena en el caso de armar encima de una adopción sin haber
    /// mirado en medio: hace falta pulsar dos Patterns dentro del mismo cuadro a
    /// caballo de un límite de compás. Se guarda en vez de descartarse porque lo
    /// que suena es el que aterrizó, y dar el otro pondría la pantalla y el knob
    /// en un hueco que todavía no suena.
    private var landedButUnread: Int?

    public init() {}

    /// Recuerda qué hueco acaba de armarse.
    ///
    /// Armar dos veces antes del compás deja el último, igual que la ranura del
    /// `PatternHandoff`: cambiar de idea antes del límite es normal en directo.
    /// - Parameters:
    ///   - patternIndex: el hueco del Bank vigente que espera al compás.
    ///   - adoptionCount: el valor del contador ahora mismo.
    public func arm(_ patternIndex: Int, adoptionCount: UInt64) {
        if let armed = armedPatternIndex, adoptionCount > armedAtCount {
            landedButUnread = armed
        }
        armedPatternIndex = patternIndex
        armedAtCount = adoptionCount
    }

    /// Olvida lo armado sin aplicarlo.
    ///
    /// La usa el camino parado, donde el material entra en el acto y no puede
    /// quedar nada esperando detrás.
    public func cancel() {
        armedPatternIndex = nil
        landedButUnread = nil
    }

    /// Qué hueco hay que aplicar, si el contador se movió desde que se armó.
    ///
    /// Devuelve `nil` en el caso de casi todos los cuadros: sin nada pendiente,
    /// leer el contador no cambia nada. Cuando devuelve un índice, el modelo
    /// mueve `project.selectedPattern` ahí, deja de haber nada armado y
    /// `ControlInput` adopta el material de ese hueco — la consecuencia que
    /// destruía trabajo (FR10).
    /// - Parameter adoptionCount: el valor del contador ahora mismo.
    /// - Returns: el hueco que acaba de empezar a sonar, o `nil`.
    public func landed(adoptionCount: UInt64) -> Int? {
        if let unread = landedButUnread {
            landedButUnread = nil
            return unread
        }
        guard let armed = armedPatternIndex, adoptionCount > armedAtCount else { return nil }
        armedPatternIndex = nil
        return armed
    }
}
