# Spec — `ControlInput` no adopta el Pattern del Bank nuevo

## Overview

**Cambiar de Bank suena, pero no se edita.** `ControlInput` guarda su propia
copia del Pattern y **solo la escribe en su `init`**; las demás escrituras son
ediciones incrementales —un giro, un pad, un canal—. Nadie la reseedea. Así que
después de cambiar de Bank el primer giro de knob republica **el Pattern anterior
entero** encima del Bank nuevo: Steps, Pulses, Rotate, el pool, el Groove y el
marco tonal.

Se descubrió el 2026-09-07 verificando `note-repeater_20260906` en dispositivo,
porque un ratchet sobre un Bank que se creía vacío es inconfundible. El resto
pasaba por «no cambió nada».

**Este track absorbe el defecto hermano** —«El cambio de Pattern no llega a la
pantalla ni al Project»— porque comparten la pieza que falta. Con el transporte
corriendo, cambiar de Bank o de Pattern **arma** y el material entra en el límite
de compás, dentro del hilo del scheduler (`Transport.select` → `armForNextBar`).
Arreglar solo la rama parada dejaría el mismo fallo esperando en la rama que suena,
y esa rama es exactamente la que el otro defecto describe.

**Dos direcciones, no una.** Falta la vía de **ida** —el modelo diciéndole a
`ControlInput` que el material cambió— y la de **vuelta** —el hilo del scheduler
diciéndole al modelo que la adopción ocurrió—.

## Functional Requirements

**FR1 — `ControlInput` adopta un Pattern entero.** Una vía pública que sustituye
su copia del Pattern por otra. Es lo único que hoy no existe.

**FR2 — Lo que es del material se sustituye; lo que es del dedo se conserva.**
Al adoptar:

- **Se sustituye** el Pattern entero: los doce Tracks con sus Cycles, pools,
  Grooves, canales, marcos tonales y registros de pads. Todo eso viaja en el
  `Pattern` y es material.
- **Se conserva el Track seleccionado.** Qué Track editas es del dedo, no del
  material: cambiar de Bank para seguir tocando el mismo Track es el gesto normal
  en directo.

**FR3 — El marco tonal no se re-siembra.** El `init` reparte un `TonalFrame` a
los doce Tracks porque nace sin material; un Pattern que viene de disco trae el
suyo por Cycle, y pisarlo sería destruir material — lo que
`product-guidelines.md` prohíbe.

**FR4 — Adoptar no publica.** Quien provoca el cambio ya avisa al transporte
—`selectBank`, `selectPattern` y `reloadBank` lo hacen—. Que `ControlInput`
publicara además dejaría dos publicaciones por cambio y una carrera por cuál
gana.

**FR5 — Temp y Ctrl All se cancelan sin restaurar.** Si hay un modificador
hundido al adoptar, el overlay y el desplazamiento capturados **se descartan**:
pertenecían a un Pattern que ya no está. Soltar el botón después no escribe nada.
Restaurarlos sobre el Pattern nuevo escribiría valores de otro material, que es
la destrucción que este track existe para impedir.

**FR6 — Los tres caminos del modelo adoptan, con el transporte parado.**
`selectBank`, `selectPattern` y `reloadBank` llaman a la vía de FR1 cuando el
material entra en el acto.

**FR7 — El scheduler publica que adoptó.** Una palabra atómica que el hilo
escribe al adoptar un Pattern armado, por el mismo camino y con la misma forma
que `CyclePlaybackClock`: sin locks, sin asignaciones y sin callback hacia el
modelo. Es un **contador de generación**: lo que importa es que cambió, no su
valor.

**FR8 — El modelo la lee y aplica lo pendiente.** El scheduler no conoce índices
de Bank ni de Pattern —solo tiene el valor—, así que el modelo recuerda qué armó
y, al ver el contador moverse, aplica esa selección: mueve
`project.selectedPattern`, limpia `armedPatternIndex` y adopta en `ControlInput`.

**FR9 — Se lee al dibujar, no por callback.** Mismo criterio que `playhead` y
`cycleInCourse`: la pantalla ya consulta, y publicar hacia el modelo sería
trabajo en el camino de tiempo real. **Lo que suena entra exacto en el compás; lo
que la pantalla y el `Project` reflejan puede llegar hasta un cuadro después**, y
eso es aceptable porque nadie lo oye.

> **Nota del 2026-09-08 — se pregunta desde un bucle de la app, no desde el
> cuerpo de la vista.**
>
> FR9 decía «se lee al dibujar» por analogía con `playhead` y `cycleInCourse`, y
> la analogía se rompe en una cosa: aquellos **leen** y esto **escribe**. Aplicar
> la adopción mueve `project.selectedPattern`, limpia lo pendiente y adopta en
> `ControlInput`; hacerlo dentro del `TimelineView` sería invalidar la vista que
> SwiftUI está evaluando en ese momento.
>
> Se implementa como un `.task` de la app que pregunta cada 16 ms —el mismo
> orden que un cuadro— y llama a `applyPendingAdoption()`. **La propiedad que
> FR9 protege se cumple entera**: el hilo del scheduler no llama a nadie, solo
> incrementa una palabra atómica, y el límite declarado —hasta un cuadro de
> retraso en la pantalla y el `Project`— es el mismo.
>
> Sin nada pendiente el tick cuesta una lectura atómica y una comparación, que
> es lo que pasa en casi todos los cuadros.

