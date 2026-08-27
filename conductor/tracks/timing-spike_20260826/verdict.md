# Veredicto — Timing Spike

**Track:** `timing-spike_20260826` · **Fecha:** 2026-08-26
**Dispositivo:** iPad Air (4ª generación), iPadOS 26.5

## Criterio de aceptación

> Medido por loopback en el iPad objetivo, a 60, 120 y 174 BPM:
> **desviación máxima < 2 ms** y **desviación típica < 0,5 ms**.

## Resultado: **CUMPLE**

### Medición de referencia — 200 eventos por tempo

| Tempo | Máximo | Media | σ | |
|---|---|---|---|---|
| 60 BPM | 0,115 ms | +0,062 ms | 0,008 ms | ✅ |
| 120 BPM | 0,104 ms | +0,062 ms | 0,009 ms | ✅ |
| 174 BPM | 0,101 ms | +0,056 ms | 0,008 ms | ✅ |

### Confirmación — 1000 eventos por tempo

| Tempo | Máximo | Media | σ | |
|---|---|---|---|---|
| 60 BPM | 0,149 ms | +0,063 ms | 0,009 ms | ✅ |
| 120 BPM | 0,108 ms | +0,060 ms | 0,009 ms | ✅ |
| 174 BPM | 0,105 ms | +0,057 ms | 0,008 ms | ✅ |

**Margen sobre el umbral:** ~13× en máximo, ~55× en desviación típica.

## Lectura de los números

**La σ es lo que decide la estabilidad musical**, y está entre 8 y 9 µs en todos los tempos. Esa cifra no se mueve al quintuplicar la muestra ni al cambiar de tempo: el reloj es estable, no estable por casualidad.

**La media positiva de +0,06 ms no es jitter, es sesgo constante** — latencia fija del camino de medición (entrega de CoreMIDI más el coste de leer el reloj en el bloque de recepción). Un desfase constante es musicalmente inocuo y, si alguna vez estorbara, se compensa restándolo. La variación es lo que no se puede arreglar después.

**La duda que la spec dejó abierta queda cerrada.** Se registró que 200 muestras podían no capturar un outlier de baja frecuencia. Con 5× más muestras el máximo sube 0,034 ms en el peor caso y la σ no cambia: la cola de la distribución se comporta.

**El iPad no fue peor que el Mac**, contra lo que se temía por la gestión térmica y de energía. Los números son equivalentes.

## Qué queda validado

La arquitectura de `tech-stack.md` — **look-ahead scheduling con timestamps de CoreMIDI**, hilo dedicado sin locks, snapshot inmutable — alcanza el timing que el producto necesita en el dispositivo objetivo. El proyecto puede seguir adelante sobre esta base.

## Qué NO queda validado

Cuatro cosas, y conviene no confundirlas con lo anterior:

1. **La cadena hasta el sintetizador.** El loopback es virtual: no cruza el cable USB. La latencia y el jitter del interfaz USB-MIDI están sin medir.
2. **El comportamiento bajo carga.** Se midió con la app en primer plano sin hacer nada más. Sin UI redibujando, sin motor generativo, sin 16 Tracks. La Fase 2 dejó el snapshot fijo al arrancar: cambiar parámetros en caliente exigirá publicación atómica, y eso es código nuevo en el camino crítico.
3. **Sesiones largas y estrés térmico.** La pasada más larga fue de ~4 minutos por tempo. Un directo dura más y calienta el dispositivo.
4. **Otros iPads.** Un solo dispositivo, y no el más antiguo que soporta iPadOS 17.

## Hallazgos del spike

Tres cosas que solo aparecieron por construir esto, y que habrían costado más caro más tarde:

1. **Los endpoints MIDI virtuales en iOS exigen el modo de fondo `audio`.** Sin él, `kMIDINotPermitted (-10844)`. En macOS no hace falta: 64 tests en verde y el dispositivo fallando.
2. **El resultado del envío no detecta desconexiones.** CoreMIDI acepta envíos a endpoints inexistentes con `noErr`. La detección va por notificaciones.
3. **Un target C solo-cabecera compila en host y rompe el enlazado de iOS.** Los tests pasaban y el build de dispositivo fallaba.

## Recomendación

Seguir con el MVP sobre esta arquitectura. El siguiente riesgo a atacar **no es el timing sino la carga**: medir de nuevo con el motor generativo y la UI reales encima, porque es entonces cuando el hilo del scheduler tendrá competencia.
