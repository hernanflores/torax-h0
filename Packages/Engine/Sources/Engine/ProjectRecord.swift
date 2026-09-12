/// El árbol tal y como se escribe en disco.
///
/// **Estos tipos son el formato, y los de al lado son la memoria.** `Cycle`,
/// `Track` y `Pattern` son POD con almacenamiento inline —tuplas, y el pool de
/// ocho alturas empaquetado en los bits de un `UInt64`— porque se copian dentro
/// del hilo del scheduler, y `_isPOD` lo vigila. Esa disposición está elegida
/// por una exigencia de tiempo real, **no por ser un buen formato de fichero**.
///
/// Un `Codable` sintetizado sobre ellos ataría el JSON a esa disposición: mover
/// un campo por razones de scheduler rompería los ficheros ya guardados. Por eso
/// hay una capa espejo con claves escritas a mano, y por eso
/// `RecordRoundTripTests` compara el JSON contra literales en vez de contra sí
/// mismo.
///
/// **`Codable` es stdlib**, así que esto no viola la regla de que `Engine` no
/// importe nada más — `DependencyBoundaryTests` la vigila. Lo que no está aquí
/// es el `JSONEncoder`, que es Foundation y vive en `Persistence`.
///
/// **Añadir un parámetro al `Cycle` tiene que romper un test.** Las rebanadas 5
/// y 6 —Note Repeater y Modulation— añaden campos, y el test que enumera las
/// claves esperadas es lo que impide que uno se pierda en silencio.

// MARK: - Cycle

/// Un `Cycle` en disco: veintiuna claves planas.
///
/// **Eran quince hasta el 2026-09-07**, cuando los cuatro del Note Repeater se
/// sumaron, y diecinueve hasta el 2026-09-08, cuando llegaron las dos de la
/// modulación.
///
/// **Plano y no anidado**, aunque `Shape`, `Groove` y `TonalFrame` sean tipos
/// propios. Un Cycle son quince números y una cadena; anidarlos en tres objetos
/// añadiría tres niveles de llaves a un fichero que se quiere leer con los ojos,
/// sin ganar nada: no hay ningún sitio donde se necesite medio Cycle.
public struct CycleRecord: Codable, Equatable, Sendable {

    public let steps: Int
    public let pulses: Int
    public let rotate: Int
    public let divisionNumerator: Int
    public let divisionDenominator: Int

    /// Las alturas, en orden. **Se guardan como números y no como el `UInt64`
    /// que las empaqueta**: ese entero es la disposición en memoria, y guardarlo
    /// ataría el fichero a ella.
    public let pool: [Int]

    public let velocity: Int
    public let sustain: Int
    public let probability: Int
    public let timing: Int
    public let delay: Int
    public let channel: Int

    /// La escala, por una clave estable en minúsculas.
    ///
    /// **No es `Scale.name`.** Aquel es lo que enseña la pantalla —`"Minor"`— y
    /// atar el fichero a él haría que capitalizar un título rompiera ficheros
    /// guardados. Son dos vocabularios distintos: uno se lee, otro se guarda.
    public let scale: String

    public let root: Int
    public let padOctaveShift: Int

    /// Los cuatro del Note Repeater, desde el 2026-09-07.
    ///
    /// **Opcionales, y es lo único que hace legible un Bank de antes de la
    /// rebanada.** Un fichero escrito sin estas claves las decodifica como `nil`
    /// y se lee como el neutro —Repeats 0, Time 1/32, Ramp 0, Pace 0—, que es
    /// exactamente el estado que ese fichero describía. La alternativa era subir
    /// `schemaVersion`, y `ProjectRecord.validated()` exige igualdad exacta: sin
    /// migrador, eso dejaría sin abrir los Banks ya guardados.
    ///
    /// **Se escriben siempre**, también el neutro: un `0` explícito dice «sin
    /// repeticiones», mientras que una clave ausente solo dice «esto lo escribió
    /// otra versión».
    ///
    /// **Time se guarda por su denominador y no por su posición en la lista.**
    /// El índice es la disposición del knob y ataría el fichero a ella: insertar
    /// una fracción en `RepeatTime.ordered` movería lo que suena un Bank ya
    /// guardado. `128` seguirá siendo 1/128.
    public let repeats: Int?
    public let repeatTimeDenominator: Int?
    public let ramp: Int?
    public let pace: Int?

