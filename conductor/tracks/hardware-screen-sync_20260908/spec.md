# Spec — La pantalla no ve lo que cambia el hardware

## Overview

**El estado del transporte y del reloj vive en `Transport`, que no es
observable**, y `TransportModel.clockRevision` —el contador que invalida la
pantalla— solo lo incrementan `setFollowsExternalClock` y `setTempo`, que son
gestos de la app. **Nadie lo incrementa desde el hilo de recepción de CoreMIDI**,
así que un cambio que venga del controlador no invalida nada.

Descubierto el 2026-09-06, durante la Fase 4 de `screens-redesign_20260906`. Dos
síntomas confirmados en dispositivo:

- **El botón de transporte no se entera de un Start del BeatStep.** La secuencia
  suena y el botón sigue enseñando *play*; pulsarlo llama a `play()` otra vez en
  vez de parar, así que **parece** que la app tiene precedencia sobre el
  controlador. No la tiene: `Transport.receive` da el mando al maestro desde el
  2026-09-03 y `ExternalStartTests` lo cubre. Lo que falla es que la app no se
  entera.
- **El tempo de un maestro externo no refresca la barra**, por lo mismo. El valor
  se calcula al preguntar y nadie le pide que vuelva a preguntar.

El propio `TransportModel.followsExternalClock` lo tiene escrito como límite
conocido desde el 2026-09-06.

## La forma del arreglo ya existe en el repositorio

`control-input-adoption_20260908` resolvió el mismo problema para la adopción de
Patterns: **el hilo de tiempo real solo incrementa una palabra atómica**
(`AtomicCounter`), y la app la lee desde un `.task` de 16 ms en `ToraxH0App` que
llama a `applyPendingAdoption()`. Ni callbacks desde el hilo de recepción, ni
temporizadores colgados de vistas.

Este track usa esa misma forma y ese mismo `.task`. No inventa un mecanismo
nuevo, y eso es la mitad de por qué es defendible después de tres intentos
fallidos.

> **Hallazgo del 2026-09-08, al planificar — hay una carrera de datos debajo, y
> condiciona la solución.**
>
> `Transport.isPlaying` es `scheduler?.isRunning`. `isRunning` sí es atómica
> (`AtomicFlag`), pero **`scheduler` es una propiedad almacenada normal**, y la
> escriben `startPlaying(atHostTime:)` y `stop()` — a las que `receive` llama
> **desde el hilo de recepción de CoreMIDI**. La pantalla la lee desde el hilo
> principal al dibujar. Eso es una carrera sobre una referencia de clase, hoy, y
> es anterior a este track.
>
> **Consecuencia para el diseño:** la solución barata y obvia —preguntar
> `isPlaying` más a menudo desde el `.task`— es la peor de todas. No arregla la
> carrera: la hace más probable, y precisamente en el instante en que el hilo de
> recepción está cambiando el scheduler. El estado tiene que **publicarse** por
> un atómico, no consultarse a través de `scheduler`.

## Functional Requirements

**FR1 — El transporte publica sus transiciones por un atómico.** Un contador de
generación que se incrementa en cada arranque y en cada parada, con la forma y
las garantías de `CyclePlaybackClock` y del contador de adopción: sin locks, sin
asignaciones, sin callbacks. Es un **contador**: lo que importa es que cambió, no
su valor.

**FR2 — Junto al contador viaja el estado, y también atómico.** Un flag que dice
si suena, escrito por el mismo camino. Sin él, el que lee sabe que algo pasó pero
tiene que volver a `scheduler` para saber qué — que es la carrera del hallazgo de
arriba.

**FR3 — Lo mueven las cuatro puertas, no solo las del hardware.** Play y Stop de
la app, y Start y Stop del maestro. Un contador que solo se mueva con el hardware
obligaría a mantener dos caminos de invalidación en vez de uno, y el que se
olvidara sería el que falla.

**FR4 — El tempo externo no lleva contador propio, y ese es el reparto.** El
tempo se publica una vez por negra —dos veces por segundo a 120 bpm— y una
invalidación por negra sería trabajo del hilo de recepción para algo que la
pantalla ya sabe calcular. **Lo compara la app en su tick**: si el tempo escrito
—el redondeado a un decimal, que es el que se ve— cambió desde la última vez,
invalida. Sin trabajo nuevo en el hilo de recepción.

**FR5 — Nada de cuarenta y ocho saltos por segundo.** El hilo de recepción atiende
un tick de reloj cada 20,8 ms a 120 bpm. **No se avisa por tick**, en ninguna
forma y por ningún camino.

**FR6 — La app lee desde el `.task` de 16 ms que ya existe.** El mismo de
`applyPendingAdoption()`, no uno nuevo, y **nunca** un temporizador colgado de una
vista: es el error que el tercer intento cometió, y las vistas se recrean con
cada invalidación.

