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

/// Un `Cycle` en disco: quince claves planas.
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

        return Cycle(
            shape: shape,
            pool: pitches,
            groove: groove,
            channel: Channel(channel) ?? .first,
            frame: TonalFrame(scale: Self.scale(for: scale), root: Root(root) ?? .c),
            padOctaveShift: padOctaveShift
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
/// **Es el único record con `schemaVersion`**, porque es la raíz: un fichero de
/// Bank sin Project no se abre solo.
public struct ProjectRecord: Codable, Equatable, Sendable {

    /// La versión que esta app escribe.
    ///
    /// **Entra desde el primer commit** aunque no haya nada a lo que migrar,
    /// porque `tech-stack.md` lo exige y porque el primer cambio ya está fechado:
    /// las rebanadas 5 y 6 añaden campos al `Cycle`.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let banks: [BankRecord]
    public let selectedBank: Int
    public let selectedPattern: Int
    public let selectedTrack: Int

    /// `"internal"` o `"external"`.
    public let clockSource: String

    /// El nombre del hardware, o `nil`. **No haber elegido es un estado válido**,
    /// no un campo que falte.
    public let destinationName: String?
    public let sourceName: String?

    public init(_ project: Project) {
        schemaVersion = Self.currentSchemaVersion
        banks = (0..<Project.bankCount).compactMap { project.bank(at: $0).map(BankRecord.init) }
        selectedBank = project.selectedBank
        selectedPattern = project.selectedPattern
        selectedTrack = project.selectedTrack
        clockSource = project.clockSource == .external ? "external" : "internal"
        destinationName = project.destinationName
        sourceName = project.sourceName
    }

    /// El Project que describe.
    ///
    /// Los índices pasan por los métodos que los acotan, así que un índice
    /// corrupto en disco produce el borde y no una selección plausible.
    public var project: Project {
        var result = Project()
        for (index, record) in banks.enumerated() {
            result = result.replacing(record.bank, at: index)
        }
        return
            result
            .selectingBank(selectedBank)
            .selectingPattern(selectedPattern)
            .selectingTrack(selectedTrack)
            .withClockSource(clockSource == "external" ? .external : .internal)
            .remembering(destinationNamed: destinationName, sourceNamed: sourceName)
    }
}
