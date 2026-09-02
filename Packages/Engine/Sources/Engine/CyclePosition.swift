/// Por qué Cycle va un Track, deducido del reloj.
///
/// **Se calcula al preguntar, no se guarda.** Es la misma regla que `Playhead`:
/// guardarlo obligaría a alguien a refrescarlo, y ese alguien sería un
/// temporizador de la interfaz — una animación no derivada del reloj musical,
/// que `product-guidelines.md` nombra como antipatrón. Aquí el reloj es la única
/// fuente: quien dibuja pregunta cuando va a dibujar.
///
/// **Y por qué se deduce en vez de leerse.** El cursor de reproducción vive en
/// el hilo del scheduler, que es su único dueño; publicarlo obligaría a ese hilo
/// a escribir algo en cada vuelta, y eso es trabajo en el camino de tiempo real
/// para que la pantalla no tenga que hacer una división. La deducción es exacta
/// porque el avance lo es: la vuelta *i* dura sus Steps por la duración del
/// Step, y las duraciones se suman.
///
/// **La rejilla sale del Cycle 1 y no del que esté sonando.** Es la limitación 8
/// del track `cycles_20260901`: la Division de un Cycle posterior se ignora, así
/// que la duración del Step es la que fijó Play. Deducir con otra cosa haría que
/// la pantalla y el sonido discreparan justo donde la limitación existe.
///
/// No es código de tiempo real: lo consulta la interfaz al redibujar.
public struct CyclePosition: Equatable, Sendable {

    /// Índice del Cycle que está sonando, 0 el primero.
    public let cycle: Int

    /// Punto de la vuelta de **ese** Cycle, como fracción en `[0, 1)`.
    ///
    /// No la usa nadie todavía; existe porque el cálculo la produce de todos
    /// modos y porque es lo que haría falta para dibujar un desarrollo que
    /// avanza, en vez de un índice que salta.
    public let turn: Double

    /// Deduce el Cycle en curso del tiempo que lleva sonando el transporte.
    ///
    /// Un tiempo negativo o nulo se trata como el origen: es el margen que el
    /// scheduler reserva para el Delay negativo, y ahí todavía no ha sonado
    /// nada.
    public init(elapsedNanoseconds: Int64, track: Track, tempo: Tempo) {
        guard elapsedNanoseconds > 0, track.activeCount > 1 else {
            cycle = 0
            turn = 0
            return
        }

        // La duración del Step la fija el Cycle 1, como en el scheduler.
        let stepDuration = MusicalTimeline(
            tempo: tempo,
            division: track.cycle(at: 0)!.shape.division
        ).stepDurationNanoseconds

        // Una pasada completa es la suma de las vueltas de los Cycles activos.
        // No se puede dividir sin más: dos Cycles pueden tener Steps distintos,
        // y entonces sus vueltas duran distinto.
        var pass = 0.0
        for index in 0..<track.activeCount {
            pass += stepDuration * Double(track.cycle(at: index)!.shape.steps.count)
        }

        var remainder = Double(elapsedNanoseconds).truncatingRemainder(dividingBy: pass)

        // Se recorre la pasada acumulando: como mucho dieciséis vueltas, sea
        // cual sea el tiempo transcurrido.
        for index in 0..<track.activeCount {
            let duration = stepDuration * Double(track.cycle(at: index)!.shape.steps.count)
            if remainder < duration {
                cycle = index
                turn = remainder / duration
                return
            }
            remainder -= duration
        }

        // Inalcanzable: el resto es menor que la suma. Se resuelve al último en
        // vez de reventar, por el mismo criterio que el resto de la pantalla.
        cycle = track.activeCount - 1
        turn = 0
    }
}

extension CyclePosition {

    /// El Cycle en curso de **cada uno** de los dieciséis Tracks.
    ///
    /// Los dieciséis siempre, tengan varios Cycles o no: un Track con uno solo
    /// resuelve a 0 y no hay que tratarlo aparte.
    ///
    /// No es código de tiempo real: lo consulta la interfaz al redibujar.
    public static func forEachTrack(
        in pattern: Pattern,
        tempo: Tempo,
        elapsedNanoseconds: Int64
    ) -> [CyclePosition] {
        (0..<Pattern.trackCount).map { index in
            CyclePosition(
                elapsedNanoseconds: elapsedNanoseconds,
                track: pattern.track(at: index) ?? Track(Pattern.emptyCycle),
                tempo: tempo
            )
        }
    }
}
