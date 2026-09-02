/// Un Track: hasta dieciséis Cycles, y por cuál va.
///
/// **El nivel nuevo de la v2.** Hasta esta rebanada, lo que la Pre Spec llama
/// Cycle se llamaba `Track` y era el juego de parámetros entero. Ahora el Track
/// lo **contiene**: hasta dieciséis versiones completas de sus ajustes, que se
/// recorren a cada vuelta del anillo. Es la A/B/C de la Pre Spec, y lo que le da
/// desarrollo en el tiempo a un Track sin que nadie toque un knob.
///
/// **Los dieciséis existen siempre**, como los dieciséis Tracks del `Pattern`:
/// no hay Cycles que crear ni destruir, solo cuántos se recorren. Es lo que
/// mantiene el tamaño fijo, y el tamaño fijo es lo que permite que este valor
/// cruce al hilo del scheduler sin asignar memoria.
///
/// **Almacenamiento inline, por obligación.** Una tupla y no un `Array`, por la
/// misma razón que en `Pattern` y en `PitchPool`: copiar esto ocurre en el hilo
/// del scheduler y un `retain` ahí viola las reglas de tiempo real.
/// `_isPOD(Track.self)` es la red que lo vigila.
///
/// **Lo que cuesta está medido**, antes de construirlo: el Pattern de dieciséis
/// Tracks con sus 256 Cycles ronda los 37 KB y un `load()` unos 870 ns, el
/// 0,0044% de la ventana de 20 ms. La tabla y su porqué están en
/// `PatternHandoff` y en `CycleSnapshotCostTests`.
public struct Track: Equatable, Sendable {

    /// Cuántos Cycles caben. La Pre Spec: «hasta 16 Cycles por Track».
    public static let cycleCount = 16

    /// Dieciséis Cycles seguidos, sin cabecera ni indirección.
    ///
    /// Se leen con aritmética de punteros sobre su almacenamiento —contiguo por
    /// ser homogénea— en vez de con un `switch` de dieciséis casos, igual que en
    /// `Pattern`. Los tests recorren los dieciséis huecos, así que un cambio de
    /// disposición se vería inmediatamente.
    private var cycles:
        (
            Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle,
            Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle
        )

    /// Cuántos Cycles se recorren, de 1 a 16.
    ///
    /// **Arranca en 1, y eso es lo que hace que meter este nivel no cambie lo
    /// que se oye** (FR10): con un solo Cycle activo el cursor no se mueve nunca
    /// y el Track suena como sonaba antes de la rebanada.
    public let activeCount: Int

    /// Por qué Cycle va la reproducción.
    ///
    /// **Lo mueve el hilo del scheduler**, en el límite de vuelta. No es el
    /// mismo cursor que el de edición: que se puedan separar es justo lo que
    /// permite construir el Cycle B mientras suena el A (FR7).
    public let cursor: Int

    /// A qué Cycle escuchan los knobs, los pads y las ediciones táctiles.
    ///
    /// **Es el otro cursor, y es de pantalla y no de sonido** (FR7). Con el
    /// transporte parado es lo único que decide qué se ve y se edita; con el
    /// transporte corriendo puede apuntar a un Cycle distinto del que suena, que
    /// es la forma natural de trabajar.
    ///
    /// Vive en el Track y no en la vista porque tiene que sobrevivir a cambiar de
    /// Track: volver a uno y encontrarlo editando otro Cycle sería perder el
    /// sitio, por la misma razón que `padOctaveShift` vive en el Cycle.
    public let editing: Int

    /// Un Track con ese Cycle en los dieciséis huecos, uno activo y el cursor en
    /// el primero.
    ///
    /// **Los quince restantes arrancan iguales al primero y no vacíos.** Un
    /// Cycle «vacío» no existe como concepto —un Cycle sin pool dispara y no
    /// emite, que es material válido—, y arrancar con copias es lo que hace que
    /// subir el número de activos entregue algo que ya suena en vez de silencio.
    public init(_ cycle: Cycle) {
        cycles = (
            cycle, cycle, cycle, cycle, cycle, cycle, cycle, cycle,
            cycle, cycle, cycle, cycle, cycle, cycle, cycle, cycle
        )
        activeCount = 1
        cursor = 0
        editing = 0
    }

    /// El constructor completo, para quien ya tiene los dieciséis y los dos
    /// contadores. Interno a propósito: fuera se llega por `replacing` y por los
    /// métodos que mueven los contadores, que son los que garantizan los rangos.
    init(
        cycles: (
            Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle,
            Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle, Cycle
        ),
        activeCount: Int,
        cursor: Int,
        editing: Int
    ) {
        self.cycles = cycles
        self.activeCount = activeCount
        self.cursor = cursor
        self.editing = editing
    }

    /// El Cycle que está sonando.
    ///
    /// El cursor nunca apunta fuera de rango —lo garantizan los métodos que lo
    /// mueven— así que el desempaquetado no puede fallar. Si alguna vez pudiera,
    /// el fallo estaría en quien movió el cursor y no aquí.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var current: Cycle { cycle(at: cursor) ?? cycle(at: 0)! }

