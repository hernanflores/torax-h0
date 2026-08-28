# Plan — MVP rebanada 3: Anillo, playhead y valor transitorio

**Track ID:** `mvp-ring-feedback_20260828`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** lo testeable primero. La geometría y el camino de vuelta del playhead son las dos piezas con lógica, y las dos viven fuera de `App`; la vista se escribe cuando ya tiene qué dibujar. Deja para el final lo único que exige iPad, que es también lo que decide la rebanada: el jitter con carga visual.

## Phase 1: La geometría vive en `Engine` [checkpoint: 4d45046]

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
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

  > Validación visual **diferida a las Fases 3 y 4** por decisión del usuario: esta fase no toca `App/`. El checkpoint da por buena la geometría y sus invariantes, no cómo se ve dibujada.

## Phase 2: El camino de vuelta del playhead [checkpoint: 03c62a9]

> La dirección que falta. `TrackHandoff` publica del control al scheduler; aquí
> el scheduler publica a la interfaz, y **sin pagar nada por ello**.

- [x] Task: Posición publicada sin coste en tiempo real — `e7e1919`
  - [~] Tests (Red): ~~la posición leída corresponde al último Step emitido~~ → **el tiempo transcurrido se mide contra el origen**. Ver la desviación abajo.
  - [x] Tests (Red): no leer durante un rato no atrasa al scheduler ni le hace perder Steps
  - [x] Tests (Red): con el transporte parado la posición no avanza
  - [x] Implementación (Green): un solo atómico con el origen en ticks de host — no hizo falta el anillo de ranuras de `TrackHandoff`
  - [x] Marcador `/// Realtime:` en lo que corra en el hilo del scheduler
  - [x] **Revisión explícita registrada:** el bucle solo gana una escritura atómica antes de entrar; dentro no cambia nada. Sin asignaciones, sin locks, sin `await`, sin logging (`NFR1`)
- [x] Task: La interfaz lee al ritmo del refresco — `03c62a9`
  - [x] Implementación (Green): `Transport.playhead` resuelve contra su reloj; el modelo lo ofrece junto al anillo sin que la vista sepa que hay un scheduler
  - [x] Parado significa quieto (`FR2`): el reloj se limpia en `stop()`, desde el hilo de control
  - [x] Sin temporizador propio de la interfaz que no venga del reloj musical (`NFR6`): el playhead se calcula al preguntar, no se guarda ni se observa

### Desviación: se publica el origen, no el Step entregado

El plan pedía «la posición leída corresponde al último Step emitido». **No sirve
y se cambió a propósito.** El scheduler entrega los Steps hasta una ventana de
look-ahead *antes* de que suenen, así que el último entregado va por delante de
lo que se oye — el desfase que `FR2` prohíbe. Publicando el origen temporal, la
posición es la que suena por construcción, y de paso la fracción de vuelta sale
continua en vez de a saltos.

### Laguna de test conocida, medida el 2026-08-28

**Que el bucle publique su propio origen no tiene test automático.** Verificarlo
exige arrancar el bucle del scheduler dentro de la suite, y hacerlo lleva
`VirtualLoopbackTests` de fallar intermitentemente a fallar **3 de 3 pasadas**
con `clientCreationFailed(-50)`, contra **0 de 4** en `main`.

Descartado que sea evitable: no es el número de tests —fusionar dos en uno da
igual— ni la prioridad del hilo —correr el bucle a prioridad normal da igual—.
Es que la suite arranque el bucle una vez más.

La CI queda verde: su partición corre los tests de CoreMIDI primero y en su
propio proceso, 0 de 3 en ambas mitades. Lo que se rompe es el run en un solo
proceso, que es el que `workflow.md` exige para medir la cobertura de `MIDI`.

La causa pertenece a [`midi-test-flake_20260826`](../midi-test-flake_20260826/index.md),
**que pasa a ser bloqueante cuatro rebanadas antes de lo previsto**. Hasta
entonces, esa línea se verifica en dispositivo en la Fase 4: el playhead va con
lo que suena, o no va.

- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

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
