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

- [ ] **1. El maestro manda.** Con `External` elegido en `3 · MIDI` y **sin tocar
      el iPad**, pulsar Play en el BeatStep: la app arranca. Con la app ya
      sonando, otro Play del BeatStep la reinicia desde el paso 0.
- [ ] **2. Los doce arrancan en fase**, entre sí y con el hardware.
- [ ] **3. El tempo se sigue y se lee.** Mover el tempo del BeatStep. El número
      de la barra cambia y **no baila en el último decimal**.
- [ ] **4. Dos minutos sin separarse.** Dejar sonar dos minutos junto al
      secuenciador del BeatStep y escuchar si se van. *(Es el criterio sin
      número: se juzga tocando. Anotar cómo se juzgó.)*
- [ ] **5. El Stop del maestro apaga limpio.** Pulsar Stop en el BeatStep: la app
      para, **no queda ninguna nota sonando** y el transporte se desarma.
      Probarlo con Sustain alto, que es donde una nota colgada dura segundos.
- [ ] **6. El cable se puede caer.** Con el transporte corriendo, desconectar el
      BeatStep. La música **sigue** y la pantalla MIDI dice `Clock lost —
      holding last tempo`. Volver a conectarlo: se re-engancha **sin parar y sin
      volver al paso 0**.
- [ ] **7. `Internal` ignora al maestro.** Con `Internal` elegido, pulsar Play y
      Stop en el BeatStep: la app no se inmuta.
- [ ] **8. El tempo interno se edita.** Con `Internal`, mover el tempo con los
      botones de `3 · MIDI` por todo el rango 20–300 y oír el cambio. Cambiarlo
      **mientras suena** no reinicia la rejilla ni pierde el paso.
- [ ] **9. Un maestro imposible se ignora y se dice.** Si el BeatStep llega a
      salirse del rango 20–300, la app conserva el último tempo bueno y lo
      indica. *(Si el hardware no puede salirse del rango, anotarlo así: el caso
      queda cubierto por test y sin verificar en dispositivo.)*
- [ ] **10. Sin regresión de jitter.** Ver la sección 2.

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

- [ ] **Pulsar Play en la app en cuanto arranque**, con `Internal` elegido, y
      dejarlo sonando toda la pasada. Los anillos tienen que verse moviéndose: si
      el playhead no corre, la medición no vale. *(El arnés por sí solo deja la
      pantalla quieta; el procedimiento está en el `device-verification.md` de la
      rebanada 2.)*
- [ ] Dejar la pantalla `1 · Track` a la vista. Son unos 8 minutos, tres tempos.
- [ ] Recoger el informe:

      xcrun devicectl device copy from --device <ID> \
        --domain-type appDataContainer --domain-identifier com.toraxh0.ToraxH0 \
        --source Documents/jitter-report-12-tracks-cycles.txt --destination .

### Contra qué se compara

| | máx | σ |
|---|---|---|
| Referencia vigente (v2 rebanada 2, 2026-09-02) | 0,158 ms | 0,013–0,014 ms |
| Umbral del proyecto | 2 ms | 0,5 ms |
| **Esta pasada** | | |

**Una regresión bloquea el cierre** (NFR4).

---

## 3. Registro

Resultado de la pasada, fecha y dispositivo. Lo que falle se anota aquí con la
condición exacta para reproducirlo.
