import Engine

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

    /// Track vigente. Se conserva entre ventanas: si una lectura del snapshot se
    /// descarta, se sigue tocando esto en lugar de callar o inventar.
    ///
    /// **Sin Track se emiten todos los Steps.** Es el modo del arnés de
    /// medición, que mide la rejilla temporal y no el material musical: ahí un
    /// reparto euclidiano solo quitaría muestras al histograma.
    public private(set) var track: Track?

    private var lookAhead: LookAheadScheduler

    public init(timeline: MusicalTimeline, track: Track? = nil, startingAtStep startingStep: Int = 0) {
        self.track = track
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
            track = published
        }

        for step in lookAhead.advance(toHorizon: horizonNanoseconds) {
            guard track?.triggers(atStep: step) ?? true else { continue }
            emit(step, lookAhead.timeline.nanosecondOffset(forStep: step))
        }
    }
}
