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

> **Enmienda del 2026-09-09, al empezar la Fase 1 — el segundo síntoma ya no
> existe, y lo resolvió otra cosa.**
>
> Comprobado en dispositivo por el usuario: con reloj externo, mover el tempo
> del maestro **sí** refresca el número de la barra. Y comprobado en el código
> por qué: `AppChrome.swift:222` envuelve el número en un
> `TimelineView(.periodic(by: 0.25))`, así que la vista repregunta cuatro veces
> por segundo y `beatsPerMinute` va directo a `transport.currentTempo`, que el
> hilo de recepción escribe por atómico. **Nadie necesita invalidar nada.** El
> propio comentario de esa vista lo dice desde que se escribió.
>
> Lo mismo vale para FR10: `MidiScreen.swift:20` envuelve la pantalla entera en
> otro `TimelineView` a 0,25 s, y ahí dentro están `clockStatus` y el segmentado
> `internal`/`external`.
>
> **Qué queda, entonces.** Solo el primer síntoma: el botón de transporte. Y se
> ve por qué el `TimelineView` no lo salvó — el botón está **fuera** de él
> (`AppChrome.swift:313`) y además no pregunta al transporte: lee
> `TransportModel.isPlaying`, la copia de la línea 487 que solo escriben `play()`
> y `stop()` de la app. Repintar más deprisa no lo arreglaría.
>
> **Y el arreglo barato sigue siendo el peor**, por la razón del hallazgo del
> 2026-09-08, ahora con un caso concreto: meter el botón en un `TimelineView`
> haría que el hilo principal leyera `transport.isPlaying` —o sea
> `scheduler?.isRunning`— cuatro veces por segundo, mientras el hilo de
> recepción reescribe `scheduler` en cada Start y cada Stop. La carrera se
> agrava justo donde duele.
>
> **Efecto sobre los requisitos.** FR4, FR9 y FR10 quedan **satisfechos por lo
> que ya hay** y salen del alcance de implementación; se conservan escritos
> porque siguen siendo criterios de aceptación y hay que verificarlos sin
> regresión. FR1, FR2, FR3, FR8, FR11 y todos los NFR siguen en pie: son el
> track.
>
> **Por qué no se implementa FR4 igualmente.** Incrementar `clockRevision` una
> vez por negra invalidaría el modelo observable entero —dos veces por segundo a
> 120 bpm— para refrescar un número que ya se refresca con un repintado local de
> una etiqueta. Sería trabajo nuevo y peor localizado que el que hay.

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

**FR4 — El tempo externo no lleva contador propio, y ese es el reparto.**
*(Ya satisfecho — ver la enmienda del 2026-09-09. Se verifica, no se implementa.)* El
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

**FR7 — Leer sin cambios cuesta lo mismo que hoy.** Una lectura atómica y una
comparación de enteros. Eso es lo que pasa en casi todos los cuadros.
*(La comparación de tempo que decía aquí se cae con FR4 — enmienda del
2026-09-09.)*

**FR8 — El botón de transporte enseña lo que suena.** Después de un Start del
BeatStep, el botón enseña *stop* y pulsarlo **para**. Es el síntoma reportado,
y es el criterio de aceptación que manda.

> **Ampliación del 2026-09-09, con el diagnóstico en la mano — el defecto es
> simétrico y arrastra el anillo.**
>
> Medido en dispositivo: en t=90 s el maestro paró, el contador de transiciones
> subió y `transport.isPlaying` pasó a `false`, mientras `model.isPlaying` se
> quedaba en `true`. **La copia no se entera de un Start ni de un Stop**, y este
> requisito solo describía el Start.
>
> **FR8b — El anillo se mueve cuando la secuencia suena.** El playhead se dibuja
> con `TimelineView(.animation(paused: !model.isPlaying))`
> (`ContentView.swift:369`), colgado de la misma copia: con un Start del maestro
> **el playhead no avanza aunque suene**. No estaba reportado —se descubrió al
> instrumentar— y lo arregla el mismo cambio, así que entra aquí en vez de abrir
> otro track. Se verifica en la Fase 4.
>
> **Por qué pulsar el botón no hacía nada** (la observación que lo destapó): con
> la copia en `false` el botón llama a `play()`, que llega a `Transport.play()` y
> muere en su `guard !isPlaying`. Ni para ni rearranca; solo sincroniza la copia
> a `true` de rebote. Es coherente con todo lo anterior y no es un defecto
> aparte.

**FR9 — La barra enseña el tempo del maestro.**
*(Ya satisfecho — ver la enmienda del 2026-09-09. Se verifica, no se implementa.)* Con reloj externo establecido, el
número de la barra sigue al maestro sin que nadie navegue a otra pantalla y
vuelva.

**FR10 — El estado del reloj también se refresca.**
*(Ya satisfecho — ver la enmienda del 2026-09-09. Se verifica, no se implementa.)* `clockStatus` y la marca
`EXT`/`INT` salen del mismo `Transport` y ya leen `clockRevision`: al
incrementarlo desde este camino, se refrescan sin tocar nada más. Incluye la
recuperación de un corte de reloj.

**FR11 — La pantalla puede ir hasta un cuadro por detrás.** Es el mismo límite
que la adopción declara, y por la misma razón: **lo que suena es exacto; lo que
se lee, no instantáneo**. Nadie lo oye.

