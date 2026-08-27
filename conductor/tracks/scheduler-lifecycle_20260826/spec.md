# Spec — Ciclo de vida del scheduler y desmontaje de CoreMIDI

**Track ID:** `scheduler-lifecycle_20260826`
**Track type:** Bug

## Overview

`SchedulerThread.stop()` no espera a que el hilo salga del bucle: solo baja una bandera atómica. El hilo tarda hasta media ventana de look-ahead en verla porque está dormido. Si `start()` llega antes, vuelve a subir la bandera y el hilo viejo nunca lee el `false`: quedan **dos schedulers vivos**, cada uno con su propio origen temporal y su propio `LookAheadScheduler`, emitiendo cada Step dos veces con timestamps distintos.

Eso contradice directamente el invariante que `LookAheadScheduler` documenta y promete: *«sobre llamadas sucesivas, cada Step se emite exactamente una vez»*. En el producto significaría notas duplicadas al parar y arrancar el transporte — el gesto más común que existe en un secuenciador.

**El arreglo obvio no funciona.** Hacer que `stop()` espere al hilo resuelve la carrera y está verificado que funciona (el join tarda 1–9 ms y el hilo sale limpio), pero deja la suite de `MIDI` en rojo **4 de 4 pasadas** con `clientCreationFailed(-50)`. La causa: retrasar el retorno de `stop()` unos 10 ms mueve el desmontaje justo dentro de la ventana en la que CoreMIDI todavía está emitiendo los eventos ya sellados con timestamp futuro. Destruir los endpoints virtuales en ese instante inutiliza la conexión MIDI del proceso: las siguientes llamadas a `MIDIClientCreateWithBlock` devuelven `paramErr`.

Por eso las dos cosas son un solo track. La carrera no se puede cerrar sin dar antes al arnés un **cierre explícito y ordenado**, en vez de depender de `deinit` y del instante en que ARC decide liberar cada objeto.

### Intentos ya descartados

Registrados para que el track no los repita:

1. **Join en `stop()`, sin más.** Correcto en semántica, rompe la suite 4/4.
2. **Drenar la ventana con `usleep` + `withExtendedLifetime` antes de desmontar.** Inestable: unas pasadas verdes, otras con un fallo más temprano y más amplio.
3. **Mover la espera a `start()`.** No agrava el flake, pero no resuelve el fondo: tras `stop()` el hilo viejo sigue emitiendo hasta media ventana. Un test escrito contra esta variante confundía «dos bucles a la vez» con «el hilo viejo emite unos ms tras `stop()`», que es comportamiento esperado si `stop()` no espera.

## Functional Requirements

### FR1 — `stop()` significa parar

Cuando `stop()` retorna, el hilo del scheduler ha salido del bucle y no volverá a invocar el handler. Ni un Step más.

### FR2 — Reiniciar no solapa bucles

`start()` tras `stop()` arranca exactamente un scheduler. Los Steps que emite empiezan en su propio origen y son contiguos: ninguno se repite ni se omite.

### FR3 — Cierre explícito del arnés

`VirtualLoopback` y `CoreMIDIOutput` exponen un cierre **explícito y ordenado**, no dependiente de `deinit` ni del orden en que ARC libere las referencias. El orden que impone el problema:

1. dejar de programar eventos nuevos,
2. dejar que la ventana de look-ahead ya entregada se vacíe,
3. dejar de enviar,
4. destruir puerto y endpoints,
5. destruir el cliente.

`JitterHarness.measure` usa ese cierre en lugar de confiar en que los locales se liberen en el momento adecuado.

### FR4 — El desmontaje no queda al azar

Ningún recurso de CoreMIDI se destruye desde `deinit` mientras pueda haber entregas en vuelo contra él. `deinit` queda como red de seguridad idempotente, no como el mecanismo principal.

## Non-Functional Requirements

- **NFR1 — Realtime safety:** el bucle del scheduler sigue sin asignar, sin locks, sin `await` y sin logging. La espera de `stop()` corre en el hilo de control, nunca en el del scheduler; llamarla desde dentro del bucle sería un error de programación, no un caso a soportar.
- **NFR2 — Parar no puede colgar.** Toda espera lleva cota superior. Agotarla se reporta; no se cuelga a quien pide parar.
- **NFR3 — Cobertura de `MIDI` ≥80%,** según `workflow.md`.
- **NFR4 — Sin regresión de jitter.** El camino de envío no cambia de forma. Si acaba cambiando, `workflow.md` (paso 7) exige medir en dispositivo antes de cerrar la tarea.

## Acceptance Criteria

- [ ] Existe un test de regresión de la carrera que **falla de forma fiable sin el arreglo** y pasa con él. Debe detectar Steps duplicados o fuera de orden tras ciclos rápidos de `stop()`/`start()`.
- [ ] Ese test usa una línea de tiempo deliberadamente rápida respecto a la ventana de look-ahead. A 120 BPM en 1/16 cada Step dura 125 ms y no da tiempo a que dos bucles se solapen: un test escrito así pasa aunque la carrera exista, y no vale.
- [ ] Se verifica explícitamente que el test falla al desactivar la guarda — no basta con que pase.
- [ ] `swift test` sobre `Engine` y `MIDI` pasa sin simulador ni hardware.
- [ ] La tasa de `clientCreationFailed(-50)` **no empeora** respecto a `main`, medida con el mismo número de pasadas en ambos.

## Known Limitations

1. **El flake de `-50` no es criterio de cierre de este track.** Se mide para no empeorarlo, no para eliminarlo; eliminarlo es el track `midi-test-flake_20260826`. Si el cierre explícito de FR3 acaba resolviéndolo —es plausible, comparten causa— ese track se reduce a verificarlo.
2. **La verificación es en macOS.** El desmontaje de CoreMIDI en iPadOS puede comportarse distinto. Este track no lo cubre.

## Out of Scope

- Publicar snapshots en caliente al scheduler (cambiar parámetros mientras suena). Sigue siendo trabajo del producto.
- Diagnosticar la causa raíz del `-50` en CoreMIDI.
- Cualquier cambio en el cálculo de timestamps o en la matemática de la ventana.