    /// Las dos de la modulación, desde el 2026-09-08.
    ///
    /// **Opcionales por la misma razón que las cuatro de arriba**: un fichero
    /// escrito sin ellas las decodifica como `nil` y se lee como el neutro
    /// —`triangle` y accent 0—, que es exactamente el estado que ese fichero
    /// describía. `schemaVersion` se queda en 1 porque
    /// `ProjectRecord.validated()` exige igualdad exacta, y sin migrador subirla
    /// dejaría sin abrir los Banks ya guardados.
    ///
    /// **Se escriben siempre**, también el neutro: un `0` explícito dice «sin
    /// modulación», mientras que una clave ausente solo dice «esto lo escribió
    /// otra versión».
    ///
    /// **`waveform` se guarda por una clave estable en minúsculas y no por su
    /// posición en el `enum`.** El orden de `Waveform.allCases` lo manda la
    /// rejilla 2×2 de la pantalla, y atar el fichero al índice haría que
    /// reordenar la rejilla cambiara la onda de un Bank ya guardado. Es el mismo
    /// criterio que `scale`, y por eso tampoco se reutiliza
    /// `Waveform.description`: aquello es lo que se lee en pantalla, y son dos
    /// vocabularios distintos aunque hoy coincidan.
    public let waveform: String?
    public let accent: Int?

    /// Pitch, desde el 2026-09-12 (`pitch-harmony_20260912`).
    ///
    /// **Opcional por la misma razón que las de arriba**: un fichero anterior la
    /// decodifica como `nil` y se lee sin transponer. **Se escribe siempre**, y se
    /// guarda el offset y no el pool que suena, que se deriva al construir el
    /// Cycle: guardar los dos sería tener dos fuentes de lo mismo.
    public let pitchOffset: Int?

    public init(_ cycle: Cycle) {
        steps = cycle.shape.steps.count
        pulses = cycle.shape.pulses.count
        rotate = cycle.shape.rotate.amount
        divisionNumerator = cycle.shape.division.numerator
        divisionDenominator = cycle.shape.division.denominator
        pool = (0..<PitchPool.capacity).compactMap { cycle.pool.pitch(at: $0)?.value }
        velocity = cycle.groove.velocity.value
        sustain = cycle.groove.sustain.percent
        probability = cycle.groove.probability.percent
        timing = cycle.groove.timing.percent
        delay = cycle.groove.delay.percent
        channel = cycle.channel.number
        scale = Self.key(for: cycle.frame.scale)
        root = cycle.frame.root.pitchClass
        padOctaveShift = cycle.padOctaveShift
        repeats = cycle.noteRepeater.repeats.count
        repeatTimeDenominator = cycle.noteRepeater.time.fraction.denominator
        ramp = cycle.noteRepeater.ramp.percent
        pace = cycle.noteRepeater.pace.percent
        waveform = Self.key(for: cycle.modulation.waveform)
        accent = cycle.modulation.accent.percent
        pitchOffset = cycle.pitchOffset.degrees
    }

