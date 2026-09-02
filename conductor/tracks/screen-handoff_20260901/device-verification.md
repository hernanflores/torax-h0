# Verificación en dispositivo — v2 rebanada 2: La pantalla del handoff

**Requiere iPad, BeatStep Pro y un sintetizador.** Es la fase que decide si la
pantalla vale: las cinco anteriores pueden estar impecables y ésta invalidarlas.

Se ejecuta en orden. El bloque 0 es preparación, el 1 es la medición y del 2 al 5
la verificación a un metro. Cada bloque dice qué se espera **y qué significa si
sale distinto**, para no tener que decidirlo en caliente.

---

## 0. Antes de empezar

- [ ] **Los encoders del BeatStep Pro en `Relative #2`**, en MIDI Control Center.
      Sin eso un clic se decodifica como ±63 y todos los parámetros saltan a su
      extremo. Nota del 2026-08-28 en `workflow.md`.
- [ ] **El sintetizador conectado y sonando** con lo entregado hasta la rebanada
      1 de la v2. Si algo no suena antes de tocar esta pantalla, no es esta
      rebanada.
- [ ] **Material en varios Tracks, no solo en el 1.** La pantalla arranca con
      material únicamente en el Track 1; para lo que se mide aquí hacen falta
      varios anillos con reparto propio. Se seleccionan con los step buttons y se
      les dan alturas con los pads.
- [ ] **Brillo al que se usa de verdad**, no al máximo: el criterio de
      legibilidad es a un metro y en las condiciones reales.

---

## 1. Jitter con los dieciséis anillos redibujándose

> **La fase que decide la rebanada.** No toca el scheduler y aun así mide, porque
> dieciséis anillos repintándose al ritmo del reloj son la «carga visual nueva»
> que la nota del 2026-08-28 de `workflow.md` obliga a medir.

### Por qué el procedimiento tiene un paso raro

**El arnés por sí solo no produce carga visual ninguna.** Corre su propio
scheduler en una tarea aparte y no toca `TransportModel`, así que el transporte
de la app sigue parado, los playheads son `nil` y los dieciséis anillos son
idénticos fotograma a fotograma — SwiftUI no repinta lo que no cambia, aunque el
`TimelineView` siga latiendo.

**Comprobado el 2026-09-02**, no supuesto: una sonda que contaba ejecuciones del
`Canvas` registró menos de 30 en 8 segundos, incluso forzando `paused: false`.

> Medir sin este paso daría un **CUMPLE que no significa nada**: sería el timing
> con la pantalla congelada, que es justo lo contrario de lo que NFR2 pide.

De ahí que haya que **pulsar Play mientras el arnés mide**.

### El procedimiento

- [ ] Lanzar con el arnés y la rejilla recta, 1000 eventos por tempo:

      --auto-measure --samples=1000 --grid=recta

- [ ] **Pulsar Play en la app en cuanto arranque**, y dejarlo sonando toda la
      pasada. Los anillos tienen que verse moviéndose: si el playhead no corre,
      la medición no vale y hay que repetirla.
- [ ] Dejar la pantalla `1 · Track` a la vista. Son unos 8 minutos, tres tempos.
- [ ] Recoger `Documents/jitter-report-recta.txt`.

> **Esto hace correr dos schedulers a la vez** —el de la app y el del arnés—, que
> es más carga de la que el producto tiene nunca. **La medición queda
> conservadora a propósito:** si pasa así, pasa en uso real. Se anota en el
> informe; no es un defecto del método, es su sesgo, y va en la dirección segura.

### Contra qué se compara

| Referencia | Máx | σ |
|---|---|---|
| MVP rebanada 3 — **un** anillo (2026-08-28) | 0,134 ms | 0,020 ms |
| v2 rebanada 1 — dieciséis Tracks (2026-09-01) | 0,598 ms | 0,083 ms |

**Umbral: máx < 2 ms, σ < 0,5 ms.** Se registra el número, no la impresión.

