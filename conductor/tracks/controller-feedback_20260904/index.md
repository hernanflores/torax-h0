# Track — Feedback visual en el controlador

**Tipo:** Feature · **Creado:** 2026-09-04 · **Estado:** nuevo

Los pads del BeatStep siguen la nota del Track seleccionado —encendidos con el
note-on y apagados con el note-off, así que Sustain se ve— y los step buttons
dicen qué Track se edita y cómo está en la mezcla. Con un interruptor en
`3 · MIDI`, porque es la primera vez que la app escribe en un dispositivo ajeno.

## Documentos

- [Especificación](./spec.md)
- [Plan de implementación](./plan.md)
- [Metadatos](./metadata.json)

## Contexto

- **La Fase 1 puede cancelar el track**: si el BeatStep no ilumina por MIDI in, no
  hay feature que entregar y se cierra ahí con el hallazgo escrito (NFR1).
- **Sin medición de jitter** aunque duplica los mensajes por nota en el camino de
  tiempo real. Es la limitación 1 de la spec, y llega detrás de una regresión sin
  causa identificada en [`external-clock_20260903`](../external-clock_20260903/index.md).
- Es la segunda mitad de la petición del 2026-09-03; la primera fue la sincronía
  de reloj.
