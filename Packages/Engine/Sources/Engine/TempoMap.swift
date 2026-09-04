/// Convierte entre el tiempo del reloj y el tiempo musical de la rejilla.
///
/// **Existe para poder seguir a un maestro sin tocar la rejilla.** Los Steps se
/// calculan contra un tempo de referencia fijo —el que se fijó al arrancar— y
/// este mapa estira o encoge esa línea de tiempo para que caiga donde el maestro
/// dice. La alternativa era rehacer las rejillas de los doce Tracks a cada
/// cambio de tempo, que es exactamente lo que `TrackScheduler` documenta como
/// imposible en caliente: cambiar la duración del Step reubica todos los Steps
/// futuros respecto a un origen que ya pasó.
///
/// **Aquí no ocurre eso**, porque el mapa se **rebasa**: al cambiar de tempo se
/// conserva el instante musical en curso y solo cambia la pendiente a partir de
/// ahí. Sin rebase, un cambio de tempo movería el pasado y la música daría un
/// salto.
///
/// **Y es global a los doce Tracks**, que es lo que lo hace legítimo. Rebasar la
/// línea de tiempo de **un** Track rompería el invariante que los mantiene en
/// fase —todas las rejillas se miden contra el mismo origen—, y por eso el track
/// `cycles_20260901` lo descartó para la Division. Un cambio de tempo del
/// maestro les llega a los doce a la vez y con el mismo rebase, así que el
/// invariante se conserva.
///
/// Todo en nanosegundos relativos al arranque del transporte, y sin conocer el
/// reloj de host: por eso vive en `Engine`.
public struct TempoMap: Equatable, Sendable {

    /// Duración de la negra con la que se construyeron las rejillas.
    private let referenceQuarterNoteNanoseconds: Double

    /// Nanosegundos de rejilla por nanosegundo de reloj.
    ///
    /// `1` mientras no haya maestro: el tiempo musical y el del reloj son el
    /// mismo, que es como se comportaba la app antes de que esto existiera.
    public private(set) var ratio: Double

    /// Instante de reloj del último rebase.
    private var wallAnchor: Int64

    /// Instante musical que le corresponde.
    private var gridAnchor: Int64

    public init(referenceQuarterNoteNanoseconds: Double) {
        self.referenceQuarterNoteNanoseconds = referenceQuarterNoteNanoseconds
        ratio = 1
        wallAnchor = 0
        gridAnchor = 0
    }

    /// Instante musical que corresponde a un instante de reloj.
    ///
    /// Realtime: llamado desde el hilo del scheduler, una vez por ventana.
    /// Sin asignaciones, sin locks, sin await.
    public func gridNanoseconds(atWallNanoseconds wall: Int64) -> Int64 {
        gridAnchor + Int64((Double(wall - wallAnchor) * ratio).rounded())
    }

    /// Instante de reloj en que cae un instante musical.
    ///
    /// Es la inversa de `gridNanoseconds(atWallNanoseconds:)`, y tiene que serlo
    /// con exactitud: el scheduler mide el horizonte en tiempo musical y sella
    /// los timestamps en tiempo de reloj, así que una asimetría desplazaría cada
    /// evento.
    ///
    /// Realtime: llamado desde el hilo del scheduler, por cada evento.
    /// Sin asignaciones, sin locks, sin await.
    public func wallNanoseconds(forGridNanoseconds grid: Int64) -> Int64 {
        wallAnchor + Int64((Double(grid - gridAnchor) / ratio).rounded())
    }

    /// Sigue el tempo del maestro a partir de este instante.
    ///
    /// **Rebasa antes de cambiar la pendiente**, que es lo que evita el salto:
    /// el instante musical en curso se conserva y lo que cambia es la velocidad
    /// a la que avanza desde ahí.
    ///
    /// Una negra de duración no positiva no cambia nada: es lo que llegaría de
    /// un maestro roto.
    ///
    /// Realtime: llamado desde el hilo del scheduler, una vez por ventana.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func follow(quarterNoteNanoseconds: Double, atWallNanoseconds wall: Int64) {
        guard quarterNoteNanoseconds > 0 else { return }

        gridAnchor = gridNanoseconds(atWallNanoseconds: wall)
        wallAnchor = wall
        ratio = referenceQuarterNoteNanoseconds / quarterNoteNanoseconds
    }

    /// Mueve el origen de la rejilla en tiempo de reloj.
    ///
    /// Positivo lo retrasa —cada instante musical cae más tarde—, negativo lo
    /// adelanta. **Se mide en tiempo de reloj y no en fracciones de negra**
    /// porque eso es lo que es un desfase: milisegundos de diferencia con el
    /// maestro, independientemente del tempo al que vaya.
    ///
    /// Realtime: llamado desde el hilo del scheduler, una vez por ventana.
    /// Sin asignaciones, sin locks, sin await.
    public mutating func shiftOrigin(byWallNanoseconds shift: Int64) {
        wallAnchor += shift
    }
}
