# Spec — Reducción a 12 Tracks, pantalla MIDI y limpieza del selector

**Tipo:** Refactor de UI · **Fecha:** 2026-09-02

## Overview

Tres ajustes sobre la pantalla entregada por la v2 (rebanadas 1–3), todos en la
misma dirección: **menos ruido para que el protagonista —los anillos— tenga
sitio**.

1. El **canal** deja de vivir en la pantalla Track. Es ruteo MIDI, no material
   del Track, y su sitio es la pantalla `3 · MIDI`, que hoy es un placeholder en
   discontinuo.
2. El **botón de Track** dice dos veces el mismo número: `index+1` arriba y
   `channel.number` debajo, que por defecto coinciden — `Pattern.init()` asigna
   Track N → canal N. Se queda solo el número.
3. **12 Tracks en vez de 16.** `RingStack` reparte el ancho entre
   `Pattern.trackCount − 1` bandas, así que doce anillos son un tercio más
   anchos sin tocar el dibujo.

Los tres son de superficie: ninguno añade capacidad musical.

## Functional Requirements

**FR1 — `Pattern.trackCount = 12`.** La tupla pasa a doce `Track`.
`Pattern.init()` mantiene la correspondencia Track N → canal N, ahora 1–12; los
canales 13–16 siguen siendo elegibles a mano desde la pantalla MIDI.

**FR2 — Anillos más anchos, sin cambiar la metáfora.** `RingStack`, `Playhead`
y `CyclePosition` derivan de `trackCount`: doce bandas salen del mismo código.
Ninguna constante de ancho se escribe a mano.

**FR3 — Step buttons 13–16 no seleccionan Track.** `ControlMapping` sigue
describiendo las dieciséis del hardware —es la tabla del preset—; quien acota es
la selección de Track, que ignora índices ≥ 12 con el mismo criterio que un CC
sin asignar: no publica y no es un error. `preset/` no cambia.

**FR4 — El botón de Track dice solo su número.** Se conservan los tres estados
de hoy: relleno de acento el elegido, acento en el trazo el que tiene material,
borde en reposo el vacío. Doce pastillas en una fila, por la misma razón que
había dieciséis en una: el orden es el de los step buttons.

**FR5 — La pantalla `3 · MIDI` existe.** Pierde el borde discontinuo y entra en
`Screen`; `unavailableScreens` queda en `["4 · Banks", "5 · Tracks"]`.

**FR6 — El canal se edita ahí, los doce a la vez.** Una fila por Track —`Track N`
y su selector de canal 1–16—, de modo que el ruteo completo se lee de un vistazo
y un choque de canales se ve sin recorrer Track por Track. Sigue siendo táctil,
como Scale y Root: `product-guidelines.md` pone la configuración del lado de la
pantalla.

**FR7 — La pantalla Track pierde su fila `Channel`.** La fila `Cycles` se queda
donde está.

**FR8 — El arnés queda coherente.** La rejilla `16-tracks-cycles` pasa a
`12-tracks-cycles` con `trackCount: 12`. Cambio mecánico: **no se mide**
(suspendido el 2026-09-02).

**FR9 — La desviación queda escrita.** Nota fechada en `Pre Spec Torax H-0.md` y
en `product.md`: doce Tracks, y por qué —legibilidad de los anillos—, antes de
implementar (Task Workflow §8).

## Non-Functional Requirements

- **NFR1** — `_isPOD(Pattern.self)` sigue siendo cierto; sin asignaciones, locks
  ni `await` en el camino del scheduler.
- **NFR2** — `Engine` no importa nada fuera de la stdlib.
- **NFR3** — Cobertura: `Engine` ≥90%, `MIDI` ≥80%. `App` no se mide.
- **NFR4** — Vocabulario de la Pre Spec, sin sinónimos nuevos.
- **NFR5** — Los tres ficheros de `App` que poseen color, tipografía y borde
  siguen siendo los únicos: la pantalla MIDI no inventa estilo propio.
- **NFR6** — **Sin medición de jitter**, suspendida el 2026-09-02.

## Acceptance Criteria

1. La pantalla Track muestra **doce** pastillas, cada una con **un solo
   número**, y sus tres estados se distinguen a un metro.
2. Los doce anillos son visiblemente más anchos y el playhead se lee sin
   acercarse.
3. `3 · MIDI` es pulsable y muestra doce filas `Track N → canal`; cambiar un
   canal se oye en el destino correcto.
4. La pantalla Track ya no tiene fila `Channel`.
5. Pulsar los step buttons 1–12 selecciona; 13–16 no hacen nada y no rompen.
6. `swift test` en `Engine` y `MIDI` pasa; `xcodebuild build` compila para iOS.
7. La Pre Spec y `product.md` llevan la nota fechada del 16 → 12.

## Out of Scope

- **MIDI Learn** — sigue siendo la rebanada 8 de la v1; se le añadirá a esta
  misma pantalla.
- **Mover destino/origen MIDI** desde la barra superior a la pantalla MIDI.
- **Medición de jitter** — suspendida.
- Patterns, Banks, persistencia.
