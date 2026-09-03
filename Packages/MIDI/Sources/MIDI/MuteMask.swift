import CToraxAtomics
import Engine

/// Qué Tracks están muteados y cuáles soleados, en un instante.
///
/// **Es el valor que se lee de golpe**, no el sitio donde vive el estado: eso es
/// `MuteMask`. Separarlos es lo que permite que el hilo del scheduler haga una
/// sola lectura atómica y decida sobre los doce Tracks con una foto coherente.
///
/// **Trivial por obligación.** Se copia en el camino de tiempo real, así que no
/// puede retener nada: dos enteros de 16 bits y nada más. `_isPOD(MuteState)` es
/// la red que lo vigila, igual que en `Cycle` y `Pattern`.
public struct MuteState: Equatable, Sendable {

    /// Un bit por Track, el 0 el primero. Solo los `Pattern.trackCount`
    /// primeros pueden estar encendidos.
    private var mutes: UInt16
    private var solos: UInt16

    /// Nada muteado, nada soleado: los doce suenan.
    public init() {
        mutes = 0
        solos = 0
    }

    init(mutes: UInt16, solos: UInt16) {
        self.mutes = mutes & Self.usableBits
        self.solos = solos & Self.usableBits
    }

    /// Los bits que corresponden a un Track real. Los de más arriba se
    /// descartan al construir: un índice de más no puede dejar encendido un
    /// Track que no existe.
    private static let usableBits: UInt16 = UInt16((1 << Pattern.trackCount) - 1)

    private static func bit(_ index: Int) -> UInt16? {
        guard (0..<Pattern.trackCount).contains(index) else { return nil }
        return UInt16(1 << index)
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func isMuted(_ index: Int) -> Bool {
        guard let bit = Self.bit(index) else { return false }
        return mutes & bit != 0
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func isSoloed(_ index: Int) -> Bool {
        guard let bit = Self.bit(index) else { return false }
        return solos & bit != 0
    }

    /// **Si ese Track se oye ahora mismo.** La regla entera, en un sitio:
    ///
    /// ```
    /// audible(i) = !mute(i) && (soloMask == 0 || solo(i))
    /// ```
    ///
    /// **Sin ningún solo suenan todos**, no ninguno: el solo solo significa algo
    /// cuando alguien lo pide, y hasta entonces la mitad derecha de la regla es
    /// cierta para los doce.
    ///
    /// **El mute manda sobre el solo.** Un Track soleado *y* muteado calla, que
    /// es lo que hace un mixer. Al revés —que el solo levantara el mute— daría
    /// el estado imposible de «está en solo, no suena, y no se ve por qué».
    ///
    /// Un índice que no es de ningún Track no es audible: no hay nada que oír.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func isAudible(_ index: Int) -> Bool {
        guard Self.bit(index) != nil else { return false }
        guard !isMuted(index) else { return false }
        return !hasAnySolo || isSoloed(index)
    }

    /// Si hay **algún** solo activo, que es lo que cambia el significado de todo
    /// lo demás: con uno encendido, callar es lo normal y sonar la excepción.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var hasAnySolo: Bool { solos != 0 }

    /// El mismo estado con el mute de ese Track del revés.
    ///
    /// **Un índice fuera de los doce devuelve el estado tal cual.** Viene de un
    /// step button, que es hardware: el criterio es el de un CC sin asignar —no
    /// cambia nada y no es un error.
    public func togglingMute(_ index: Int) -> MuteState {
        guard let bit = Self.bit(index) else { return self }
        return MuteState(mutes: mutes ^ bit, solos: solos)
    }

    public func togglingSolo(_ index: Int) -> MuteState {
        guard let bit = Self.bit(index) else { return self }
        return MuteState(mutes: mutes, solos: solos ^ bit)
    }

    /// Los dos campos en una palabra: el mute en los bits bajos, el solo a
    /// partir del 16.
    ///
    /// El hueco entre los dos campos —los bits 12 a 15— está de sobra a
    /// propósito: si `Pattern.trackCount` volviera a subir hasta dieciséis, la
    /// disposición aguanta sin moverse.
    var word: UInt64 { UInt64(mutes) | (UInt64(solos) << 16) }

    init(word: UInt64) {
        self.init(mutes: UInt16(truncatingIfNeeded: word), solos: UInt16(truncatingIfNeeded: word >> 16))
    }
}

/// Dónde vive el estado de mezcla: doce mutes y doce solos, en una sola palabra
/// atómica.
///
/// **Una palabra y no dos atómicos.** El hilo del scheduler decide con el mute y
/// el solo a la vez, así que leerlos por separado permitiría ver el mute de
/// antes con el solo de después. En ese instante intermedio —el usuario suelta
/// el último solo y mutea otro Track— o callaría todo, o no callaría nada.
/// Ninguna de las dos es un estado que el usuario haya pedido nunca. Con un solo
/// `load`, la foto es siempre coherente.
///
/// **No lleva compare-and-swap, y es una decisión.** Todo lo que escribe aquí
/// llega por el actor principal: el gesto táctil nace ahí, y el del controlador
/// se salta al principal antes de aplicarse —`TransportModel` es `@MainActor` y
/// la recepción de CoreMIDI hace el salto—. Un solo escritor hace que leer,
/// cambiar un bit y escribir sea seguro sin CAS. **Si algún día algo escribe
/// desde otro hilo, esto deja de ser cierto** y hay que pasar a
/// compare-exchange: por eso está escrito aquí y no solo sabido.
///
/// **Fuera del `Pattern` a propósito.** Esto es mezcla, no material: cambiar de
/// Pattern no lo mueve, y silenciar un Track no lo edita. La Pre Spec lo
/// justifica en la nota del 2026-09-02.
public final class MuteMask: @unchecked Sendable {

    private let storage: UnsafeMutablePointer<TXAtomicUInt64>

    public init(_ initial: MuteState = MuteState()) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: TXAtomicUInt64())
        tx_atomic_uint64_store(storage, initial.word)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// La foto: los dos juegos, de una sola lectura.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func load() -> MuteState {
        MuteState(word: tx_atomic_uint64_load(storage))
    }

    /// Publica un estado entero. La vía de la pantalla, que ya tiene el suyo.
    public func store(_ state: MuteState) {
        tx_atomic_uint64_store(storage, state.word)
    }

    /// Alterna el mute de un Track. Escritor único: ver la nota del tipo.
    public func toggleMute(_ index: Int) {
        store(load().togglingMute(index))
    }

    /// Alterna el solo de un Track. Escritor único: ver la nota del tipo.
    public func toggleSolo(_ index: Int) {
        store(load().togglingSolo(index))
    }
}