**FR10 — Lo que el defecto hermano prometía queda cumplido.** Al adoptar en el
compás: la cuenta atrás desaparece, la rejilla de Patterns marca el que suena, y
**el siguiente giro de knob escribe en el hueco correcto** — que es la
consecuencia que destruye trabajo.

## Non-Functional Requirements

**NFR1 — Nada nuevo en el camino de tiempo real salvo una escritura atómica.** El
hilo del scheduler solo incrementa un contador al adoptar, que es lo que ya hace
`CyclePlaybackClock` en cada límite de vuelta.

**NFR2 — Cobertura.** `MIDI` ≥80%, `Engine` ≥90% si algo baja ahí. La vía de FR1
y la palabra de FR7 viven en `MIDI`, donde se testean.

**NFR3 — El cableado en `App` no lleva tests, y por eso es una línea.** `App` no
se mide (`workflow.md`). Los tres sitios de llamada de FR6 y la lectura de FR8
tienen que ser llamadas directas sin lógica: si aparece una decisión ahí, está en
el sitio equivocado y baja a `MIDI`.

**NFR4 — Sin medición de jitter.** La suspensión del 2026-09-02 manda, y además
este cambio **no mueve ningún instante**: cambia quién conoce el material, no
cuándo suena.

## Acceptance Criteria

1. Con el transporte **parado**, cambiar de Bank y girar un knob edita el Pattern
   del Bank nuevo. El anterior no vuelve.
2. Lo mismo con `selectPattern` y con `reloadBank`.
3. Cambiar a un Bank **sin material** y girar un knob no resucita el material del
   Bank anterior.
4. El Track seleccionado sobrevive al cambio; el marco tonal de cada Cycle es el
   del Pattern nuevo.
5. Con el transporte **corriendo**, cambiar de Pattern: suena en el compás, y en
   cuanto suena la cuenta atrás desaparece, la rejilla marca el hueco correcto y
   un giro de knob escribe **en ese hueco** y no en el anterior.
6. Con un Temp o un Ctrl All hundido, cambiar de Bank y soltar el modificador
   después **no escribe nada** del Pattern viejo.
7. `MIDI` ≥80%, y la suite entera verde.

## Out of Scope

- **Los mutes y el solo.** No viajan en el `Pattern` y hoy no se tocan al cambiar
  de Bank, ni para conservarlos ni para limpiarlos. Se deja escrito como límite
  conocido, sin cambiar comportamiento.
- **Que el cambio de Bank o de Pattern sea instantáneo con el transporte
  corriendo.** Sigue siendo cuantizado al compás, que es lo que la rebanada 4
  entregó a propósito.
- **Encadenar Patterns**, **Program Change** y **disparar Patterns desde el
  controlador**. Siguen fuera, como los dejó `persistence_20260907`.
- **Medición de jitter** (NFR4).

## Correcciones al implementar

> **Nota del 2026-09-08.** Lo que cambió respecto a lo escrito arriba, al
> implementarlo:
>
> - **FR9 se implementa como un poll de la app, no dentro del cuerpo de la
>   vista.** Ver la nota fechada en FR9: aplicar escribe en el modelo y
>   `playhead`/`cycleInCourse` solo leen. La propiedad que FR9 protege se cumple
>   entera.
> - **FR8 hizo falta un caso que la spec no nombraba**: armar encima de algo que
>   ya aterrizó sin haber mirado en medio. Suena el que entró en el compás, no el
>   que espera al siguiente, así que el aterrizaje se guarda en vez de perderse.
>   Hace falta pulsar dos Patterns dentro del mismo cuadro a caballo de un límite
>   de compás — poco probable, y por eso resuelto con un test en vez de confiando
>   en que no pase. Vive en `PendingAdoption`.
> - **Stop también mueve el contador**, porque `Transport.stop()` adopta lo
>   pendiente (FR10 de `persistence`). No estaba previsto y resulta ser lo
>   correcto: la pantalla refleja el Pattern que Stop dejó vigente.
> - Nada más. FR1–FR7 y FR10 quedaron como estaban escritos.

## Known Limitations

- **La pantalla puede ir hasta un cuadro por detrás del sonido** en el momento de
  la adopción (FR9). Lo que suena es exacto; lo que se lee, no instantáneo.
- **Si la app no está dibujando, la adopción no se aplica al modelo hasta que
  vuelva a dibujar.** El sonido no depende de ello.
- **Los mutes al cambiar de Bank quedan como estén**, por la decisión de arriba.