    /// El Cycle que describe.
    ///
    /// **Un valor fuera de rango cae en su default en vez de reventar.** El
    /// fichero puede venir de cualquier sitio, y un Sustain de 900 no es razón
    /// para no abrir la app: la alternativa —fallar la carga entera— convertiría
    /// un byte malo en la pérdida de un Bank.
    public var cycle: Cycle {
        let shape = Shape(
            steps: Steps(steps) ?? Steps(16)!,
            pulses: Pulses(pulses) ?? Pulses(1)!,
            rotate: Rotate(rotate),
            division: Division(numerator: divisionNumerator, denominator: divisionDenominator)
                ?? .sixteenth
        )

        var pitches = PitchPool()
        for value in pool {
            guard let pitch = Pitch(value) else { continue }
            pitches = pitches.inserting(pitch)
        }

        let groove = Groove(
            velocity: Velocity(velocity) ?? .default,
            sustain: Sustain(percent: sustain) ?? .default,
            probability: Probability(percent: probability) ?? .default,
            timing: Timing(percent: timing) ?? .default,
            delay: Delay(percent: delay) ?? .default
        )

        // Un valor fuera de rango cae en su default, como el resto de las
        // claves. Time se busca en la lista por su denominador: una fracción que
        // no esté en ella —un fichero de otra versión, o tocado a mano— vuelve
        // como el default en vez de dejar el Bank sin abrir.
        let repeater = NoteRepeater(
            repeats: repeats.flatMap(Repeats.init) ?? .default,
            time: RepeatTime.ordered.first { $0.fraction.denominator == repeatTimeDenominator }
                ?? .default,
            ramp: ramp.flatMap { Ramp(percent: $0) } ?? .default,
            pace: pace.flatMap { Pace(percent: $0) } ?? .default
        )

        // Una onda desconocida y un accent fuera de rango caen en su default,
        // como el resto de las claves: un fichero de otra versión —o tocado a
        // mano— no deja un Bank sin abrir.
        let modulation = Modulation(
            waveform: waveform.map(Self.waveform(for:)) ?? .default,
            accent: accent.flatMap { Accent(percent: $0) } ?? .default
        )

        return Cycle(
            shape: shape,
            pool: pitches,
            groove: groove,
            channel: Channel(channel) ?? .first,
            frame: TonalFrame(scale: Self.scale(for: scale), root: Root(root) ?? .c),
            noteRepeater: repeater,
            modulation: modulation,
            padOctaveShift: padOctaveShift,
            // Fuera de ±28 cae en el neutro, como el resto de las claves.
            pitchOffset: pitchOffset.flatMap(PitchOffset.init) ?? .zero
        )
    }

    /// La clave con la que cada escala se escribe en disco.
    ///
    /// **Exhaustivo a propósito**: sin `default`, añadir una escala al motor no
    /// compila hasta que alguien decida cómo se guarda.
    static func key(for scale: Scale) -> String {
        switch scale {
        case .minor: "minor"
        case .major: "major"
        case .dorian: "dorian"
        case .phrygian: "phrygian"
        case .pentatonic: "pentatonic"
        case .mixolydian: "mixolydian"
        case .lydian: "lydian"
        case .hirajoshi: "hirajoshi"
        }
    }

    /// Y de vuelta. Una clave desconocida cae en `minor`, que es el default del
    /// producto: un fichero de una versión futura no deja la app sin abrir.
    static func scale(for key: String) -> Scale {
        Scale.allCases.first { Self.key(for: $0) == key } ?? .minor
    }

    /// La clave con la que cada onda se escribe en disco.
    ///
    /// **Exhaustivo a propósito**, como el de `Scale`: sin `default`, añadir una
    /// onda al motor no compila hasta que alguien decida cómo se guarda.
    ///
    /// **No es `Waveform.description`**, aunque hoy coincidan. Aquel es lo que
    /// enseña la pantalla y atar el fichero a él haría que un cambio de
    /// rotulación rompiera ficheros guardados. Son dos vocabularios distintos:
    /// uno se lee, otro se guarda — la misma razón que separa `scale` de
    /// `Scale.name`.
    static func key(for waveform: Waveform) -> String {
        switch waveform {
        case .saw: "saw"
        case .triangle: "triangle"
        case .sine: "sine"
        case .pulse: "pulse"
        }
    }

    /// Y de vuelta. Una clave desconocida cae en el default del producto.
    static func waveform(for key: String) -> Waveform {
        Waveform.allCases.first { Self.key(for: $0) == key } ?? .default
    }
}

// MARK: - Track

/// Un `Track` en disco: sus dieciséis Cycles, cuántos están activos y cuál se
/// está editando.
///
/// **El cursor de reproducción no está, y es a propósito** (FR8). Lo mueve el
/// hilo del scheduler en el límite de vuelta: es estado de ejecución y no
/// material. Un Pattern entra siempre por el principio de su desarrollo, así que
/// disparar el break suena igual las dos veces.
public struct TrackRecord: Codable, Equatable, Sendable {

    public let cycles: [CycleRecord]
    public let activeCount: Int
    public let editing: Int

