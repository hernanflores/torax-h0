# Verificación en dispositivo — Sincronía de reloj externo

**Qué se verifica:** los diez criterios de aceptación del `spec.md` y la medición
de jitter con reloj interno (NFR4).

**Con qué:** iPad + BeatStep Pro conectado por Camera Kit + un sintetizador
recibiendo por MIDI. El BeatStep tiene que estar mandando su reloj —en MIDI
Control Center, *Sync* en `Internal` y la salida MIDI/USB activada— y sus
encoders en `Relative #2`, como siempre.

---

## 0. Instalar

```bash
xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS' \
  -derivedDataPath build/device
xcrun devicectl list devices          # el <ID> sale de la columna Identifier
xcrun devicectl device install app --device <ID> \
  build/device/Build/Products/Debug-iphoneos/ToraxH0.app
```

---

## 1. Los diez criterios

Marcar cada uno con lo observado. **Si alguno falla, se anota y se para**: el
track no cierra con un criterio en rojo.

> **Resultado — 2026-09-04, iPad + BeatStep Pro.** Verificados los criterios 1 a
> 8, **con dos defectos encontrados por el camino y arreglados**: el reloj
> entrante no llegaba al transporte (`03be820`) y el transporte del maestro no
> mandaba sobre el de la app (`f8e2432`). El criterio 9 no se ejerció: el
> hardware no llega a salirse del rango 20–300, así que queda cubierto por test y
> sin ver en dispositivo.

- [x] **1. El maestro manda.** Con `External` elegido en `3 · MIDI` y **sin tocar
      el iPad**, pulsar Play en el BeatStep: la app arranca. Con la app ya
      sonando, otro Play del BeatStep la reinicia desde el paso 0.
- [x] **2. Los doce arrancan en fase**, entre sí y con el hardware.
- [x] **3. El tempo se sigue y se lee.** Mover el tempo del BeatStep. El número
      de la barra cambia y **no baila en el último decimal**.
- [x] **4. Dos minutos sin separarse.** Dejar sonar dos minutos junto al
      secuenciador del BeatStep y escuchar si se van. *(Es el criterio sin
      número: se juzga tocando. Anotar cómo se juzgó.)*
- [x] **5. El Stop del maestro apaga limpio.** Pulsar Stop en el BeatStep: la app
      para, **no queda ninguna nota sonando** y el transporte se desarma.
      Probarlo con Sustain alto, que es donde una nota colgada dura segundos.
- [x] **6. El cable se puede caer.** Con el transporte corriendo, desconectar el
      BeatStep. La música **sigue** y la pantalla MIDI dice `Clock lost —
      holding last tempo`. Volver a conectarlo: se re-engancha **sin parar y sin
      volver al paso 0**.
- [x] **7. `Internal` ignora al maestro.** Con `Internal` elegido, pulsar Play y
      Stop en el BeatStep: la app no se inmuta.
- [x] **8. El tempo interno se edita.** Con `Internal`, mover el tempo con los
      botones de `3 · MIDI` por todo el rango 20–300 y oír el cambio. Cambiarlo
      **mientras suena** no reinicia la rejilla ni pierde el paso.
- [~] **9. Un maestro imposible se ignora y se dice.** *(No ejercido: el BeatStep
      no sale del rango 20–300. Cubierto por test, sin ver en dispositivo.)* Si el BeatStep llega a
      salirse del rango 20–300, la app conserva el último tempo bueno y lo
      indica. *(Si el hardware no puede salirse del rango, anotarlo así: el caso
      queda cubierto por test y sin verificar en dispositivo.)*
- [x] **10. Jitter medido.** CUMPLE el umbral, con regresión aceptada. Ver la sección 2.

---

## 2. Medición de jitter, con reloj interno

**Se mide con el reloj de la app, no siguiendo al maestro** (NFR4): lo que se
quiere saber es si el trabajo nuevo degradó el camino que ya funcionaba. El
jitter *siguiendo a un maestro* queda sin número —el arnés no sabe medir contra
un reloj externo— y es la limitación 5 del `spec.md`.

```bash
xcrun devicectl device process launch --device <ID> --console \
  com.toraxh0.ToraxH0 --auto-measure --samples=1000 --grid=12-tracks-cycles
```

- [x] **Pulsar Play en la app en cuanto arranque**, con `Internal` elegido, y
      dejarlo sonando toda la pasada. Los anillos tienen que verse moviéndose: si
      el playhead no corre, la medición no vale. *(El arnés por sí solo deja la
      pantalla quieta; el procedimiento está en el `device-verification.md` de la
      rebanada 2.)*
- [x] Dejar la pantalla `1 · Track` a la vista. Son unos 8 minutos, tres tempos.
- [x] Recoger el informe:

      xcrun devicectl device copy from --device <ID> \
        --domain-type appDataContainer --domain-identifier com.toraxh0.ToraxH0 \
        --source Documents/jitter-report-12-tracks-cycles.txt --destination .

