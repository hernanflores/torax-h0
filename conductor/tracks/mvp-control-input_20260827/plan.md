# Plan — MVP rebanada 2: Entrada de control

**Track ID:** `mvp-control-input_20260827`

Sigue la metodología definida en [`workflow.md`](../../workflow.md): tests fallando primero (Red), implementación mínima (Green), refactor, verificación de cobertura y checkpoint de fase. El trabajo va en rama y se integra por Pull Request.

**Orden:** el motor primero, otra vez, porque el cambio de `Pulses` toca código ya entregado en la rebanada 1 y conviene estabilizarlo antes de construir encima. Luego la cadena completa mensaje→Track de forma determinista, y solo al final la plataforma y el dispositivo.

## Phase 1: El modelo de Pulses en `Engine`

- [ ] Task: `Pulses` se valida por sí solo
  - [ ] Tests (Red): `Pulses` acepta 1–16 sin conocer Steps; rechaza 0, negativos y mayores que 16
  - [ ] Tests (Red): los casos de la Pre Spec (16/4, 16/5, 12/7) siguen dando el mismo patrón
  - [ ] Implementación (Green): `init?(_:)` sustituye a `init?(_:in:)`
  - [ ] Actualizar los tests de la rebanada 1 que asumen el inicializador acoplado
- [ ] Task: Acotado no destructivo en el reparto
  - [ ] Tests (Red): `Steps 4` con `Pulses 9` reparte 4 pulsos y **conserva** el 9
  - [ ] Tests (Red): subir Steps restaura el reparto original — ida y vuelta sin pérdida
  - [ ] Tests (Red): invariante exhaustiva — `effectivePulses == min(pulses, steps)` para toda combinación
  - [ ] Implementación (Green): `EuclideanRhythm` reparte `min(pulses, steps)`; `Shape.effectivePulses`
  - [ ] Documentar la desviación de la Pre Spec con nota fechada (`workflow.md` paso 8)
- [ ] Task: Lista ordenada de Divisions
  - [ ] Tests (Red): recorrer hacia arriba y hacia abajo se detiene en los extremos, no envuelve
  - [ ] Implementación (Green): secuencia de valores musicales, no un entero libre
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 2: Del mensaje MIDI al Track publicado

> Toda esta fase se testea sin CoreMIDI y sin hardware.

- [ ] Task: Decodificación de encoders relativos
  - [ ] Tests (Red): complemento a dos — `0x01`→+1, `0x3F`→+63, `0x7F`→−1, `0x41`→−63
  - [ ] Tests (Red): `0x00` y `0x40` no producen movimiento
  - [ ] Tests (Red): determinismo — mismo mensaje, mismo delta
  - [ ] Implementación (Green): la convención entra como parámetro, no cableada
- [ ] Task: Mapeo de CC a parámetro de Shape
  - [ ] Tests (Red): un CC mapeado mueve su parámetro y **solo** el suyo
  - [ ] Tests (Red): un CC sin mapear se ignora en silencio, no es error
  - [ ] Implementación (Green): tabla fija, **declarada provisional** en el código
- [ ] Task: Aplicar el delta y publicar
  - [ ] Tests (Red): girar Pulses publica un `Track` nuevo, recogido en la ventana siguiente
  - [ ] Tests (Red): bajar Steps acota sin destruir; subirlo restaura — de extremo a extremo desde el mensaje
  - [ ] Tests (Red): los extremos de rango no desbordan ni envuelven donde no deben
  - [ ] Implementación (Green): publicación por `TrackHandoff`, sin tocar el camino de tiempo real
  - [ ] Revisión explícita: decodificar y publicar corren en el hilo de control, nunca en el del scheduler
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## Phase 3: Entrada MIDI real y controlador virtual

- [ ] Task: Fuentes de entrada y selección
  - [ ] Tests (Red): la lista refleja las fuentes del sistema; sin fuentes es un estado válido
  - [ ] Tests (Red): `onSetupChanged` provoca reconsulta
  - [ ] Implementación (Green): estado `No MIDI input`, sin lenguaje de error ni disculpa
  - [ ] Reutilizar la lógica de selección de la salida en lugar de duplicarla
- [ ] Task: Recepción por CoreMIDI
  - [ ] Implementación (Green): puerto de entrada y conexión a la fuente elegida
  - [ ] Cierre explícito y ordenado desde el principio — no repetir el problema de `scheduler-lifecycle`
  - [ ] Medir la tasa de `-50`/`-2` antes y después: este track añade un segundo cliente de CoreMIDI
- [ ] Task: Controlador virtual de desarrollo
  - [ ] Tests (Red): inyectar un giro produce el mismo efecto que un CC real
  - [ ] Implementación (Green): inyector de eventos relativos, sin CoreMIDI
  - [ ] **Verificar que el binario de Release no lo contiene**
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
