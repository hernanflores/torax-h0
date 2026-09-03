# Track — Sincronía de reloj externo

**Tipo:** Feature · **Creado:** 2026-09-03 · **Estado:** nuevo

La app sigue el Start, el Stop y el reloj a 24 ppqn del BeatStep Pro, y deriva de
ahí el tempo. El look-ahead se conserva —tempo estimado, ventana corta— y la fase
se re-ancla una vez por negra. Con el reloj externo cortado, sigue sonando al
último tempo conocido; y el tempo interno deja de estar clavado en 120.

## Documentos

- [Especificación](./spec.md)
- [Plan de implementación](./plan.md)
- [Metadatos](./metadata.json)

## Contexto

- El feedback visual en el controlador **no entra aquí**: es el track siguiente,
  registrado sin planificar en [`tracks.md`](../../tracks.md).
- Toca la rejilla temporal, así que **retoma la medición de jitter** como
  excepción acotada a la suspensión del 2026-09-02 (NFR4).
- Enmienda `tech-stack.md` y `product.md` antes de tocar código (NFR5).
