# Track: v2 rebanada 4 — Persistencia: Patterns y Banks

**ID:** `persistence_20260907` · **Type:** Feature · **Status:** new

Hasta hoy la app tiene **un** `Pattern` y cerrarla lo pierde entero. Esta
rebanada hace las dos cosas que faltan para que deje de ser cierto: el árbol
crece los dos niveles que la Pre Spec pone encima —**16 Banks de 16 Patterns**,
cada Bank con su tempo— y aparece el **disco**.

Es el primer track del proyecto que escribe un fichero. Todo lo anterior vivía en
memoria porque el material cabía en una sesión; con Cycles dentro, cada Pattern
son doce Tracks por dieciséis Cycles, y perder eso al salir es perder dieciséis
veces más trabajo que antes de la rebanada 3.

**Y la pantalla `banks` deja de ser cáscara.** El rediseño del handoff la entregó
dibujando dieciséis huecos de banco y dieciséis de pattern de los que solo el
primero existía, con la promesa escrita en su propio encabezado: «el día que
exista el modelo de `Bank` —la rebanada 4 de la v2— esta pantalla deja de ser
cáscara **sin cambiar de forma**». La forma se respeta; lo que cambia es que
detrás hay algo.

**Sí es una rebanada de motor, y la entrada del registro decía que no.** Cambiar
de Pattern con el transporte corriendo es **cuantizado al próximo compás de
cuatro negras**, y esa decisión la toma el hilo del scheduler en el límite. El
snapshot no crece ni un byte y no hay trabajo nuevo por evento, pero hay una
lectura atómica más por ventana y una adopción de ranura dentro del hilo de
tiempo real. Se elige igualmente porque un Pattern que solo entra parando es un
fichero, no la «sección de live» que la Pre Spec promete. La Fase 1 lo escribe
fechado antes de tocar código.

**El Pattern entrante se arma y lo adopta el scheduler.** `PatternHandoff` no
cambia de protocolo: gana un contador de generación para lo armado, que el lector
consulta una vez por ventana. El instante lo decide quien conoce la rejilla, y no
el hilo principal observando el playhead.

**Las notas que cruzan el límite terminan como estaban programadas.** Sin
all-notes-off: el note-off ya viaja sellado con timestamp por el look-ahead, así
que la cola de la frase anterior se solapa con la nueva en vez de cortarse en
seco.

**Dos capas de guardado, como en la Pre Spec.** El **Autosave** protege el
trabajo en curso —debounce tras la calma, forzado al pasar a segundo plano, y
solo el Bank tocado—; **`Save Bank`** fija el punto de retorno intencional de un
Bank y **`Reload`** vuelve a él. Reload es cuantizado, no lleva confirmación y no
está disponible en un Bank que nunca se guardó: sin punto de retorno, volver a
vacío no es volver, es borrar.

**En disco: un fichero por Bank más uno de Project**, JSON indentado en
Application Support, escritura atómica y `schemaVersion` desde el primer commit.
Un Pattern vacío se escribe como una marca y no como 37 KB de ceros. Un fichero
ilegible o de versión desconocida se **aparta con marca de tiempo** y la app
arranca vacía diciéndolo: nunca se pierde el fichero del usuario y nunca se queda
la app sin abrir.

**Los DTO no son los tipos de tiempo real.** Tipos `Codable` espejo traducen
desde y hacia los POD, así que mover un campo de `Cycle` por razones de tiempo
real no puede romper un fichero guardado. `_isPOD(Pattern.self)` sigue vigilando
exactamente lo que vigila hoy; `Bank` y `Project` no lo pretenden y viven en el
hilo principal con arrays.

**Entra un paquete SPM nuevo, `Persistence`.** Es un cambio de tech stack y la
Fase 1 lo documenta antes de implementarlo. No cabe en lo que hay: `Engine` no
importa nada fuera de la stdlib y `JSONEncoder` es Foundation, `MIDI` es
CoreMIDI, y `App` **no se mide** — dejar ahí el guardado sería dejar sin cobertura
la única pieza capaz de perder el trabajo del usuario. Umbral: ≥90%.

**No lleva medición de jitter**, y por dos razones independientes: la medición
está suspendida desde el 2026-09-02, y esta rebanada **no mueve ningún instante**
—cambia qué material se emite en un límite que ya existía—, así que ni bajo la
regla anterior habría exigido arnés.

**Lo que deja fuera:** Backup Project (exportar/importar por Files), Program
Change, encadenado de Patterns, disparo desde el controlador —no quedan step
buttons libres—, nombres editables y copiar Banks.

## Documents

-   [Specification](./spec.md)
-   [Implementation Plan](./plan.md)
-   [Metadata](./metadata.json)

## Project Context

-   [Project Index](../../index.md)
-   [Rebanada 3 de la v2 — Cycles](../cycles_20260901/index.md): es lo que hay
    que guardar, y su limitación 1 —«sin persistencia»— la cierra este track.
-   [Rebanada 2 de la v2 — La pantalla del handoff](../screen-handoff_20260901/index.md):
    dejó fuera Banks, Patterns y la lista de Tracks; aquí llegan.
-   [Rediseño de las cuatro pantallas](../screens-redesign_20260906/index.md):
    entregó `banks` como cáscara y escribió la promesa que este track cobra.
-   [Rebanada 1 de la v2 — Dieciséis Tracks](../multi-track_20260831/index.md):
    el `PatternHandoff` que gana la ranura armada.
-   [Sincronía de reloj externo](../external-clock_20260903/index.md): con
    `External`, el tempo del Bank no manda.
-   [Mute y Solo por Track](../mute-solo_20260902/index.md): es mezcla y no
    material, así que no se guarda.
-   [Note Repeater](../note-repeater_20260906/index.md) y
    [LFO Modulation](../modulation_20260906/index.md): las dos añaden campos al
    `Cycle`, así que el primer cambio de esquema llega con ellas. Está escrito en
    las dependencias del `spec.md` y es la razón de que `schemaVersion` entre
    ahora.