| Resultado | Qué significa |
|---|---|
| En línea con la rebanada 1 | Los dieciséis anillos no cuestan timing. Es lo esperado: el dibujo va en el hilo principal y el scheduler en el suyo. |
| σ peor pero bajo umbral | Se registra y se explica. La causa probable es dibujar de más por fotograma, **no el scheduler**: se ataca ahí antes de tocar nada de timing. |
| Umbral superado | **La rebanada se para.** Se bisecta quitando carga de dibujo —empezando por reconstruir el `RingStack` en cada fotograma— antes de mirar el camino de envío. |

- [ ] El número va a `product.md`, junto a las anteriores, y a la git note.

> **Una sospecha que conviene tener delante al leer el resultado.** La rebanada 3
> registró «jitter con carga visual: máx 0,134 ms · σ 0,020 ms» y atribuyó +5 µs
> de σ al redibujado del anillo. La arquitectura era la misma que la de hoy, así
> que **es posible que aquella medición tampoco tuviera el anillo animándose** y
> que esos 5 µs fueran ruido. No se puede comprobar retroactivamente y no cambia
> ninguna decisión ya tomada; si la medición de ahora sale parecida a la de la
> rebanada 1, ésta es una explicación candidata y no hace falta buscar otra.

---

## 2. El playhead, a un metro

> **Es el riesgo declarado de la rebanada** (FR2), y el que la inversión de
> columnas de la Fase 3 existía para acotar.

- [ ] Con el transporte corriendo, **a un metro de la pantalla**: se ve por dónde
      va el tiempo en el Track seleccionado.
- [ ] Con dos Tracks en Divisions distintas: se ve que sus playheads van a
      velocidades distintas, cada uno sobre su anillo.

| Resultado | Qué hacer |
|---|---|
| Se lee | Nada. FR2 cumplido y el riesgo se cierra. |
| No se lee | **Anillo grande aparte para el Track elegido**, que es la respuesta que la spec ya deja escrita — no dibujar menos anillos. Se decide aquí, se anota como enmienda de la spec y se abre la tarea. |

---

## 3. Los tres acentos, de reojo y con poca luz

> **El riesgo 6 de la spec**, y la razón por la que el ámbar existía.

- [ ] Tocar los tres tabs y mirar **de reojo**, no de frente: SHAPE verde, GROOVE
      mauve, TONAL violeta.
- [ ] Con poca luz, que es la condición de uso que `product-guidelines.md` nombra.

| Resultado | Qué hacer |
|---|---|
| Se distinguen | El mauve del handoff se queda. Se anota que se comprobó. |
| Mauve y violeta se confunden | **Volver al ámbar `#D99A4E` es una opción legítima y documentada**: su razón —separarse por tono y no solo por luminosidad— sigue escrita en `Palette.groove`. Se decide con la app en la mano y se registra la decisión, sea cual sea. |

---

## 4. La lectura grande, a un metro

- [ ] Girar un knob de **cada** familia y comprobar que el panel responde en el
      Step siguiente, con el color de la familia que se movió.
- [ ] **El tab activo salta a la familia del knob que se giró.** Es la regla que
      se eligió en la Fase 3: el giro manda, porque la pantalla es el espejo del
      controlador.
- [ ] `Probability 100%` —la lectura más larga— **se lee entera**, en dos
      líneas. Es la corrección del 2026-09-02.
- [ ] **Los anillos no se tapan en ningún momento**, gire lo que gire. Desde
      FR14 es estructural —viven en otra columna— así que un solape sería un
      fallo de layout, no de la regla.

---

## 5. Lo que se corrigió el 2026-09-02, y hay que ver que quedó bien

- [ ] Con **dos o más destinos MIDI disponibles**: la barra superior escribe el
      nombre del dispositivo **una sola vez**, y el selector es una flecha.
- [ ] Un nombre largo de CoreMIDI **no empuja las tres columnas hacia abajo** ni
      corta la interfaz por el borde inferior.
- [ ] La fila de canal se ve entera, sin cortarse.

> Esto no se pudo verificar en simulador: hacen falta dos o más dispositivos MIDI
> y el simulador no tiene ninguno — con menos de dos el selector ni siquiera
> aparece.

---

## 6. Registro

- [ ] Los números y las decisiones, en la git note de la tarea. **Un número, no
      una impresión.**
- [ ] Este fichero, con lo que salió de cada bloque.
- [ ] Si algo se decidió distinto de lo que la spec dice, la enmienda va a
      `spec.md` con su razón — no solo aquí.