**FR7 — Leer sin cambios cuesta lo mismo que hoy.** Una lectura atómica, una
comparación de enteros y una comparación de tempo. Eso es lo que pasa en casi
todos los cuadros.

**FR8 — El botón de transporte enseña lo que suena.** Después de un Start del
BeatStep, el botón enseña *stop* y pulsarlo **para**. Es el síntoma reportado,
y es el criterio de aceptación que manda.

**FR9 — La barra enseña el tempo del maestro.** Con reloj externo establecido, el
número de la barra sigue al maestro sin que nadie navegue a otra pantalla y
vuelva.

**FR10 — El estado del reloj también se refresca.** `clockStatus` y la marca
`EXT`/`INT` salen del mismo `Transport` y ya leen `clockRevision`: al
incrementarlo desde este camino, se refrescan sin tocar nada más. Incluye la
recuperación de un corte de reloj.

**FR11 — La pantalla puede ir hasta un cuadro por detrás.** Es el mismo límite
que la adopción declara, y por la misma razón: **lo que suena es exacto; lo que
se lee, no instantáneo**. Nadie lo oye.

## Non-Functional Requirements

**NFR1 — En el hilo de recepción no entra nada más que escrituras atómicas.** Ni
una asignación, ni un lock, ni un `await`, ni una llamada hacia el modelo. Las
funciones nuevas llevan el marcador `/// Realtime:`.

**NFR2 — La carrera sobre `scheduler` no crece.** Este track no añade lecturas de
`scheduler` desde el hilo principal. Si el arreglo termina eliminando la que hay
—porque el flag de FR2 sirva para responder `isPlaying`—, se anota y se prueba;
si no, se deja escrito como límite conocido con su ruta de arreglo.

**NFR3 — Cobertura.** `MIDI` ≥80%. El contador, el flag y su relación con
`receive` viven ahí.

**NFR4 — El cableado en `App` no lleva tests, y por eso es poca cosa.** `App` no
se mide (`workflow.md`). La comparación de FR4 y la lectura de FR6 tienen que ser
directas: si aparece una decisión, baja a `MIDI`.

**NFR5 — Sin medición de jitter.** La suspensión del 2026-09-02 manda, y este
cambio no mueve ningún instante. Lo que **sí** se comprueba es el coste por tick
—FR5, FR7—, que es otra cosa y se mide contando, no cronometrando.

**NFR6 — Se valida en dispositivo, con instrumentación y números.** Es la lección
de los tres intentos: los síntomas viven en el hilo de recepción de CoreMIDI y en
el hardware, y el simulador no tiene ninguno de los dos. Una captura de pantalla
o un porcentaje de CPU **no valen como prueba** en esta zona.

## Acceptance Criteria

1. Con reloj externo, pulsar Start en el BeatStep: la secuencia suena **y** el
   botón de la app pasa a *stop*. Pulsarlo entonces **para**.
2. Pulsar Stop en el BeatStep: el botón vuelve a *play*, sin navegar a ninguna
   parte.
3. Con reloj externo establecido, mover el tempo del maestro: el número de la
   barra lo sigue, y se lee estable —el redondeo a un decimal es el de hoy—.
4. Cortar el reloj del maestro y devolverlo: `clockStatus` refleja las dos
   transiciones.
5. Play y Stop **desde la app** siguen funcionando igual, con reloj interno y con
   externo.
6. **Contado, no estimado**: en un minuto de reloj externo a 120 bpm, el contador
   de FR1 se mueve tantas veces como transiciones hubo, y ni una más. Los 2880
   ticks del minuto no lo mueven.
7. La app **no** gana un temporizador nuevo: el número de `.task` en
   `ToraxH0App` es el mismo de antes.
8. `MIDI` ≥80% y la suite entera verde.

## Out of Scope

- **Hacer observable a `Transport`.** Es una clase que el hilo del scheduler
  toca; convertirla en `@Observable` metería el hilo principal donde no cabe.
- **Arreglar la carrera sobre `scheduler`** más allá de lo que NFR2 exige. Si el
  diagnóstico dice que merece su propio track, se abre.
- **Que la app emita clock.** Sigue fuera, como lo dejó `external-clock_20260903`.
- **Cualquier otra cosa del rediseño de pantallas.** Este track es el defecto,
  no la Fase 4 que lo encontró.
- **Medición de jitter** (NFR5).

## Known Limitations

- **Hasta un cuadro de retraso** entre el gesto del hardware y la pantalla
  (FR11).
- **Si la app no está dibujando, no se entera hasta que vuelva.** El sonido no
  depende de ello, igual que en la adopción.
- **El tempo se compara redondeado**, así que un cambio del maestro por debajo de
  la décima no refresca. Es lo que ya se ve en pantalla.
