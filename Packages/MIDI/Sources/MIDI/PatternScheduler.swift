import Engine

/// Programa los dieciséis Tracks sobre un solo reloj.
///
/// **Un reloj, dieciséis rejillas.** El tempo y el origen temporal son
/// compartidos —es lo que hace que dieciséis voces suenen juntas en vez de en
/// paralelo— pero cada Track cae donde digan sus Steps, su Division, su Timing y
/// su Delay. Aquí no hay sincronización posterior: la fase se conserva porque
/// todas las rejillas se miden contra el **mismo origen**, no porque se ajusten
/// entre sí.
///
/// **Un solo hilo los recorre.** No hay dieciséis hilos, y no es un ahorro: son
/// dieciséis hilos a prioridad máxima lo que hoy rompe la creación de endpoints
/// de CoreMIDI (la ampliación del 2026-08-27 de `workflow.md`). Recorrer
/// dieciséis rejillas dentro de la ventana ya abierta es aritmética de enteros
/// contra un presupuesto de veinte millones de nanosegundos.
///
/// **El snapshot se lee una vez por ventana, no una por Track.** Leerlo dieciséis
/// veces dejaría que dos Tracks tocaran material de publicaciones distintas, que
/// es exactamente la mezcla que el handoff existe para evitar.
public final class PatternScheduler {

    /// Material vigente. Se conserva entre ventanas: si una lectura del
    /// snapshot se descarta, se sigue tocando esto en lugar de callar.
    public private(set) var pattern: Pattern

    /// Un scheduler por Track, reservados de una vez.
    ///
    /// **Se reservan al construir, y construir es lo que hace Play.** Un `Array`
    /// metería comprobaciones de unicidad y posible conteo de referencias dentro
    /// del bucle; esto es un bloque de memoria que vive lo que viva el objeto,
    /// que es el mismo patrón que ya usa `PatternHandoff` con sus ranuras.
    private let schedulers: UnsafeMutablePointer<TrackScheduler>

    /// Cada Track lleva su propia rejilla porque lleva su propia Division.
    ///
    /// Se construyen aquí, con el tempo compartido: **el origen es el mismo para
    /// los dieciséis**, y por eso dos Divisions distintas caen en fase sin
    /// ajustarse entre sí.
    ///
    /// - Parameters:
    ///   - tempo: el tempo compartido; lo fija el transporte.
    ///   - pattern: con qué material se arranca.
    ///   - seed: semilla base del aleatorio. Cada Track deriva la suya, para que
    ///     dos Tracks con la misma Probability no omitan los mismos Pulses.
    public init(
        tempo: Tempo,
        pattern: Pattern,
        startingAtStep startingStep: Int = 0,
        seed: UInt64 = SeededRandom.defaultSeed
    ) {
        self.pattern = pattern
        schedulers = .allocate(capacity: Pattern.trackCount)

        for index in 0..<Pattern.trackCount {
            let cycle = pattern.cycle(at: index)!
            schedulers.advanced(by: index).initialize(
                to: TrackScheduler(
                    timeline: MusicalTimeline(tempo: tempo, division: cycle.shape.division),
                    material: .cycle(cycle),
                    startingAtStep: startingStep,
                    seed: Self.seed(seed, forTrack: index)
                )
            )
        }
    }

    /// Un solo material sobre una rejilla dada, y quince Tracks vacíos.
    ///
    /// **Es la vía del arnés de medición**, que mide la rejilla temporal y no el
    /// material musical: le hace falta `.everyStep` sobre una `MusicalTimeline`
    /// concreta, no dieciséis Tracks. Comparte el recorrido con el camino normal
    /// para que el arnés siga midiendo lo mismo que suena.
    public convenience init(
        timeline: MusicalTimeline,
        material: SchedulerMaterial,
        startingAtStep startingStep: Int = 0,
        seed: UInt64 = SeededRandom.defaultSeed
    ) {
        self.init(
            tempo: timeline.tempo, pattern: Pattern(), startingAtStep: startingStep, seed: seed)
        schedulers[0] = TrackScheduler(
            timeline: timeline,
            material: material,
            startingAtStep: startingStep,
            seed: Self.seed(seed, forTrack: 0)
        )
    }

