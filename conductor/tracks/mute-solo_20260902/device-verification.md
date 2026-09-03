# Verificación en dispositivo — Mute y Solo por Track

**Ejecutada el 2026-09-02** en iPad con BeatStep Pro y sintetizador externo.
Resultado: **los diez criterios de aceptación, verificados.**

**Sin medición de jitter** (NFR6, suspendida el 2026-09-02). Este track decide
*si* se emite, no *cuándo*: no toca la rejilla, el scheduler ni la matemática de
tiempo.

---

## 0. Antes de empezar

- [x] **Los encoders del BeatStep Pro en `Relative #2`**, en MIDI Control Center.
      Nota del 2026-08-28 en `workflow.md`.
- [x] **El multitímbrico conectado**, con varios canales sonando distinto: sin
      eso no se puede juzgar que callar uno no calla a los demás.
- [x] **Sonando lo entregado hasta la Fase 5.** Si algo no suena antes de tocar
      un botón M, no es este track.

---

## 1. Lo que se verificó

| # | Criterio | Resultado |
|---|---|---|
| 1 | `M` calla el Track antes de su siguiente pulso y apaga lo que sonaba por su canal; el resto no se altera | ✅ |
| 2 | Quitar el mute lo devuelve **en fase**, no desde el principio | ✅ |
| 3 | `S` en uno deja sonando a ese; en un segundo, a los dos; soltar ambos devuelve los doce | ✅ |
| 4 | Un Track soleado **y** muteado calla | ✅ |
| 5 | Step 16 mantenido + step 3 mutea el Track 3 **sin** mover la selección; la pantalla lo refleja | ✅ |
| 6 | Ídem con el 15 para solo | ✅ |
| 7 | El anillo del Track inaudible se atenúa y su **playhead sigue girando** | ✅ |
| 8 | Parar y arrancar conserva mutes y solos | ✅ |
| 9 | `Engine` sin un solo cambio; `_isPOD(Pattern.self)` pasa | ✅ (test) |
| 10 | Cobertura de `MIDI` ≥80% con máscara, regla, gate y modificadores cubiertos | ✅ 92,19% |

**Los dos que más importaban al oído, y por qué:**

- **El criterio 2** es la promesa entera de la feature. Un mute que devolviera el
  Track al principio del anillo sería un stop con otro nombre, y la diferencia
  solo se oye: en pantalla las dos cosas se ven igual.
- **El criterio 1 con Sustain al 200% sobre una Division larga** es el modo de
  fallo caro. Sin el barrido de FR4, mutear a mitad de nota deja el sintetizador
  sonando segundos después de haber pulsado el botón.

---

## 2. Lo que esta verificación no cubre

- **La ventana de look-ahead.** Un note-on ya entregado a CoreMIDI con timestamp
  futuro suena aunque el mute llegue después. Son 20 ms: por debajo de lo
  perceptible en este gesto, y no se intentó medir.
- **Dos Tracks en el mismo canal.** El `CC 123` es un mensaje de canal, así que
  apagar uno corta las notas del otro; el otro vuelve en su siguiente pulso. No
  se montó el caso a propósito: está documentado en `Transport.silence` y la
  pantalla MIDI existe para verlo venir.
- **Jitter.** Suspendido.
