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

    /// Vía interna para valores que ya se han acotado al rango, como los que
    /// produce un giro de knob. Evita un `guard` inalcanzable en cada sitio de
    /// uso. Mismo idioma que `Division.init(unchecked:)`.
    init(unchecked count: Int) {
        self.count = count
    }
}

/// Número de Pulses repartidos sobre el anillo.
///
/// **No se valida contra un `Steps` concreto, a propósito.** Hasta la rebanada 1
/// su inicializador exigía el anillo y rechazaba cualquier valor mayor, para que
/// ningún sitio de uso tuviera que revalidar. Lo que aquella decisión no
/// anticipó es que el usuario giraría Steps: bajarlo por debajo de Pulses
/// destruía el valor, y `product-guidelines.md` lo prohíbe —«cambiar un
/// parámetro nunca destruye material: el pool tonal sobrevive a un cambio de
/// Scale reencuadrándose, no vaciándose».
///
/// Así que el valor que se guarda aquí es **la intención**, y el reparto usa lo
/// que quepa en el anillo. Es exactamente el criterio que `Rotate` ya seguía: la
/// resolución contra el anillo la hace quien conoce su tamaño.
///
/// Ver la desviación documentada en `spec.md` del track
/// `mvp-control-input_20260827`.
public struct Pulses: Equatable, Sendable {

    /// Rango admitido. Coincide con el de `Steps` porque no puede haber más
    /// Pulses que posiciones donde ponerlos, ni en el anillo más largo.
    public static let validRange = Steps.validRange

    public let count: Int

    /// Devuelve `nil` si el número de Pulses cae fuera de `validRange`.
    public init?(_ count: Int) {
        guard Self.validRange.contains(count) else { return nil }
        self.count = count
    }

    /// Vía interna para valores ya acotados. Ver `Steps.init(unchecked:)`.
    init(unchecked count: Int) {
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

    /// Pulses pretendidos: el valor del parámetro, que es lo que el knob mueve
    /// y lo que la pantalla muestra.
    public var pulses: Pulses { rhythm.pulses }

    /// Pulses que suenan: los que caben en el anillo actual.
    public var effectivePulses: Int { rhythm.effectivePulses }

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

extension Shape: CustomStringConvertible {

    /// Cómo se lee Shape en pantalla: `Steps 16 · Pulses 5 · Rotate 0 · Division 1/16`.
    ///
    /// El formato sale de `product-guidelines.md`: «Preciso, no conversacional.
    /// La app no explica ni acompaña: informa» y «Vocabulario de la Pre Spec, en
    /// inglés, sin traducir». Por eso los términos van en inglés aunque el resto
    /// de la documentación esté en castellano — son nombres de parámetro, no
    /// prosa.
    ///
    /// **No dice nada sobre la altura, y es deliberado.** La nota de esta
    /// rebanada es una constante provisional del camino MIDI; mostrarla
    /// sugeriría una nota fija por paso, que es justo lo que
    /// `product-guidelines.md` advierte que contradice el modelo de pool.
    ///
    /// Rotate se muestra con el valor del parámetro, no con el giro ya
    /// normalizado: es lo que el usuario ajustará cuando haya knobs.
    public var description: String {
        "Steps \(steps.count) · Pulses \(pulses.count) · Rotate \(rotate.amount) · Division \(division)"
    }
}

extension Shape {

    /// Devuelve el Shape resultante de desplazar un parámetro.
    ///
    /// Es lo que produce un giro de knob, expresado sin saber nada de MIDI: el
    /// motor recibe un desplazamiento con signo y decide qué significa para cada
    /// parámetro.
    ///
    /// **Cada parámetro se comporta según su naturaleza, no según una regla
    /// única:**
    ///
    /// - `steps` y `division` **se frenan** en sus extremos. Son escalas con
    ///   principio y fin; envolver convertiría un ajuste fino en un salto
    ///   brutal, y `product-guidelines.md` pide que girar produzca «siempre un
    ///   cambio inmediato y proporcional».
    /// - `rotate` **envuelve**, porque es un giro sobre un anillo cerrado:
    ///   pasarse del último Step y aparecer en el primero es el comportamiento
    ///   correcto. Se normaliza dentro del anillo para que el valor que se
    ///   muestra siga significando algo tras muchos giros.
    /// - `pulses` se frena en **su propio rango**, no en Steps. Frenarlo antes
    ///   sería el acotado destructivo que este track eliminó: el valor guardado
    ///   es la intención y `effectivePulses` es lo que suena.
    ///
    /// No es código de tiempo real: construir un Shape reparte los Pulses, y eso
    /// asigna. Se llama desde el hilo de control, al recibir un giro.
    public func applying(_ delta: Int, to parameter: ShapeParameter) -> Shape {
        switch parameter {
        case .steps:
            let clamped = min(max(steps.count + delta, Steps.validRange.lowerBound), Steps.validRange.upperBound)
            return Shape(
                steps: Steps(unchecked: clamped), pulses: pulses, rotate: rotate, division: division
            )

        case .pulses:
            let clamped = min(max(pulses.count + delta, Pulses.validRange.lowerBound), Pulses.validRange.upperBound)
            return Shape(
                steps: steps, pulses: Pulses(unchecked: clamped), rotate: rotate, division: division
            )

        case .rotate:
            // El resto puede ser negativo, así que se lleva al anillo antes de
            // guardarlo: `Rotate` admite cualquier entero, pero un valor
            // normalizado es el único que se puede mostrar sin confundir.
            let remainder = (rotate.amount + delta) % steps.count
            let wrapped = remainder < 0 ? remainder + steps.count : remainder
            return Shape(steps: steps, pulses: pulses, rotate: Rotate(wrapped), division: division)

        case .division:
            return Shape(steps: steps, pulses: pulses, rotate: rotate, division: division.advanced(by: delta))
        }
    }
}