    deinit {
        schedulers.deinitialize(count: Pattern.trackCount)
        schedulers.deallocate()
    }

    /// La semilla de un Track, derivada de la base.
    ///
    /// **Dos Tracks con la misma Probability no deben omitir los mismos
    /// Pulses**, o el aleatorio se oiría como una sola decisión en vez de como
    /// dieciséis voces independientes. Se deriva en vez de sortearse para que
    /// siga cumpliéndose la promesa de `tech-stack.md`: pulsar Play dos veces
    /// reproduce la misma secuencia.
    ///
    /// El multiplicador es un entero grande impar —el de Knuth para
    /// dispersión multiplicativa— así que índices contiguos dan semillas muy
    /// separadas y no secuencias emparentadas.
    static func seed(_ base: UInt64, forTrack index: Int) -> UInt64 {
        base &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
    }

    /// Cuánto hay que reservar por delante para que ningún evento adelantado se
    /// pida para un instante que ya pasó.
    ///
    /// **Es el mayor de los dieciséis**, no el del primero: el origen de la
    /// rejilla es común, así que tiene que dar cabida al Track que más se
    /// adelanta.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var advanceBudgetNanoseconds: Int64 {
        var budget: Int64 = 0
        for index in 0..<Pattern.trackCount {
            budget = max(budget, schedulers[index].advanceBudgetNanoseconds)
        }
        return budget
    }

    /// Recoge el snapshot pendiente y emite lo que dispare hasta el horizonte,
    /// Track por Track.
    ///
    /// `emit` recibe el índice del Track y **el Track que produjo el evento**.
    /// Quien emite necesita el canal y la Division, que son datos del Track, y
    /// entregárselos aquí es lo que le evita volver a leer el snapshot: la
    /// lectura se hace una vez por ventana, no una por nota. Con 2,25 KB esa
    /// diferencia era invisible; con Cycles el snapshot es dieciséis veces mayor
    /// y sería una copia de decenas de kilobytes por nota, en el hilo de tiempo
    /// real.
    ///
    /// Es además lo que garantiza que el canal y la Division con que sale una
    /// nota sean los del **mismo** snapshot que la produjo, y no los de una
    /// publicación que haya caído entre medias.
    ///
    /// **Un Track sin material no programa nada** (NFR3): su rejilla avanza
    /// —para que no pierda la fase si alguien le da alturas mientras suena— pero
    /// no se emite. El coste crece con los Tracks que suenan, no con dieciséis
    /// siempre.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func advance(
        toHorizon horizonNanoseconds: Int64,
        refreshingFrom handoff: PatternHandoff?,
        emit: (
            _ track: Int, _ source: Cycle, _ step: Int, _ pitch: Pitch?, _ groove: Groove,
            _ offsetNanoseconds: Int64
        ) -> Void
    ) {
        // Una sola lectura para los dieciséis: dos lecturas podrían caer a
        // ambos lados de una publicación.
        if let published = handoff?.load() {
            pattern = published
            for index in 0..<Pattern.trackCount {
                schedulers[index].refresh(with: pattern.cycle(at: index)!)
            }
        }

        for index in 0..<Pattern.trackCount {
            // Se pregunta al material del scheduler y no al Pattern porque el
            // arnés de medición no tiene Track detrás: mide la rejilla.
            let emits = schedulers[index].material.emitsAnything

            // Una copia por Track y por ventana, fuera del cierre: dentro sería
            // una por evento, que es justo la lectura que esta firma existe para
            // quitar. El índice no puede fallar: el Pattern siempre tiene
            // dieciséis.
            let source = pattern.cycle(at: index)!

            schedulers[index].advance(toHorizon: horizonNanoseconds, refreshingFrom: nil) {
                step, pitch, groove, offset in
                guard emits else { return }
                emit(index, source, step, pitch, groove, offset)
            }
        }
    }
}
