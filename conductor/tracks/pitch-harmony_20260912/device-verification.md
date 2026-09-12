# Verificación en dispositivo — Pitch y Harmony

**Fecha:** 2026-09-12
**Dispositivo:** iPad (modelo no anotado)
**Hardware:** iPad + Arturia BeatStep Pro
**Resultado:** **OK**, confirmado por el usuario. Todas las comprobaciones de la
FASE 8 pasaron; no se registraron casos abruptos ni estancados.

**Una sola pasada, al final.** El iPad no estuvo disponible durante la
implementación, así que desde la FASE 5 los checkpoints cerraron con las pruebas
automáticas y la verificación en dispositivo de las FASES 3 a 7 se hizo aquí, de
una vez (enmienda del 2026-09-12 en `plan.md`).

## Lo que se comprobó

| Fase | Comprobación | Resultado |
|---|---|---|
| 3 — Pitch | El knob 14 transpone en grados, también en negativo; el valor se conserva al cambiar Scale; los pads muestran el pool base; sobrevive a relanzar | OK |
| 4 — Harmony | Desde C3 E3 G3, el knob 15 da D3 E3 G3 → D3 F3 G3 → D3 F3 A3 y un clic inverso C3 F3 A3 | OK |
| 4 — Harmony | Con Harmony en C3 F3 A3, Pitch +1 da D3 G3 B3 y Pitch 0 vuelve a C3 F3 A3 | OK |
| 4 — Harmony | Un pad que edita el pool y un cambio de Scale limpian Harmony y conservan Pitch; el siguiente clic mueve la nota más grave | OK |
| 4 — Harmony | Relanzar conserva el estado y el cursor: desde C3 F3 A3, un clic da C3 G3 A3 | OK |
| 5 — MIDI Learn | Un proyecto antiguo recibe los knobs 14 y 15; Pitch aprendido en otro knob sobrevive; Steps en el 14 deja Pitch sin control y así sigue al relanzar; el botón de fábrica restaura | OK |
| 6 — Temp y Ctrl All | Con [step 13] Pitch se iguala y Harmony da un paso por Cycle, y los dos vuelven al soltar. Con [step 14] Pitch desplaza los doce Tracks y Harmony se recalcula desde la base; soltar devuelve todo | OK |
| 7 — Pantalla | El card Tonal muestra `pitch` y `harmony`; `scale` ilumina el pool base con su línea de transformación; el valor grande anuncia los dos giros | OK |
| Oído | Pools de 2, 3 y 4 pitches en major, minor y pentatonic, giros lentos y rápidos, cambios de sentido | OK, sin casos abruptos ni estancados |

## Sin medición de jitter

Por la suspensión del 2026-09-02 y porque el track no desplaza ningún instante:
cambia qué suena, no cuándo, y el pool que suena se calcula en el hilo de
control (NFR4).
