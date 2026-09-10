# Track: La pantalla no ve lo que cambia el hardware

**ID:** `hardware-screen-sync_20260908` · **Type:** Bug · **Status:** complete

El estado del transporte y del reloj vive en `Transport`, que no es observable, y
**nadie incrementa `clockRevision` desde el hilo de recepción de CoreMIDI**. Un
cambio que venga del controlador no invalida la pantalla.

Dos síntomas confirmados en dispositivo el 2026-09-06:

- **El botón de transporte no se entera de un Start del BeatStep.** La secuencia
  suena y el botón sigue enseñando *play*; pulsarlo llama a `play()` otra vez en
  vez de parar, así que **parece** que la app tiene precedencia sobre el
  controlador. No la tiene: `Transport.receive` da el mando al maestro desde el
  2026-09-03 y `ExternalStartTests` lo cubre. Lo que falla es que la app no se
  entera.
- **El tempo de un maestro externo no refresca la barra**, por lo mismo.

**La forma del arreglo ya está encontrada, y no es nueva.** Es la misma que
`control-input-adoption_20260908` usó para la adopción: el hilo de tiempo real
solo incrementa una palabra atómica, y la app la lee desde el `.task` de 16 ms
que ya existe en `ToraxH0App`. Ni callbacks desde el hilo de recepción, ni
temporizadores colgados de vistas.

**Lo que este defecto ya enseñó.** Se intentó arreglar de paso dentro de la
Fase 4 de `screens-redesign_20260906`, y los tres intentos dejaron la app peor:
dos sin atender el MIDI entrante, y el último colgó un temporizador de un `.task`
en una vista que la propia invalidación recreaba, así que se multiplicaban y
saturaban el hilo principal — el mismo al que la entrada de control salta para
publicar un giro. Se revirtió todo.

**La lección de método:** los síntomas viven en el hilo de recepción de CoreMIDI
y en el hardware, y el simulador no tiene ninguno de los dos. Un cambio en esa
zona **no se valida con una captura ni con un porcentaje de CPU**.

**Sin medición de jitter**: no mueve ningún instante. Sí lleva una comprobación
de coste por tick, que es otra cosa y está en la Fase 1.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [`ControlInput` no adopta el Pattern del Bank nuevo](../control-input-adoption_20260908/index.md):
    de ahí sale la forma entera —contador atómico escrito en el hilo de tiempo
    real, leído desde el `.task` de 16 ms de la app— y el `.task` donde esto se
    engancha.
-   [Sincronía de reloj externo](../external-clock_20260903/index.md): trajo
    `Transport.receive`, el `ClockFollower` y la decisión de que el maestro manda
    el transporte. Este track hace que se vea.
-   [Rediseño de las cuatro pantallas](../screens-redesign_20260906/index.md):
    donde se descubrió y donde tres intentos de arreglarlo de paso se
    revirtieron.