    public init(_ track: Track) {
        cycles = (0..<Track.cycleCount).compactMap { track.cycle(at: $0).map(CycleRecord.init) }
        activeCount = track.activeCount
        editing = track.editing
    }

    /// El Track que describe, con el cursor de reproducción en el primer Cycle.
    ///
    /// **Un fichero con menos de dieciséis Cycles se completa** con el primero,
    /// que es lo que `Track.init(_:)` ya hace: los dieciséis existen siempre, y
    /// un fichero recortado no puede producir un Track con huecos.
    public var track: Track {
        // **El rango se abre antes de escribir los Cycles, no después.**
        // `withActiveCount` copia el Cycle en edición en los huecos que activa
        // —FR3 de la rebanada de Cycles—, que es lo correcto cuando lo sube un
        // usuario y sería destructivo aquí: pisaría lo que se acaba de leer del
        // fichero.
        let first = cycles.first?.cycle ?? Pattern.emptyCycle
        var result = Track(first).withActiveCount(activeCount)
        for (index, record) in cycles.enumerated() {
            result = result.replacing(record.cycle, at: index)
        }
        return result.withEditing(editing)
    }
}

// MARK: - Pattern

/// Un `Pattern` en disco: sus doce Tracks.
public struct PatternRecord: Codable, Equatable, Sendable {

    public let tracks: [TrackRecord]

    public init(_ pattern: Pattern) {
        tracks = (0..<Pattern.trackCount).compactMap { pattern.track(at: $0).map(TrackRecord.init) }
    }

    /// El Pattern que describe. Los huecos que falten quedan vacíos: los doce
    /// existen siempre.
    public var pattern: Pattern {
        var result = Pattern()
        for (index, record) in tracks.enumerated() {
            result = result.replacing(record.track, at: index)
        }
        return result
    }
}

// MARK: - Bank

/// Un `Bank` en disco: dieciséis Patterns y su tempo.
public struct BankRecord: Codable, Equatable, Sendable {

    /// Los dieciséis, **con `null` donde no hay nada**.
    ///
    /// **Un Pattern vacío son ~42 KB de ceros**: doce Tracks por dieciséis
    /// Cycles de quince campos cada uno, todos en su valor por defecto.
    /// Escribirlos deja un Bank recién creado ocupando lo mismo que uno lleno
    /// —675 498 bytes contra 675 530, medidos— y un Project vacío en 10,8 MB.
    /// Con la marca, un Project vacío no llega a 4 KB.
    ///
    /// **La marca es `null` y no un centinela inventado**: el formato ya tiene
    /// una forma de decir «aquí no hay nada», y un hueco `null` se lee con los
    /// ojos igual de bien que un objeto.
    ///
    /// **Los huecos ocupan su sitio en la lista.** Es el riesgo real de
    /// colapsar: si los vacíos se omitieran, el Pattern 10 volvería en la
    /// posición 2. La lista siempre tiene dieciséis entradas.
    public let patterns: [PatternRecord?]

    public let tempo: Double

    public init(_ bank: Bank) {
        patterns = (0..<Bank.patternCount).map { index in
            guard let pattern = bank.pattern(at: index), pattern.hasMaterial else { return nil }
            return PatternRecord(pattern)
        }
        tempo = bank.tempo.beatsPerMinute
    }

    /// El Bank que describe. Un tempo fuera de rango cae en el default, con el
    /// mismo criterio que el resto de esta capa. Un hueco `null` queda como el
    /// `Pattern()` con el que arranca un Bank.
    public var bank: Bank {
        var result = Bank().withTempo(Tempo(beatsPerMinute: tempo) ?? Bank.defaultTempo)
        for (index, record) in patterns.enumerated() {
            guard let record else { continue }
            result = result.replacing(record.pattern, at: index)
        }
        return result
    }
}

// MARK: - Project

