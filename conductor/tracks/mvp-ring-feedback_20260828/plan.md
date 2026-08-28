# Plan — MVP rebanada 3: Anillo, playhead y valor transitorio

**Track ID:** `mvp-ring-feedback_20260828`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** lo testeable primero. La geometría y el camino de vuelta del playhead son las dos piezas con lógica, y las dos viven fuera de `App`; la vista se escribe cuando ya tiene qué dibujar. Deja para el final lo único que exige iPad, que es también lo que decide la rebanada: el jitter con carga visual.

## Phase 1: La geometría vive en `Engine`

> `workflow.md`: si algo en `App` merece un test, está en el sitio equivocado.
> Toda esta fase se testea sin simulador, sin hardware y sin dibujar nada.

- [x] Task: Posiciones del anillo — `4d45046`
  - [x] Tests (Red): un anillo de N Steps produce N posiciones, repartidas por igual sobre la vuelta completa
  - [x] Tests (Red): el Step 0 está en una posición fija y conocida, para que el anillo no gire solo al cambiar Steps
  - [x] Tests (Red): cambiar Steps redistribuye sin dejar huecos ni solapes
  - [x] Implementación (Green): la posición se expresa en fracción de vuelta, no en píxeles ni en radianes — `App` decide cómo se dibuja
- [x] Task: Qué posiciones llevan Pulse — `4d45046`
  - [x] Tests (Red): los casos de la Pre Spec (16/4, 16/5, 12/7) marcan exactamente las posiciones que ya cubre `EuclideanRhythm`
  - [x] Tests (Red): `Rotate` desplaza las marcas de forma coherente con el gesto, no reordena el patrón en el sitio
  - [x] Tests (Red): con `Pulses > Steps` se marcan `effectivePulses`, sin destruir el valor — la invariante de la rebanada 2 sigue en pie
  - [x] Implementación (Green): se reutiliza `EuclideanRhythm`, no se recalcula el reparto

  > Las dos tareas comparten SHA: son un solo tipo, y partirlo habría exigido publicar un `Ring` sin `isPulse` que ningún llamante puede usar.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: El camino de vuelta del playhead

> La dirección que falta. `TrackHandoff` publica del control al scheduler; aquí
> el scheduler publica a la interfaz, y **sin pagar nada por ello**.

- [ ] Task: Posición publicada sin coste en tiempo real
  - [ ] Tests (Red): la posición leída corresponde al último Step emitido
  - [ ] Tests (Red): no leer durante un rato no atrasa al scheduler ni le hace perder Steps
  - [ ] Tests (Red): con el transporte parado la posición no avanza
  - [ ] Implementación (Green): un valor que el scheduler escribe sin bloquearse y la interfaz lee sin bloquearlo — mismas reglas que `TrackHandoff`, dirección contraria
  - [ ] Marcador `/// Realtime:` en lo que corra en el hilo del scheduler
  - [ ] **Revisión explícita registrada:** sin asignaciones, sin locks, sin `await`, sin logging en el camino del scheduler (`NFR1`)
- [ ] Task: La interfaz lee al ritmo del refresco
  - [ ] Tests (Red): el modelo expone la posición sin exigir que la vista conozca el scheduler
  - [ ] Implementación (Green): lectura derivada del transporte; parado significa quieto (`FR2`)
  - [ ] Sin temporizador propio de la interfaz que no venga del reloj musical (`NFR6`)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: La pantalla

> Aquí ya no hay lógica que testear: `App` recibe fracciones de vuelta y las
> dibuja. Lo que se verifica es que no se coló lógica dentro.

- [ ] Task: El anillo y sus Pulses
  - [ ] Implementación: círculo de posiciones con las marcadas destacadas, sobre fondo oscuro y alto contraste
  - [ ] Steps, Pulses y Rotate movidos por knob se ven al instante
  - [ ] Revisión: la vista no calcula geometría, solo la dibuja (`NFR3`)
- [ ] Task: El playhead
  - [ ] Implementación: marca que recorre el anillo derivada del transporte
  - [ ] Parado no se mueve; ninguna animación que no comunique tiempo musical
- [ ] Task: Valor grande transitorio
  - [ ] Implementación: el valor aparece en grande al girar y se desvanece por inactividad
  - [ ] **El anillo permanece visible bajo él y nunca se oculta** (`FR4`)
  - [ ] Tipografía muy grande y jerarquía marcada: el criterio es un metro, no el gusto
- [ ] Task: Acento de familia y estado heredado
  - [ ] Implementación: el acento de Shape se declara como token en un solo sitio, listo para que Tonal y Groove añadan el suyo
  - [ ] Transporte, destino, fuente y solo lectura siguen visibles y operativos (`FR6`)
  - [ ] Sin controlador, anillo y playhead siguen funcionando (`FR7`)
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Verificación en dispositivo

> La fase que decide la rebanada. Las tres anteriores pueden estar impecables y
> esta invalidarlas.

- [ ] Task: Jitter con carga visual — **requiere iPad**
  - [ ] Medir con el anillo y el playhead dibujándose, en los tres tempos del arnés
  - [ ] Comparar contra la referencia de la rebanada 1: máx 0,127 ms · σ 0,015 ms
  - [ ] **Registrar el número en la git note, cumpla o no.** Es la deuda que `product.md` dejó abierta
  - [ ] Si σ se degrada, diagnosticar antes de ajustar: el sospechoso es la frecuencia de redibujado, no el scheduler
- [ ] Task: Verificación de uso — **requiere iPad y controlador**
  - [ ] El playhead va con lo que se oye: sin desfase de un Step
  - [ ] Girar Pulses cambia el anillo y muestra el valor grande sin ocultarlo
  - [ ] Rotate se lee como una rotación, no como otro patrón
  - [ ] Legibilidad a un metro: playhead, pulsos activos y valor transitorio (`NFR5`)
  - [ ] Sin controlador: anillo y playhead siguen; el overlay no se dispara
- [ ] Task: Verificar cobertura — `Engine` ≥90%, `MIDI` ≥80%
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La Fase 4 puede invalidar a las tres anteriores.** `product.md` dejó dicho
  que la σ sube con el tempo y que faltaba medir con el anillo. Si el redibujado
  degrada el timing, el arreglo es la interfaz —bajar la frecuencia de
  refresco del playhead, dibujar menos por posición—, **nunca tocar el
  scheduler**. El criterio principal del producto es el timing, no la fluidez de
  la animación.
- **El camino de vuelta del playhead es tiempo real por el lado que escribe.**
  Es la primera vez que el hilo del scheduler publica algo hacia fuera. La
  tentación de resolverlo con un lock o con una notificación a la interfaz desde
  ese hilo es exactamente el error que `NFR1` prohíbe.
- **El overlay tiene un antipatrón declarado a un paso.** «Nunca se sustituye el
  contexto por el detalle»: un overlay a pantalla completa que tape el anillo
  cumpliría FR4 leído a la ligera y violaría la guía. El anillo no se oculta.
- **El handoff describe una pantalla más rica de la que corresponde.** Pestañas
  de familia, selector de Track y anillos concéntricos asumen material que no
  existe. Implementarlos vacíos sería construir chrome sin función y habría que
  desmontarlo.
