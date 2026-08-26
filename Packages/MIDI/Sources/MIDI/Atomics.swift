import CToraxAtomics

/// Bandera booleana sin lock, para comunicar el hilo de control con el del
/// scheduler.
///
/// El hilo del scheduler la lee en cada vuelta del bucle; el hilo principal la
/// escribe al parar. Un lock aquí bloquearía el camino de timing, y en iPadOS 17
/// no hay atómicos en la stdlib —`Synchronization.Atomic` exige iOS 18—, así que
/// se apoya en el target C `CToraxAtomics`.
public final class AtomicFlag: @unchecked Sendable {

    private let storage: UnsafeMutablePointer<TXAtomicBool>

    public init(_ initialValue: Bool) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: TXAtomicBool())
        tx_atomic_bool_store(storage, initialValue)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// Realtime: legible desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var value: Bool {
        get { tx_atomic_bool_load(storage) }
        set { tx_atomic_bool_store(storage, newValue) }
    }
}

/// Contador de 64 bits sin lock.
///
/// Lo usa el arnés de medición para contar eventos emitidos desde el hilo del
/// scheduler mientras la interfaz los lee, sin que ninguno bloquee al otro.
public final class AtomicCounter: @unchecked Sendable {

    private let storage: UnsafeMutablePointer<TXAtomicUInt64>

    public init(_ initialValue: UInt64 = 0) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: TXAtomicUInt64())
        tx_atomic_uint64_store(storage, initialValue)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// Realtime: accesible desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var value: UInt64 {
        get { tx_atomic_uint64_load(storage) }
        set { tx_atomic_uint64_store(storage, newValue) }
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func increment(by amount: UInt64 = 1) {
        tx_atomic_uint64_add(storage, amount)
    }
}