/// El `Project` en disco: los dieciséis Banks, dónde se estaba mirando y los
/// ajustes de sesión.
///
/// **No lleva los Banks dentro, y eso es el formato de disco** (FR18): cada Bank
/// es su propio fichero de ~600 KB, y éste es la cabecera. Así el Autosave
/// reescribe solo el Bank tocado en vez de los dieciséis, y `Save Bank` puede
/// copiar un fichero en vez de recortar un árbol.
///
/// **Es el único record con `schemaVersion`**, porque es la raíz: un fichero de
/// Bank sin cabecera no se abre solo.
public struct ProjectRecord: Codable, Equatable, Sendable {

    /// La versión que esta app escribe.
    ///
    /// **Entra desde el primer commit** aunque no haya nada a lo que migrar,
    /// porque `tech-stack.md` lo exige y porque el primer cambio ya está fechado:
    /// las rebanadas 5 y 6 añaden campos al `Cycle`.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let selectedBank: Int
    public let selectedPattern: Int
    public let selectedTrack: Int

    /// `"internal"` o `"external"`.
    public let clockSource: String

    /// El nombre del hardware, o `nil`. **No haber elegido es un estado válido**,
    /// no un campo que falte.
    public let destinationName: String?
    public let sourceName: String?

    /// El mapeo aprendido, o **ausente si nunca se aprendió nada**.
    ///
    /// **Es opcional a propósito, y por eso `schemaVersion` no sube**
    /// (`midi-learn_20260908`, FR17). La migración que haría falta es «si no
    /// está, usa el preset de fábrica», y eso es justo lo que un opcional ya
    /// significa aquí — el mismo criterio que `destinationName`. Subir a 2 sin
    /// migrador haría que `validated()` lanzara para todos los ficheros
    /// existentes, y `ProjectStore.load()` los apartaría: la app abriría vacía.
    public let controlNumbers: ControlNumbersRecord?

    /// **El segundo parámetro existe para poder construir un record con una
    /// versión que no es la vigente**, que es lo único que permite probar el
    /// camino de la versión no soportada sin fabricar JSON a mano.
    public init(_ project: Project, schemaVersion: Int = ProjectRecord.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        selectedBank = project.selectedBank
        selectedPattern = project.selectedPattern
        selectedTrack = project.selectedTrack
        clockSource = project.clockSource == .external ? "external" : "internal"
        destinationName = project.destinationName
        sourceName = project.sourceName
        controlNumbers = project.controlNumbers.map(ControlNumbersRecord.init)
    }

    /// El Project que describe, **con los Banks que le den**.
    ///
    /// Los Banks vienen de sus propios ficheros: esta cabecera solo sabe dónde
    /// se estaba mirando y qué reloj mandaba. Los que falten quedan vacíos, que
    /// es lo que hace que un Project a medio escribir no impida arrancar.
    ///
    /// Los índices pasan por los métodos que los acotan, así que un índice
    /// corrupto en disco produce el borde y no una selección plausible.
    public func project(with banks: [Bank]) -> Project {
        var result = Project()
        for (index, bank) in banks.enumerated() {
            result = result.replacing(bank, at: index)
        }
        return
            result
            .selectingBank(selectedBank)
            .selectingPattern(selectedPattern)
            .selectingTrack(selectedTrack)
            .withClockSource(clockSource == "external" ? .external : .internal)
            .remembering(destinationNamed: destinationName, sourceNamed: sourceName)
            .remembering(controlNumbers: controlNumbers?.numbers)
    }
}

/// El mapeo del controlador, tal como se escribe en disco.
///
/// **Las claves son del disco y no de la pantalla.** Cada parámetro se guarda
/// por una cadena estable en minúsculas y no por su posición en el `enum`: el
/// orden de `TrackParameter.allCases` es el del flujo del motor, y atar el
/// fichero a él haría que reordenarlo cambiara el mapeo de un usuario. Es el
/// mismo criterio que `scale` y `waveform`, y por eso tampoco se reutiliza
/// `TrackParameter.description`, que es lo que se lee en la interfaz.
public struct ControlNumbersRecord: Codable, Equatable, Sendable {

    /// Número de controlador por parámetro, con el parámetro escrito por su
    /// clave.
    public let assignments: [String: Int]

    public let padBlock: Int
    public let knobBlock: Int
    public let stepButtonBlock: Int