### Contra qué se compara

| | máx | σ |
|---|---|---|
| Referencia vigente (v2 rebanada 2, 2026-09-02) | 0,158 ms | 0,013–0,014 ms |
| Umbral del proyecto | 2 ms | 0,5 ms |

**Una regresión bloquea el cierre** (NFR4).

### Pasada 1 — 2026-09-03

```
60 BPM  · n=1000  máx=0,144 ms  media=+0,097 ms  σ=0,015 ms  → CUMPLE
120 BPM · n=1000  máx=0,468 ms  media=+0,097 ms  σ=0,030 ms  → CUMPLE
174 BPM · n=1000  máx=0,374 ms  media=+0,091 ms  σ=0,024 ms  → CUMPLE
VEREDICTO: CUMPLE
```

**CUMPLE con margen —4,3× en el máximo y 16× en la σ— pero es peor que la
referencia**: el máximo la triplica y la σ la dobla. Dos cosas apuntan a un
episodio y no a un coste del cambio:

- **La media no se mueve**, y de hecho baja: +0,091 a +0,097 ms contra los
  +0,105–0,121 de las seis mediciones anteriores. Estimar el tempo y corregir la
  fase por negra costarían tiempo de forma sistemática, y eso subiría la media y
  degradaría los tres tempos a la vez. Lo que se ensanchó es la cola.
- **El pico está a 120 BPM, no a 174.** Si el coste fuera del trabajo por
  ventana, el tempo más rápido sería el peor.

Es el mismo patrón que la v2 rebanada 1, cuya cola de 0,598 ms a 174 BPM no se
reprodujo en la rebanada siguiente. **Se repite la pasada** antes de decidir
(2026-09-03).

### Pasada 2 — 2026-09-04

```
60 BPM  · n=1000  máx=0,152 ms  media=+0,094 ms  σ=0,012 ms  → CUMPLE
120 BPM · n=1000  máx=0,448 ms  media=+0,095 ms  σ=0,028 ms  → CUMPLE
174 BPM · n=1000  máx=0,525 ms  media=+0,093 ms  σ=0,030 ms  → CUMPLE
VEREDICTO: CUMPLE
```

**Se reproduce, así que la hipótesis del episodio era falsa.** Con dos muestras el
patrón es nítido:

| Tempo | Pasada 1 | Pasada 2 | Referencia |
|---|---|---|---|
| 60 BPM | 0,144 · 0,015 | 0,152 · 0,012 | indistinguible |
| 120 BPM | 0,468 · 0,030 | 0,448 · 0,028 | 0,158 · 0,013–0,014 |
| 174 BPM | 0,374 · 0,024 | 0,525 · 0,030 | ídem |

**60 BPM está limpio y los dos tempos rápidos no.** Apunta a un coste que se nota
cuando hay más eventos por ventana —la ventana de look-ahead dura lo mismo a
cualquier tempo, pero a 174 BPM caben más eventos dentro—. Lo que no encaja con
esa lectura es que **la media no se mueva**: un coste por evento debería subirla,
y en las dos pasadas baja ligeramente respecto a las seis mediciones anteriores.

**Sospechosos, por si alguien retoma esto**, los dos son trabajo por evento que
este track añadió:

1. `TempoMap.wallNanoseconds(forGridNanoseconds:)`, una división en coma flotante
   y un redondeo por evento en el bucle del scheduler.
2. La lectura atómica del `ClockHandoff` **por nota** en el cierre de emisión, que
   escala la duración del gate. Está documentada en `Transport` como excepción
   consciente a «una lectura por ventana»: sería lo primero que yo movería a la
   ventana, pasando el factor con el evento.

**El experimento que no se hizo**, y que es el que decide: medir `main` en el
mismo iPad y el mismo día. La referencia de 0,158 ms se tomó el 2026-09-02, en
otra sesión; sin repetirla no se puede separar «regresión del track» de
«condiciones distintas». Se propuso y **se descartó**.

### Decisión — 2026-09-04: se cierra con la regresión dentro

**Lo decidió el usuario**, con los dos números delante. Qué significa:

- El track **cumple el umbral del proyecto con margen**: 4,3× en el máximo (0,525
  contra 2 ms) y 16× en la σ (0,030 contra 0,5 ms).
- Y **empeora respecto a la referencia**: el máximo la triplica y la σ la dobla.
- **Contradice el NFR4 de este track**, que dice que una regresión bloquea el
  cierre. Se cierra igualmente, y queda escrito aquí para que la decisión se
  pueda revisar con el coste delante.
- **La referencia vigente pasa a ser esta**: máx 0,525 ms, σ hasta 0,030 ms. Quien
  mida después compara contra este número, no contra el de la rebanada 2.

---

## 3. Registro

Resultado de la pasada, fecha y dispositivo. Lo que falle se anota aquí con la
condición exacta para reproducirlo.
