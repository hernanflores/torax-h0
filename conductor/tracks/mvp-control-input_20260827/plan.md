# Plan — MVP rebanada 2: Entrada de control

**Track ID:** `mvp-control-input_20260827`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** el motor primero, otra vez, porque el cambio de `Pulses` toca código ya entregado en la rebanada 1 y conviene estabilizarlo antes de construir encima. Luego la cadena completa mensaje→Track de forma determinista, y solo al final la plataforma y el dispositivo.

## Phase 1: El modelo de Pulses en `Engine` [checkpoint: e2fb8ea]

- [x] Task: `Pulses` se valida por sí solo — `709b40b`
  - [x] Tests (Red): `Pulses` acepta 1–16 sin conocer Steps; rechaza 0, negativos y mayores que 16
  - [x] Tests (Red): los casos de la Pre Spec (16/4, 16/5, 12/7) siguen dando el mismo patrón
  - [x] Implementación (Green): `init?(_:)` sustituye a `init?(_:in:)`
  - [x] Actualizar los tests de la rebanada 1 que asumen el inicializador acoplado
- [x] Task: Acotado no destructivo en el reparto — `48e9a5f`
  - [x] Tests (Red): `Steps 4` con `Pulses 9` reparte 4 pulsos y **conserva** el 9
  - [x] Tests (Red): subir Steps restaura el reparto original — ida y vuelta sin pérdida
  - [x] Tests (Red): invariante exhaustiva — `effectivePulses == min(pulses, steps)` para toda combinación
  - [x] Implementación (Green): `EuclideanRhythm` reparte `min(pulses, steps)`; `Shape.effectivePulses`
  - [x] Documentar la desviación de la Pre Spec con nota fechada (`workflow.md` paso 8)
- [x] Task: Lista ordenada de Divisions — `e2fb8ea`
  - [x] Tests (Red): recorrer hacia arriba y hacia abajo se detiene en los extremos, no envuelve
  - [x] Implementación (Green): secuencia de valores musicales, no un entero libre
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Del mensaje MIDI al Track publicado [checkpoint: 3251d76]

> Toda esta fase se testea sin CoreMIDI y sin hardware.

- [x] Task: Decodificación de encoders relativos — `c5f8923`
  - [x] Tests (Red): complemento a dos — `0x01`→+1, `0x3F`→+63, `0x7F`→−1, `0x41`→−63
  - [x] Tests (Red): `0x00` y `0x40` no producen movimiento
  - [x] Tests (Red): determinismo — mismo mensaje, mismo delta
  - [x] Implementación (Green): la convención entra como parámetro, no cableada
- [x] Task: Mapeo de CC a parámetro de Shape — `10a9eb6`
  - [x] Tests (Red): un CC mapeado mueve su parámetro y **solo** el suyo
  - [x] Tests (Red): un CC sin mapear se ignora en silencio, no es error
  - [x] Implementación (Green): tabla fija, **declarada provisional** en el código
- [x] Task: Aplicar el delta y publicar — `590c8d0`
  - [x] Tests (Red): girar Pulses publica un `Track` nuevo, recogido en la ventana siguiente
  - [x] Tests (Red): bajar Steps acota sin destruir; subirlo restaura — de extremo a extremo desde el mensaje
  - [x] Tests (Red): los extremos de rango no desbordan ni envuelven donde no deben
  - [x] Implementación (Green): publicación por `TrackHandoff`, sin tocar el camino de tiempo real
  - [x] Revisión explícita: decodificar y publicar corren en el hilo de control, nunca en el del scheduler
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Entrada MIDI real y controlador virtual [checkpoint: 06470b2]

- [x] Task: Fuentes de entrada y selección — `2d7b155`
  - [x] Tests (Red): la lista refleja las fuentes del sistema; sin fuentes es un estado válido
  - [x] Tests (Red): `onSetupChanged` provoca reconsulta
  - [x] Implementación (Green): estado `No MIDI input`, sin lenguaje de error ni disculpa
  - [x] Reutilizar la lógica de selección de la salida en lugar de duplicarla
