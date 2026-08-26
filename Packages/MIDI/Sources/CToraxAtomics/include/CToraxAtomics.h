#ifndef CTORAX_ATOMICS_H
#define CTORAX_ATOMICS_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

/// Atómicos sin lock para comunicar el hilo de control con el del scheduler.
///
/// Existe porque en iPadOS 17 no hay alternativa sin dependencias:
/// `Synchronization.Atomic` de Swift 6 exige iOS 18, y `swift-atomics` seria una
/// dependencia de terceros que `tech-stack.md` prohibe. Un lock queda descartado
/// porque el hilo del scheduler no puede bloquearse.
///
/// Es codigo propio del proyecto, no una dependencia externa.

typedef struct {
    _Atomic(bool) value;
} TXAtomicBool;

static inline void tx_atomic_bool_store(TXAtomicBool *flag, bool newValue) {
    atomic_store_explicit(&flag->value, newValue, memory_order_release);
}

static inline bool tx_atomic_bool_load(const TXAtomicBool *flag) {
    return atomic_load_explicit(&flag->value, memory_order_acquire);
}

typedef struct {
    _Atomic(uint64_t) value;
} TXAtomicUInt64;

static inline void tx_atomic_uint64_store(TXAtomicUInt64 *counter, uint64_t newValue) {
    atomic_store_explicit(&counter->value, newValue, memory_order_release);
}

static inline uint64_t tx_atomic_uint64_load(const TXAtomicUInt64 *counter) {
    return atomic_load_explicit(&counter->value, memory_order_acquire);
}

static inline void tx_atomic_uint64_add(TXAtomicUInt64 *counter, uint64_t amount) {
    atomic_fetch_add_explicit(&counter->value, amount, memory_order_acq_rel);
}

/// Indica si los atomicos de esta plataforma son realmente lock-free.
///
/// En algunas plataformas `_Atomic` se emula con un lock interno, lo que
/// anularia el proposito de este target. Se verifica en tests.
bool tx_atomics_is_lock_free(void);

#endif /* CTORAX_ATOMICS_H */