    public init(assignments: [String: Int], padBlock: Int, knobBlock: Int, stepButtonBlock: Int) {
        self.assignments = assignments
        self.padBlock = padBlock
        self.knobBlock = knobBlock
        self.stepButtonBlock = stepButtonBlock
    }

    public init(_ numbers: ControlNumbers) {
        assignments = Dictionary(
            uniqueKeysWithValues: numbers.assignments.map { (Self.key(for: $0.key), $0.value) })
        padBlock = numbers.padBlock
        knobBlock = numbers.knobBlock
        stepButtonBlock = numbers.stepButtonBlock
    }

    /// Los números que describe.
    ///
    /// **Una clave desconocida se descarta y el resto entra.** Un fichero
    /// escrito por una app más nueva no puede dejar sin mapeo a ésta; con el
    /// mismo criterio que una escala desconocida cae en `minor` en vez de
    /// impedir la apertura.
    public var numbers: ControlNumbers {
        var table: [TrackParameter: Int] = [:]
        for (key, number) in assignments {
            guard let parameter = Self.parameter(for: key) else { continue }
            table[parameter] = number
        }
        return ControlNumbers(
            assignments: table,
            padBlock: padBlock,
            knobBlock: knobBlock,
            stepButtonBlock: stepButtonBlock
        )
    }

    /// La clave con la que cada parámetro se escribe en disco.
    ///
    /// **Exhaustivo a propósito**, como los de `Scale` y `Waveform`: sin
    /// `default`, añadir un parámetro al motor no compila hasta que alguien
    /// decida cómo se guarda. Sin eso, un mapeo aprendido perdería justo el
    /// parámetro nuevo, en silencio.
    static func key(for parameter: TrackParameter) -> String {
        switch parameter {
        case .steps: "steps"
        case .pulses: "pulses"
        case .rotate: "rotate"
        case .division: "division"
        case .repeats: "repeats"
        case .repeatTime: "repeattime"
        case .ramp: "ramp"
        case .pace: "pace"
        case .velocity: "velocity"
        case .sustain: "sustain"
        case .probability: "probability"
        case .timing: "timing"
        case .delay: "delay"
        case .pitch: "pitch"
        }
    }

    /// Y de vuelta. `nil` para lo que esta app no conoce.
    static func parameter(for key: String) -> TrackParameter? {
        TrackParameter.allCases.first { Self.key(for: $0) == key }
    }
}

extension ProjectRecord {

    /// El mismo record si su versión es la que esta app entiende, o un error si
    /// no.
    ///
    /// **El error tiene que ser distinguible de uno de decodificación**, y esa
    /// es toda la razón de que exista este método. La Fase 4 decide qué hacer
    /// con el fichero según de qué falle, y `DecodingError` no separa «esto no
    /// es JSON válido» de «esto lo escribió una app más nueva». Los dos acaban
    /// en el mismo sitio —el fichero se aparta y la app arranca— pero lo que se
    /// le dice al usuario no es lo mismo.
    public func validated() throws -> ProjectRecord {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SchemaError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: Self.currentSchemaVersion
            )
        }
        return self
    }

    /// El punto donde enchufar la primera migración. **Hoy no hace nada**, y
    /// eso es deliberado (FR19).
    ///
    /// Escribir un migrador de v1 a v2 antes de que exista v2 es probar una
    /// migración inventada, que envejece con el esquema real. Lo que hace falta
    /// ahora es que el sitio esté decidido y que la llamada esté puesta, para
    /// que quien escriba la primera no tenga además que decidir dónde va.
    ///
    /// **El primer caso ya está fechado**: las rebanadas 5 y 6 añaden campos al
    /// `Cycle`.
    public static func migrated(_ record: ProjectRecord) throws -> ProjectRecord {
        try record.validated()
    }
}

/// Lo que puede ir mal con la versión de un fichero.
public enum SchemaError: Error, Equatable, CustomStringConvertible, Sendable {

    /// El fichero declara una versión que esta app no entiende.
    ///
    /// **Lleva los dos números dentro** porque un mensaje que solo diga «versión
    /// no soportada» obliga a abrir el fichero a mano para saber cuál.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            "El fichero declara la versión de esquema \(found) y esta app entiende la \(supported)."
        }
    }
}
