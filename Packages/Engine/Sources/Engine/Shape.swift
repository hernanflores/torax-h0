/// Número de Steps del anillo.
///
/// La Pre Spec describe un rango 1–64, pero v1 se acota a **1–16**: es lo que
/// cabe en el anillo con legibilidad a un metro, que es el criterio de
/// `product-guidelines.md`. El rango largo llega cuando exista una
/// representación que lo aguante.
///
/// Valida en el inicializador, como `Tempo` y `Division`: un `Steps` que existe
/// es siempre válido, y ningún sitio de uso vuelve a comprobarlo.
public struct Steps: Equatable, Sendable {

    /// Rango admitido en v1.
    public static let validRange: ClosedRange<Int> = 1...16

    public let count: Int

    /// Devuelve `nil` si el número de Steps cae fuera de `validRange`.
    public init?(_ count: Int) {
        guard Self.validRange.contains(count) else { return nil }
        self.count = count
    }
}

/// Número de Pulses repartidos sobre el anillo.
///
/// Su límite superior no es una constante: es el `Steps` en el que vive. Por eso
/// el inicializador exige el anillo, en lugar de aceptar un entero suelto que
/// alguien tendría que validar más tarde contra el Track.
public struct Pulses: Equatable, Sendable {

    public let count: Int

    /// Devuelve `nil` si el número de Pulses cae fuera de `1...steps.count`.
    public init?(_ count: Int, in steps: Steps) {
        guard (1...steps.count).contains(count) else { return nil }
        self.count = count
    }
}

/// Desplazamiento del patrón sobre el anillo.
///
/// **No se valida contra un rango a propósito.** Rotate es un giro sobre un
/// anillo cerrado: un valor negativo gira en sentido contrario y un valor mayor
/// que Steps da la vuelta. Ambos son musicalmente significativos, así que
/// rechazarlos obligaría a quien llama a normalizar antes — justo el reparto de
/// responsabilidad que el tipo existe para evitar. La envoltura la resuelve el
/// reparto, que es quien conoce el tamaño del anillo.
public struct Rotate: Equatable, Sendable {

    public let amount: Int

    public init(_ amount: Int) {
        self.amount = amount
    }

    /// Patrón sin girar. Es el valor por defecto del producto.
    public static let none = Rotate(0)
}

/// Shape — la familia que decide **cuándo** ocurren los eventos.
///
/// La Pre Spec la sitúa primera en el flujo del motor: «Shape decide *cuándo* y
/// con qué densidad ocurren eventos», antes de que Tonal elija alturas y Groove
/// las interprete. Sus cuatro parámetros en esta rebanada son Steps, Pulses,
/// Rotate y Division; el resto de la tabla de la Pre Spec —Repeats, Time,
/// Voicing, Range, Cycles— llega en tracks posteriores.
///
/// Es un valor inmutable y `Sendable` a propósito: es lo que cruza al hilo del
/// scheduler como snapshot, y por eso no hay ningún lock que tomar en el camino
/// de timing (`conductor/code_styleguides/swift.md`).
public struct Shape: Equatable, Sendable {

    /// Valor rítmico de cada Step. Default del producto: 1/16.
    public let division: Division

    /// El anillo ya repartido y girado. Privado porque Shape es la fachada que
    /// el resto del motor usa; el reparto es su mecanismo, no su interfaz.
    private let rhythm: EuclideanRhythm

    public var steps: Steps { rhythm.steps }
    public var pulses: Pulses { rhythm.pulses }
    public var rotate: Rotate { rhythm.rotate }

    /// **No es código de tiempo real:** construir un Shape reparte los Pulses, y
    /// eso asigna memoria. Se hace en el hilo principal al publicar un snapshot.
    public init(
        steps: Steps,
        pulses: Pulses,
        rotate: Rotate = .none,
        division: Division = .sixteenth
    ) {
        self.division = division
        self.rhythm = EuclideanRhythm(steps: steps, pulses: pulses, rotate: rotate)
    }

    /// Indica si el Step dado dispara. El índice envuelve sobre el anillo.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func triggers(atStep index: Int) -> Bool {
        rhythm.triggers(atStep: index)
    }
}

/// Track — «una voz/carril musical y de control».
///
/// La Pre Spec lo define como el sitio donde residen los parámetros
/// generativos. En esta rebanada solo tiene Shape: Tonal y Groove están fuera de
/// alcance, y con ellos el pool de alturas. **Que el Track no diga nada sobre la
/// altura es deliberado**: `product-guidelines.md` advierte contra consolidar la
/// idea de una nota fija por paso, que contradice el modelo de pool. La altura
/// provisional de esta rebanada es una constante del camino MIDI, no estado del
/// Track.
public struct Track: Equatable, Sendable {

    public let shape: Shape

    public init(shape: Shape) {
        self.shape = shape
    }

    /// Indica si el Step dado dispara, combinando Shape y Rotate.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func triggers(atStep index: Int) -> Bool {
        shape.triggers(atStep: index)
    }
}
