# Verificación en simulador — v2 rebanada 6: LFO Modulation

**Track:** `modulation_20260906`
**Fecha:** 2026-09-08
**Simulador:** iPad Pro 11", iOS 26.3
**Build:** `xcodebuild -scheme ToraxH0 -destination "id=<sim>"`, instalado y
lanzado con `simctl`

## Qué puede decidir el simulador y qué no

**Puede:** la pantalla entera. Sin MIDI no hay transporte, y `modulation` no
depende de él para nada de lo que dibuja salvo el playhead — la rejilla de
ondas, el panel, el slider y los dos cards son estado y no edición, igual que
pasa con la pantalla `track`.

**No puede**, y queda para el dispositivo:

- **El playhead del panel** (FR14). Sin destinos MIDI `canPlay` es falso, así que
  no hay transporte que lo mueva.
- **Que el acento se oiga.** Es el criterio 13 y solo lo decide un sinte.
- **El gesto del slider.** `simctl` no toca la pantalla, así que el arrastre y el
  imantado se comprueban con el dedo.

## Cómo se forzaron los estados

`simctl` no puede tocar la pantalla, así que cada captura se hizo **construyendo
una app con el estado dentro** —arranque en `modulation`, y la onda o el anillo
fijados en la vista— y revirtiendo el cambio después. Es una técnica de
verificación, no código entregado: el árbol quedó limpio antes del commit y no
hay ni una constante de prueba en `App/ModulationScreen.swift`.

## Lo que se comprobó

### El chrome de cinco (FR10) — **cumple**

Las cinco pestañas —`track`, `scale`, `midi`, `banks`, `modulation`— caben en la
fila sin apretarse, con el subrayado de 3 pt en la activa. El relleno lateral
bajó de 28 a 20 puntos para que la palabra más larga del conjunto no dejara las
etiquetas tocándose; el objetivo táctil sigue siendo la columna entera.

### Las cuatro ondas (FR11, FR19, FR20) — **cumple**

Rejilla 2×2, la seleccionada en mauve plano con etiqueta oscura y las otras tres
hundidas con borde neutro de 2 pt. Todas las cadenas en minúscula. Las cuatro
capturas —una por onda— coinciden con la forma que `Engine` entrega:

| Onda | Lo que dibuja el card | Lo que dibuja el panel |
|---|---|---|
| `saw` | rampa con **un** corte, dos ciclos | sube al cuarto, cae, vuelve a subir |
| `triangle` | subida y bajada simétricas | pico en el Step 4 de 16, valle en el 12 |
| `sine` | la misma forma redondeada | pico donde el de `triangle` |
| `pulse` | onda cuadrada, dos ciclos | ocho barras altas y ocho bajas |

### El recorte se ve (FR12) — **cumple, y es el hallazgo que justifica el panel**

Con `Velocity` 100 y `accent` +100, las barras del cuarto de vuelta **se aplanan
contra 127 formando una meseta**, mientras la línea de la onda sigue subiendo por
encima de ellas. Eso es exactamente lo que las *Known Limitations* de la spec
describen como «silencioso en el sonido y visible solo en el panel»: el panel lo
enseña sin decir nada.

### Nueve barras y no dieciséis (FR13) — **cumple**

Con un Track de 9 Steps y 4 Pulses el panel dibuja **nueve** barras, con las
alturas de la serie que `ModulationOffsetTests` fija por número:

```
64 · 91 · 119 · 106 · 78 · 51 · 23 · 8 · 36
```

Cuatro claras —los pulsos euclidianos— y cinco atenuadas. Los Steps que no
disparan **llevan su altura igualmente**, que es lo que hace que la onda se lea
entera en vez de como cuatro barras sueltas.

### La etiqueta de contexto (FR16, FR17) — **cumple**

Dice `track 01 · cycle 01`, con dos cifras y ancho fijo. **Es etiqueta y no
selector**: no lleva la franja de doce que sí tiene `scale`.

### El pie y el card resumen (FR15, FR19) — **cumple**

`1 cycle per pattern` al pie del panel, `bipolar velocity` bajo el slider, y el
card resumen repite `waveform` y `accent` con el valor con signo.

### La lectura grande — **cumple**

`0` sin signo con el neutro; `+100` en mauve con el accent al extremo. El signo
se ve en el positivo, como pide el formato que vive en `Engine`.

## Tres defectos encontrados mirándolo, y corregidos

Van aquí porque son la justificación de esta tarea: los tres pasaban los tests.

1. **`saw` se dibujaba como una escalera dentada.** El paso vertical se aplicaba
   en cada muestra de `saw` y de `pulse`; `pulse` salía bien —dos valores, el
   escalón coincide con la forma— y `saw` no. Lo que distingue un corte de una
   pendiente es el **tamaño del salto**, no de qué onda se trate.
2. **`layoutPriority` no reparte proporciones.** Se usó para el 70/30 de FR11 y
   la prioridad decide *quién pide primero*, no *cuánto*: la columna derecha
   bajaba a unos cuarenta puntos, con `accent` partido en una letra por línea.
3. **La línea de centro tapaba las barras** y parecía partir cada una en dos, y
   **la onda del panel trazaba dos ciclos** cuando el panel es una vuelta —que es
   exactamente un ciclo (FR4)—. Dos decían que la modulación va al doble de
   velocidad de la que va.

## Veredicto

**La pantalla cumple lo que el handoff pide, en todo lo que el simulador alcanza.**
Queda para el dispositivo el criterio 13 —que el acento se **oiga**—, el playhead
del panel (FR14) y el gesto del slider con su imantado (FR18).
