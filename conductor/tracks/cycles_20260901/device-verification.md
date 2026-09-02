# Verificación en dispositivo — v2 rebanada 3: Cycles

**Requiere iPad, BeatStep Pro y un sintetizador multitímbrico.** Es la fase que
decide si la rebanada vale: las cinco anteriores pueden estar impecables y ésta
invalidarlas.

El bloque 0 es preparación, el 1 es la medición de jitter —bloqueante— y el 2 la
verificación funcional con el hardware.

---

## 0. Antes de empezar

- [ ] **Los encoders del BeatStep Pro en `Relative #2`**, en MIDI Control Center.
      Sin eso un clic se decodifica como ±63 y todos los parámetros saltan a su
      extremo. Nota del 2026-08-28 en `workflow.md`.
- [ ] **El multitímbrico conectado**, con al menos dos canales sonando distinto.
      Sin eso no se puede juzgar si dos Tracks desarrollan por separado.
- [ ] **El sintetizador sonando con lo entregado hasta la rebanada 2.** Si algo
      no suena antes de tocar esta rebanada, no es esta rebanada.

---

## 1. Jitter con los dieciséis sonando y avanzando

> **La medición que puede parar la rebanada.** Esta rebanada añade trabajo al
> hilo del scheduler —una decisión en el límite de cada vuelta y un cambio de
> material justo ahí— y multiplica por dieciséis el snapshot que ese hilo copia.
> Es exactamente lo que la nota del 2026-08-28 de `workflow.md` obliga a medir.

### La rejilla es nueva, y por qué

La rejilla `16 Tracks` de la rebanada 1 deja **un Cycle por Track**, así que
mediría los dieciséis quietos: el trabajo que esta rebanada añade no se
ejercería nunca y el CUMPLE no diría nada.

Se añadió `16 Tracks · 4 Cycles`, con los dieciséis Tracks recorriendo cuatro
Cycles cada uno. Los cuatro comparten Shape —la vuelta dura lo mismo, y así el
número sigue siendo comparable con las mediciones anteriores— y llevan alturas
distintas, para que el cambio de material sea real. Hay tests que lo vigilan en
`JitterHarnessCyclesGridTests`.

**Cuatro y no dieciséis**: lo que se mide es el coste de *avanzar*, que ocurre
una vez por vuelta y no depende de cuántos haya. Con cuatro, una pasada completa
cabe varias veces en la medición; con dieciséis solo se alargaría la pasada sin
ejercer nada nuevo.

### El paso que no es obvio

**El arnés por sí solo no produce carga visual ninguna.** Corre su propio
scheduler en una tarea aparte y no toca `TransportModel`, así que el transporte
de la app sigue parado, los playheads son `nil` y los anillos son idénticos
fotograma a fotograma — SwiftUI no repinta lo que no cambia. Comprobado con una
sonda el 2026-09-02, no supuesto: menos de 30 ejecuciones del `Canvas` en 8
segundos.

Medir sin esto daría un **CUMPLE que no significa nada**: sería el timing con la
pantalla congelada.

De ahí que haya que **pulsar Play en la app mientras el arnés mide**. Esta
rebanada añade además una fila que se repinta a 10 Hz, así que también hay que
**dejar varios Cycles activos en el Track seleccionado** para que esa fila tenga
algo que mover.

### El procedimiento

```bash
# 1. Instalar la build en el iPad, desde la raíz del repo
xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS' \
  -derivedDataPath build/device
xcrun devicectl device install app --device <ID> \
  build/device/Build/Products/Debug-iphoneos/ToraxH0.app

# 2. Lanzarla con el arnés. --console deja la salida en la terminal
xcrun devicectl device process launch --device <ID> --console \
  com.toraxh0.ToraxH0 --auto-measure --samples=1000 --grid=16-tracks-cycles
```

El `<ID>` sale de `xcrun devicectl list devices` (columna *Identifier*).

Desde Xcode también vale: *Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Arguments ▸
Arguments Passed On Launch*. **Hay que acordarse de quitarlos después**, o
cualquier ejecución posterior arrancará midiendo.

- [ ] Lanzada con `--auto-measure --samples=1000 --grid=16-tracks-cycles`.
- [ ] **Antes de que arranque la primera pasada**: dejar el Track 1 con **4
      Cycles activos** (fila *Cycles*, botón «4») y pulsar Play. Los anillos
      tienen que verse moviéndose y el relleno de la fila de Cycles avanzando.
      Si no, la medición no vale y hay que repetirla.