    /// El Cycle de esa posición, o `nil` fuera de 0–15.
    ///
    /// Fuera de rango devuelve `nil` con el mismo criterio que un pad fuera de
    /// la superficie: no es un error y no revienta. Lo puede preguntar el hilo
    /// del scheduler, y ahí reventar sería un fallo de audio.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func cycle(at index: Int) -> Cycle? {
        guard (0..<Self.cycleCount).contains(index) else { return nil }
        return withUnsafePointer(to: cycles) { pointer in
            pointer.withMemoryRebound(to: Cycle.self, capacity: Self.cycleCount) {
                $0[index]
            }
        }
    }

    /// El mismo Track con ese Cycle en esa posición y los otros quince intactos.
    ///
    /// Fuera de rango devuelve el Track tal cual: nada que cambiar.
    public func replacing(_ cycle: Cycle, at index: Int) -> Track {
        guard (0..<Self.cycleCount).contains(index) else { return self }

        var updated = self
        withUnsafeMutablePointer(to: &updated.cycles) { pointer in
            pointer.withMemoryRebound(to: Cycle.self, capacity: Self.cycleCount) {
                $0[index] = cycle
            }
        }
        return updated
    }

    /// El mismo Track con el Cycle que suena sustituido.
    ///
    /// Es el camino de la edición en caliente mientras no exista el cursor de
    /// edición: girar un knob cambia lo que se está oyendo.
    public func replacingCurrent(_ cycle: Cycle) -> Track {
        replacing(cycle, at: cursor)
    }

    /// El mismo Track recorriendo otro número de Cycles, de 1 a 16.
    ///
    /// **Se frena en los extremos en vez de envolver**, como Steps y Division:
    /// envolver convertiría un giro de más en un salto de dieciséis Cycles a uno,
    /// y eso es destruir un desarrollo por un descuido.
    ///
    /// **Al subir, lo que empieza a existir nace copiando el Cycle en edición**
    /// (FR3) y no vacío ni por defecto. Es lo que hace que A/B/C se construya
    /// tocando: se duplica lo que se tiene delante y se le cambia una cosa. Y es
    /// también lo que evita que subir el número meta un cambio audible que nadie
    /// pidió — el Cycle nuevo suena igual hasta que se edita.
    ///
    /// **Al bajar se descarta por el final**, nunca por delante: descartar por
    /// delante renumeraría el desarrollo entero. Lo que queda fuera se deja como
    /// esté; si se vuelve a subir, la regla de arriba lo sobrescribe con una copia
    /// del Cycle en edición, que es lo que alguien espera al volver a subirlo.
    ///
    /// **El cursor de reproducción no se toca** (FR9). De eso se encarga el
    /// scheduler al cerrar la vuelta: la vuelta en curso se termina con el Cycle
    /// que estaba sonando y el avance siguiente entra en el rango, en vez de
    /// cortar un patrón por la mitad. El de edición sí se acota de inmediato,
    /// porque eso es pantalla y no sonido.
    public func withActiveCount(_ count: Int) -> Track {
        let clamped = min(max(count, 1), Self.cycleCount)

        var updated = self
        if clamped > activeCount {
            let seed = cycle(at: editing) ?? current
            for index in activeCount..<clamped {
                updated = updated.replacing(seed, at: index)
            }
        }

        return Track(
            cycles: updated.cycles,
            activeCount: clamped,
            cursor: cursor,
            editing: min(editing, clamped - 1)
        )
    }

    /// El mismo Track editando otro Cycle.
    ///
    /// Se acota al rango **activo** y no al de dieciséis: no se edita un Cycle
    /// que no se recorre. No mueve el cursor de reproducción ni toca el material
    /// (FR7).
    public func withEditing(_ index: Int) -> Track {
        Track(
            cycles: cycles,
            activeCount: activeCount,
            cursor: cursor,
            editing: min(max(index, 0), activeCount - 1)
        )
    }

    /// El mismo Track con la reproducción en otro Cycle.
    ///
    /// **Lo llama el scheduler**, en el límite de vuelta, y es la única vía por
    /// la que este cursor se mueve. Se acota al rango activo, que es lo que
    /// resuelve el caso de FR9: si el rango bajó mientras sonaba un Cycle que
    /// ahora queda fuera, el avance siguiente entra en el rango.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func withCursor(_ index: Int) -> Track {
        Track(
            cycles: cycles,
            activeCount: activeCount,
            cursor: min(max(index, 0), activeCount - 1),
            editing: editing
        )
    }

    /// Compara los dieciséis Cycles, cuántos hay activos y los dos cursores.
    ///
    /// Se escribe a mano porque una tupla de dieciséis no es `Equatable` sola, y
    /// compararla campo a campo dejaría fuera exactamente los huecos que nadie
    /// mira: es el mismo motivo por el que `Pattern` también la escribe.
    public static func == (lhs: Track, rhs: Track) -> Bool {
        guard lhs.activeCount == rhs.activeCount, lhs.cursor == rhs.cursor,
            lhs.editing == rhs.editing
        else { return false }
        for index in 0..<Self.cycleCount where lhs.cycle(at: index) != rhs.cycle(at: index) {
            return false
        }
        return true
    }
}
