# Plan — `ControlInput` no adopta el Pattern del Bank nuevo

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de dentro afuera, y de lo barato a lo caro.** Primero la vía de ida
en `ControlInput`, que es donde está el fallo que se reportó y donde hay tests;
después el cableado de los tres caminos parados, que ya lo arregla del todo para
el transporte parado; después la vía de vuelta desde el hilo del scheduler, que
es la mitad cara y la que absorbe el defecto hermano; y por último el dispositivo.

**La Fase 3 es la que tiene el riesgo**, no la 1. Tocar el hilo del scheduler
—aunque sea para escribir un contador— es tocar el camino que la v1 existió para
proteger. La forma está copiada de `CyclePlaybackClock`, que ya resolvió este
mismo problema, y eso es lo que la hace defendible.

**Cada fase deja el producto mejor que como lo encontró.** Al cerrar la Fase 2 el
fallo reportado está arreglado para el transporte parado, aunque la 3 no llegue a
existir. Es lo que permite parar entre fases sin dejar nada a medias.

**Sin medición de jitter** (NFR4): este cambio no mueve ningún instante, cambia
quién conoce el material.

## FASE 1: LA VÍA DE IDA — `ControlInput` ADOPTA [checkpoint: ac078df]

- [x] Task: `ControlInput` adopta un Pattern entero (FR1, FR2, FR3, FR4) `da357ba`
  - [x] Tests (Red): adoptar sustituye los doce Tracks —Shape, pool, Groove,
        canal, marco tonal y registro de pads— por los del Pattern nuevo.
  - [x] Tests (Red): **el Track seleccionado se conserva**, y con él a quién
        escuchan los knobs y los pads.
  - [x] Tests (Red): **el marco tonal no se re-siembra**: cada Cycle conserva el
        que traía el Pattern adoptado, y no el que se le pasó al `init`.
  - [x] Tests (Red): **adoptar no publica**. El cierre de publicación no se llama
        ni una vez.
  - [x] Tests (Red): después de adoptar, un giro de knob edita el material nuevo
        — que es el fallo reportado, escrito como test.
  - [x] Implementación (Green): la vía pública, junto a `setFrame` y
        `setActiveCycleCount`, que son las otras entradas que no vienen del
        controlador.
- [x] Task: Los modificadores se cancelan al adoptar (FR5) `ac078df`
  - [x] Tests (Red): con Temp hundido, adoptar y soltar **no escribe nada**; el
        Pattern queda como lo dejó la adopción.
  - [x] Tests (Red): lo mismo con Ctrl All, incluido el caso de haber girado
        contra el tope antes de adoptar.
  - [x] Tests (Red): el modificador **sigue hundido** a efectos del gesto
        siguiente: soltar no es lo que lo cancela, adoptar sí.
  - [x] Implementación (Green): descartar `overlay` y `ctrlAll` sin restaurarlos.
  - [x] Documentar por qué no se restauran sobre el Pattern nuevo: los valores
        capturados son de otro material, y escribirlos ahí es la destrucción que
        este track existe para impedir.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL CABLEADO CON EL TRANSPORTE PARADO [checkpoint: 7274945]

- [x] Task: Los tres caminos adoptan (FR6, NFR3) `7274945`
  - [x] `selectBank`, `selectPattern` y `reloadBank` llaman a la vía de la Fase 1
        en su rama parada, **una línea cada uno y sin lógica**.
  - [x] Comprobar que la rama que suena **no** adopta todavía: hasta la Fase 3,
        con el transporte corriendo el material entra en el compás y el modelo no
        se entera.
  - [x] Revisar que no queda ningún otro sitio que cambie el material del modelo
        sin avisar — si aparece uno, entra aquí.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: LA VÍA DE VUELTA — EL SCHEDULER DICE QUE ADOPTÓ [checkpoint: d0af03d]

- [x] Task: La palabra atómica de la adopción (FR7, NFR1) `e99ba9e`
  - [x] Tests (Red): el contador arranca en cero y **se mueve exactamente una vez
        por adopción**, no una por ventana.
  - [x] Tests (Red): armar sin que llegue el compás **no** lo mueve; armar dos
        veces y adoptar una lo mueve una vez.
  - [x] Tests (Red): la lectura desde otro hilo no rompe nada — mismo test de
        concurrencia que tiene `CyclePlaybackClock`.
  - [x] Implementación (Green): un `AtomicCounter`, con la forma de
        `CyclePlaybackClock`: sin locks, sin asignaciones, escrito solo en el
        límite de compás.
  - [x] Comprobar que **no cambia el coste por ventana**: la escritura ocurre en
        la adopción, que ya era un camino excepcional.
- [x] Task: El modelo aplica lo que armó (FR8, FR10) `d0af03d`
  - [x] Tests (Red): con una adopción publicada, el modelo mueve
        `project.selectedPattern` al hueco que armó y **limpia
        `armedPatternIndex`**.
  - [x] Tests (Red): y **adopta en `ControlInput`**, así que el siguiente giro de
        knob escribe en el hueco nuevo — la consecuencia que destruía trabajo.
  - [x] Tests (Red): sin adopción pendiente, leer el contador no cambia nada.
  - [x] Implementación (Green): lo que se recuerda al armar y lo que se aplica al
        ver el contador moverse. La decisión vive donde haya tests, no en `App`.
- [x] Task: La pantalla lo consulta al dibujar (FR9, NFR3) `d0af03d`
  - [x] El mismo criterio que `playhead` y `cycleInCourse`: se consulta al
        dibujar, sin callback desde el hilo de tiempo real.
  - [x] Dejar escrito el límite: lo que suena es exacto; lo que la pantalla
        refleja puede llegar hasta un cuadro después.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: DISPOSITIVO Y CIERRE

- [~] Task: Verificación en iPad con BeatStep Pro
  - [ ] **El fallo reportado, primero**: cambiar de Bank —incluido uno vacío— y
        girar un knob. El Pattern anterior no vuelve.
  - [ ] `selectPattern` y `reloadBank` con el transporte parado.
  - [ ] **Con el transporte corriendo**: cambiar de Pattern, oír que entra en el
        compás, y ver que la cuenta atrás desaparece y la rejilla marca el hueco
        correcto. Girar un knob y comprobar que escribe **en ese hueco**.
  - [ ] Temp y Ctrl All hundidos durante un cambio de Bank: soltar no escribe
        nada del Pattern viejo.
  - [ ] Escribir `device-verification.md` con lo que se probó y lo que falló.
- [ ] Task: Cobertura y suite completa
  - [ ] `Engine` ≥90%, `MIDI` ≥80% medida en un proceso e ignorando
        `Engine/Sources`, como dice `workflow.md`.
- [ ] Task: Pull Request
  - [ ] Rama `fix/control-input-adoption`, PR contra `main`. Cuerpo corto.
- [ ] Task: Cerrar los dos defectos en el registro
  - [ ] Marcar este track **y el defecto hermano** —«El cambio de Pattern no
        llega a la pantalla ni al Project»—, que este track absorbe.
  - [ ] Anotar en el `spec.md` lo que se haya corregido al implementar, con
        fecha.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
