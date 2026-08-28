import Engine

/// Qué decide si un Step dispara.
///
/// **Existe para que dos significados no compartan un `nil`.** Antes esto era un
/// `Track?`, y `nil` quería decir «emite todos los Steps». Pero
/// `TrackHandoff.load()` devuelve `nil` con otro significado —«descarta esta
/// lectura»—, así que enchufar uno en el otro convertía un descarte en una
/// ráfaga de notas a densidad máxima. Con dos casos con nombre, esa confusión no
/// se puede escribir.
public enum SchedulerMaterial: Equatable, Sendable {

    /// El material musical de un Track: dispara donde diga su Shape.
    case track(Track)

    /// Todos los Steps disparan.
    ///
    /// Es el modo del arnés de medición, que mide la rejilla temporal y no el
    /// material musical: ahí un reparto euclidiano solo quitaría muestras al
    /// histograma.
    case everyStep

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    func triggers(atStep index: Int) -> Bool {
        switch self {
        case let .track(track): track.triggers(atStep: index)
        case .everyStep: true
        }
    }
}

/// Decide qué Steps de un Track se emiten en cada ventana, y recoge los
/// snapshots que se publiquen mientras suena.
///
/// **Por qué existe como tipo aparte.** `LookAheadScheduler` sabe *qué Steps*
/// caen en la ventana; el Track sabe *cuáles de ellos disparan*. Juntarlo aquí
/// —y no dentro del hilo— deja el relevo de snapshot en un valor al que se le
/// puede dar el horizonte a mano. Así «el snapshot se recoge en la ventana
/// siguiente» es un test determinista y no una carrera contra el reloj.
///
/// **Dónde se recoge el snapshot.** Una vez por ventana, antes de recorrerla,
/// nunca a mitad. Un cambio a media ventana partiría el patrón dentro del mismo
/// horizonte y haría imposible razonar sobre qué Steps ya se habían entregado.
///
/// **Lo que el snapshot todavía no puede cambiar en caliente: Division.**
/// La rejilla temporal —cuándo cae cada Step— la fija la `MusicalTimeline` con
/// la que se construye este valor, y no se vuelve a leer. Cambiar la Division de
/// un Track publicado altera la duración del Step, así que reubicaría todos los
/// Steps futuros respecto a un origen que ya pasó: hace falta rebasar la línea
/// de tiempo en un límite de Step, no solo leer un valor nuevo. En esta rebanada
/// no hay entrada de control y ningún parámetro es editable, así que no se puede
/// provocar; llega con el track de entrada de control. Steps, Pulses y Rotate sí
/// cambian en caliente y están cubiertos por tests.
public struct TrackScheduler {

    /// Material vigente. Se conserva entre ventanas: si una lectura del snapshot
    /// se descarta, se sigue tocando esto en lugar de callar o inventar.
    public private(set) var material: SchedulerMaterial

    private var lookAhead: LookAheadScheduler

    public init(
        timeline: MusicalTimeline,
        material: SchedulerMaterial = .everyStep,
        startingAtStep startingStep: Int = 0
    ) {
        self.material = material
        self.lookAhead = LookAheadScheduler(timeline: timeline, startingAtStep: startingStep)
    }

    /// Recoge el snapshot pendiente y emite los Steps que disparan hasta el
    /// horizonte.
    ///
    /// `emit` recibe el índice de Step y su offset en nanosegundos respecto al
    /// origen de la línea de tiempo. El cierre no escapa, así que no hay nada que
    /// asignar para llamarlo.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func advance(
        toHorizon horizonNanoseconds: Int64,
        refreshingFrom handoff: TrackHandoff?,
        emit: (_ step: Int, _ offsetNanoseconds: Int64) -> Void
    ) {
        if let published = handoff?.load() {
            material = .track(published)
        }

        for step in lookAhead.advance(toHorizon: horizonNanoseconds) {
            guard material.triggers(atStep: step) else { continue }
            emit(step, lookAhead.timeline.nanosecondOffset(forStep: step))
        }
    }
}
