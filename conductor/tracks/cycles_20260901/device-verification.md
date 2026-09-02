# Verificación en dispositivo — v2 rebanada 3: Cycles

**Requiere iPad, BeatStep Pro y un sintetizador multitímbrico.**

El bloque 0 es preparación, el 1 era la medición de jitter —**retirada el
2026-09-02**, y se conserva como procedimiento— y el 2 la verificación funcional
con el hardware, que es la que se ejecutó.

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

## 1. ~~Jitter con los dieciséis sonando y avanzando~~ — retirada el 2026-09-02

> **No se ejecuta.** Decisión del usuario del 2026-09-02, tomada después de que
> la recogida del informe del dispositivo fallara: no se hacen más mediciones de
> jitter en el proyecto. Está en `workflow.md`, en *Medición de jitter:
> suspendida*, con el coste de la decisión detallado, y en el NFR4 del
> `spec.md`, con lo que queda sin comprobar en esta rebanada.
>
> **Todo lo de abajo se conserva y funciona.** No es documentación muerta: es el
> procedimiento listo para el día que se quiera volver a medir, incluida la
> rejilla nueva que esta rebanada necesitaba y que antes no existía.

### La rejilla es nueva, y por qué

> **Nota del 2026-09-02 — los nombres de rejilla de esta página son los de
> entonces.** Al bajar a doce Tracks (`ui-declutter_20260902`), `16 Tracks` y
> `16 Tracks · 4 Cycles` pasaron a llamarse `12 Tracks` y `12 Tracks · 4 Cycles`,
> con sufijos `12-tracks` y `12-tracks-cycles`. Aquí se dejan sin tocar porque
> este documento **registra una ejecución que ocurrió**, y con dieciséis: para
> repetir el procedimiento hoy, sustituye el nombre en los comandos.

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

De ahí que haya que **pulsar Play en la app mientras el arnés mide**, y dejar
varios Cycles activos en el Track seleccionado para que la fila de Cycles tenga
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

Después, el informe:

```bash
xcrun devicectl device copy from --device <ID> \
  --domain-type appDataContainer --domain-identifier com.toraxh0.ToraxH0 \
  --source Documents/jitter-report-16-tracks-cycles.txt --destination .
```

> **Este último paso es el que falló el 2026-09-02**, y es lo que llevó a
> suspender las mediciones. Si se retoman, es por donde hay que empezar: el
> `--console` del lanzamiento deja el veredicto en la terminal aunque el fichero
> no se pueda recoger, así que esa es la vía de respaldo.

### Contra qué se habría comparado

| Referencia | Máx | σ |
|---|---|---|
| MVP rebanada 6 — Groove temporal (2026-08-30) | 0,151 ms | 0,009–0,013 ms |
| v2 rebanada 1 — dieciséis Tracks (2026-09-01) | 0,598 ms | 0,083 ms |
| v2 rebanada 2 — dieciséis anillos (2026-09-02) | 0,158 ms | 0,013–0,014 ms |

Umbral: máx < 2 ms, σ < 0,5 ms.

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