## Non-Functional Requirements

**NFR1 — La publicación nueva solo escribe atómicos.** En la lógica de
publicación nueva que corre en el hilo de recepción no entra una asignación no
atómica, ni un lock, ni un `await`, ni una llamada hacia el modelo. Este alcance
excluye las llamadas que `Transport.receive` ya hace, como
`startPlaying(atHostTime:)`, `stop()` y `follow(tickAtHostTime:)`: se conserva su
comportamiento y este track no rediseña `Transport.receive`. Las funciones
nuevas llevan el marcador `/// Realtime:`.

**NFR2 — La carrera sobre `scheduler` no crece.** Este track no añade lecturas de
`scheduler` desde el hilo principal. Si el arreglo termina eliminando la que hay
—porque el flag de FR2 sirva para responder `isPlaying`—, se anota y se prueba;
si no, se deja escrito como límite conocido con su ruta de arreglo.

> **Resuelto el 2026-09-09, en la Fase 1: se elimina.** El flag de FR2 puede
> responder `isPlaying`, así que `Transport.isPlaying` pasa a leer el atómico y
> el hilo principal deja de tocar `scheduler` por ese camino. La rama «se deja
> como límite conocido» no se toma.
>
> **Lo que queda después**, escrito para que no se dé por resuelto de más: el
> hilo de recepción sigue escribiendo `scheduler` en `startPlaying(atHostTime:)`
> y en `stop()`. Lo que desaparece es el **lector** concurrente del hilo
> principal. Si algún día se quiere cerrar del todo, la ruta es hacer que la
> referencia viaje por un atómico o que el ciclo de vida del hilo deje de
> reasignarla — y eso sí es un track propio, no un arreglo de paso.

**NFR3 — Cobertura.** `MIDI` ≥80%. El contador, el flag y su relación con
`receive` viven ahí.

**NFR4 — El cableado en `App` no lleva tests, y por eso es poca cosa.** `App` no
se mide (`workflow.md`). La comparación de FR4 y la lectura de FR6 tienen que ser
directas: si aparece una decisión, baja a `MIDI`.

**NFR5 — Sin medición de jitter.** La suspensión del 2026-09-02 manda, y este
cambio no mueve ningún instante. Lo que **sí** se comprueba es el coste por tick
—FR5, FR7—, que es otra cosa y se mide contando, no cronometrando.

> **Contado el 2026-09-09**, 220 s con reloj externo a 124 bpm: **50,4 ticks/s**
> medidos, ~49,6/s una vez corregida la deriva del cronómetro —que es 124 × 24 /
> 60 exacto—, y **4 transiciones** en todo el tramo. Avisar por tick habrían sido
> ~11.000 invalidaciones; por transición son 4. FR5 queda decidido con datos.

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

## Lo que se corrigió al implementar

> **Nota del 2026-09-10, al cerrar.** Tres cosas cambiaron respecto a lo que
> este documento decía el 2026-09-08. Se dejan escritas porque el valor de un
> spec está en que se pueda comparar con lo que pasó.
>
> **1. El segundo síntoma ya estaba resuelto** (enmienda del 2026-09-09, arriba).
> El tempo del maestro sí llegaba a la barra, y lo resolvía un `TimelineView` que
> ya existía. FR4 pasó de implementarse a verificarse, y con él se cayó una tarea
> entera de la Fase 3. **Se descubrió preguntando**, no midiendo: el usuario lo
> dijo al leer el diagnóstico.
>
> **2. El defecto era simétrico, y aquí solo estaba escrita la mitad.** La copia
> tampoco se enteraba de un Stop del maestro. Se encontró **contando** en la
> Fase 1: en t=90 s de la pasada de diagnóstico el maestro paró,
> `transport.isPlaying` pasó a `false` y `model.isPlaying` se quedó en `true`.
>
> **3. Había un tercer síntoma que nadie había reportado: el anillo.** El
> playhead cuelga de la misma copia, así que con un Start del maestro no avanzaba
> aunque la secuencia sonara. Entró como FR8b y lo arregló el mismo cambio.
>
> **La forma del arreglo no cambió.** Es la que
> `control-input-adoption_20260908` ya había encontrado: contador atómico escrito
> en el hilo de tiempo real, leído desde el `.task` de 16 ms. Eso se planificó
> bien y se implementó tal cual.
>
> **Lo que sí se ganó de más:** NFR2 se resolvió eliminando la lectura, no
> dejándola como límite conocido, y se adelantó a la Fase 2 — así la carrera se
> quedó sin lector aunque la Fase 3 no hubiera llegado.

## Known Limitations

- **Hasta un cuadro de retraso** entre el gesto del hardware y la pantalla
  (FR11).
- **Si la app no está dibujando, no se entera hasta que vuelva.** El sonido no
  depende de ello, igual que en la adopción.
- **El tempo se compara redondeado**, así que un cambio del maestro por debajo de
  la décima no refresca. Es lo que ya se ve en pantalla. *(Lo hace el
  `TimelineView` de la barra, no este track — enmienda del 2026-09-09.)*
- **La escritura de `scheduler` desde el hilo de recepción sigue ahí.** Lo que
  este track elimina es el **lector** del hilo principal. Cerrarla del todo
  exigiría que la referencia viajara por un atómico o que el hilo dejara de
  reasignarse, y eso es un track propio (NFR2).
