#include "include/CToraxAtomics.h"

/// El resto del target son funciones `static inline` en la cabecera, que no
/// generan codigo objeto. Xcode exige al menos una unidad de traduccion real
/// para poder enlazar el target, asi que esta funcion existe para eso.
///
/// Sin ella el build de host pasa pero el de iOS falla con:
///   "Build input file cannot be found: ... CToraxAtomics.o"
bool tx_atomics_is_lock_free(void) {
    TXAtomicBool flag;
    TXAtomicUInt64 counter;
    return atomic_is_lock_free(&flag.value) && atomic_is_lock_free(&counter.value);
}
