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

## Phase 3: Entrada MIDI real y controlador virtual

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
  - [~] **Verificar que el binario de Release no lo contiene** — verificado sobre el paquete (release: 0 símbolos; debug: 131). Sobre el binario de la app queda **pendiente de la Fase 4**: hoy la comprobación es vacua porque nada lo referencia todavía.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 4: Integración y verificación en dispositivo

- [ ] Task: Cablear en la app
  - [ ] Selección de fuente en la pantalla, junto a la de destino
  - [ ] El texto de Shape se actualiza al girar
  - [ ] Sin controlador conectado, la app sigue siendo de solo lectura y transporte
- [ ] Task: Verificación en iPad
  - [ ] Girar Pulses cambia el patrón audible **en el Step siguiente**
  - [ ] Bajar Steps por debajo de Pulses y volver a subir: nada se pierde
  - [ ] Desconectar el controlador a media sesión se refleja como estado
  - [ ] Verificar que el transporte sigue funcionando sin controlador
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Notas de riesgo

- **La Fase 1 toca código ya entregado.** Cambiar `Pulses` reescribe el inicializador que usan `Shape`, `EuclideanRhythm` y cuatro ficheros de test de la rebanada 1. Las invariantes exhaustivas existentes —conservación de Pulses, primer Step siempre dispara— son la red que debe seguir en verde.
- **La entrada añade un segundo cliente de CoreMIDI al proceso.** Ese es exactamente el recurso implicado en `clientCreationFailed(-2)` y `(-50)`, y este track lo duplica. **Es razonable esperar que la CI empeore**, así que se mide la tasa antes y después en lugar de descubrirlo en el PR, como pasó en la rebanada 1.
- **La exclusión del controlador virtual en Release es la misma clase de problema que `UIBackgroundModes`**, que ya costó un descubrimiento tardío: compila igual y solo se nota en el binario. Se verifica sobre el producto final, no por inspección del código.