- [x] Task: Recepción por CoreMIDI — `45d7783`
  - [x] Implementación (Green): puerto de entrada y conexión a la fuente elegida
  - [x] Cierre explícito y ordenado desde el principio — no repetir el problema de `scheduler-lifecycle`
  - [x] Medir la tasa de `-50`/`-2` antes y después: este track añade un segundo cliente de CoreMIDI — **0 de 6 antes, 0 de 6 después**
- [x] Task: Controlador virtual de desarrollo — `06470b2`
  - [x] Tests (Red): inyectar un giro produce el mismo efecto que un CC real
  - [x] Implementación (Green): inyector de eventos relativos, sin CoreMIDI
  - [x] **Verificar que el binario de Release no lo contiene** — hecho en la Fase 4 sobre el binario de la app: `CoreMIDIInput` 129 símbolos, `ControlInput` 81, `VirtualController` **0**.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Integración y verificación en dispositivo [checkpoint: f442bfb]

- [x] Task: Cablear en la app — `f442bfb`
  - [x] Selección de fuente en la pantalla, junto a la de destino
  - [x] El texto de Shape se actualiza al girar
  - [x] Sin controlador conectado, la app sigue siendo de solo lectura y transporte
- [x] Task: Verificación en iPad — verificada el 2026-08-28 sobre iPad Air (4ª gen)
  - [x] Girar Pulses cambia el patrón audible **en el Step siguiente**
  - [x] Bajar Steps por debajo de Pulses y volver a subir: nada se pierde
  - [~] Desconectar el controlador a media sesión se refleja como estado — no cae ni da error, pero el estado que se muestra es el equivocado. Ver abajo.
  - [x] Verificar que el transporte sigue funcionando sin controlador
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

### Lo que la verificación en dispositivo encontró

**1. Los encoders tienen que estar en `Relative #2`.** Con el BeatStep Pro en
otro modo relativo, un solo clic se decodifica como un delta de ±63 y Steps,
Pulses y Division saltan a su extremo — 1 o 16, sin valores intermedios. Rotate
parecía sano por ser el único que envuelve módulo Steps en vez de acotar, lo que
lo convierte en el peor testigo de los cuatro. **No es un defecto:**
`RelativeEncoding` decodifica complemento a dos y lo declara; lo que faltaba era
decir en algún sitio que el controlador tiene que hablarlo. Anotado en
`workflow.md` → *Device Testing*. Los demás modos entran con el preset del
BeatStep Pro, que es un track posterior.

**2. `Red Session 1` monopoliza la entrada — defecto real, fuera de este track.**
iPadOS publica siempre la sesión MIDI de red como fuente, así que la lista nunca
está vacía: se autoselecciona, `No MIDI input` y el indicador `read-only` son
inalcanzables en el dispositivo de destino, y al conectar el BeatStep Pro hay
que elegir la fuente a mano. El criterio *«sin controlador conectado, la app
sigue siendo de solo lectura y transporte»* se cumple **en comportamiento** —no
llegan giros y no hay vía táctil para suplirlos— pero no en lo que la pantalla
dice. Registrado como
[`network-session-source_20260828`](../network-session-source_20260828/index.md),
que no bloquea a nadie ni depende de la cadena de CoreMIDI.

## Notas de riesgo

- **La Fase 1 toca código ya entregado.** Cambiar `Pulses` reescribe el inicializador que usan `Shape`, `EuclideanRhythm` y cuatro ficheros de test de la rebanada 1. Las invariantes exhaustivas existentes —conservación de Pulses, primer Step siempre dispara— son la red que debe seguir en verde.
- **La entrada añade un segundo cliente de CoreMIDI al proceso.** Ese es exactamente el recurso implicado en `clientCreationFailed(-2)` y `(-50)`, y este track lo duplica. **Es razonable esperar que la CI empeore**, así que se mide la tasa antes y después en lugar de descubrirlo en el PR, como pasó en la rebanada 1.
- **La exclusión del controlador virtual en Release es la misma clase de problema que `UIBackgroundModes`**, que ya costó un descubrimiento tardío: compila igual y solo se nota en el binario. Se verifica sobre el producto final, no por inspección del código.