- [ ] Dejar la pantalla `1 · Track` a la vista. Son unos 8 minutos, tres tempos.
- [ ] Recoger `Documents/jitter-report-16-tracks-cycles.txt`:

      xcrun devicectl device copy from --device <ID> \
        --domain-type appDataContainer --domain-identifier com.toraxh0.ToraxH0 \
        --source Documents/jitter-report-16-tracks-cycles.txt --destination .

> **Esto hace correr dos schedulers a la vez** —el de la app y el del arnés—, que
> es más carga de la que el producto tiene nunca. La medición queda
> **conservadora a propósito**: si pasa así, pasa en uso real.

### Contra qué se compara

| Referencia | Máx | σ |
|---|---|---|
| MVP rebanada 6 — Groove temporal (2026-08-30) | 0,151 ms | 0,009–0,013 ms |
| v2 rebanada 1 — dieciséis Tracks (2026-09-01) | 0,598 ms | 0,083 ms |
| v2 rebanada 2 — dieciséis anillos (2026-09-02) | 0,158 ms | 0,013–0,014 ms |

**Umbral: máx < 2 ms, σ < 0,5 ms.** Se registra el número, no la impresión.

### Y lo que hay que mirar además del número

- [ ] **¿Algún pico cae en el Step 0 de una vuelta?** Ahí es donde esta rebanada
      añade trabajo: es la primera decisión dentro del bucle del scheduler que no
      es aritmética pura. Un máximo alto repartido es otra cosa que un máximo
      alto agrupado en los límites de vuelta.
- [ ] **¿Se movió la media?** Es lo que distingue un coste sistemático —copiar un
      snapshot dieciséis veces mayor— de unos pocos outliers. La rebanada 1 dejó
      anotado que su cola no movía la media.
- [ ] **¿Se reprodujo la cola de la rebanada 1?** Sus 0,598 ms a 174 BPM no
      volvieron a aparecer en la rebanada 2. Si reaparecen aquí, deja de ser un
      episodio puntual.

| Resultado | Qué significa |
|---|---|
| En línea con la rebanada 2 | Avanzar de Cycle no cuesta timing. Es lo esperado: el avance es aritmética de enteros y una copia que ya se pagaba. |
| σ peor pero bajo umbral | Se registra y se explica. Mirar primero el límite de vuelta; después, la fila de Cycles a 10 Hz. |
| Umbral superado | **La rebanada se para** y se bisecta con el arnés. No se cierra con una medición mala explicada. |

### Resultado — _(fecha)_, iPad Air (4ª gen)

Rejilla `16 Tracks · 4 Cycles`, **1000 eventos por tempo**, con el transporte de
la app corriendo, los dieciséis anillos repintándose y cuatro Cycles avanzando.

| Tempo | n | Máx | Media | σ | Veredicto |
|---|---|---|---|---|---|
| 60 BPM |  |  |  |  |  |
| 120 BPM |  |  |  |  |  |
| 174 BPM |  |  |  |  |  |

**Lectura:** _(pendiente de medir)_

---

## 2. Verificación funcional con el hardware

> **Validada el 2026-09-02**, antes de la medición: el desarrollo suena, los dos
> cursores se comportan y `Stop` no deja nada colgado. Se deja escrito el
> recorrido para poder repetirlo.

- [x] **Un Track con 3 Cycles distintos**: se oye el desarrollo A/B/C y el
      retorno a A, sin tocar nada.
- [x] **Dos Tracks de longitudes distintas con Cycles**: desarrollan a ritmos
      distintos y no se desalinean al cabo de varios minutos.
- [x] **Construir el Cycle B con el knob 10 mientras suena el A**, y oírlo entrar
      en su vuelta.
- [x] **Play dos veces**: el desarrollo se repite igual.
- [x] **`Stop` con Cycles avanzando**: nada queda colgado, incluido con Delay
      positivo y canales distintos por Cycle.

### Lo que esta pasada encontró

**Un fallo de la pantalla, no del motor.** Con el transporte parado, mover el
knob 10 y girar otro knob no cambiaba nada en pantalla, y se leía como «el Track
dejó de responder a los knobs».

Los knobs sí editaban, y el Cycle correcto: lo que fallaba era que la vista
—`TransportModel.track`, el anillo, el playhead, la pastilla de canal y el mapa
de material— seguía enseñando el Cycle **que suena** en vez del **que se edita**.

Arreglado en `c9f5b2a`, con la regla escrita y cuatro tests: todo lo que la
pantalla muestra es el Cycle en edición; lo único que enseña el que suena es el
relleno de la fila de Cycles.

**Por qué ningún test lo cogía antes:** con un solo Cycle activo los dos accesos
devuelven lo mismo, y hasta esta rebanada nunca hubo más de uno.
