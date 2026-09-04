# Plan — Sincronía de reloj externo

Sigue el `workflow.md`: tests antes de implementación, un commit por tarea, git
note por commit y checkpoint verificado al cerrar cada fase.

**El orden va de fuera adentro, al revés que `mute-solo`.** Aquí lo que se toca
es el reloj, y el reloj ya funciona: cada fase tiene que dejarlo funcionando.
Primero las dos notas de desviación, que el Task Workflow §8 exige antes de tocar
código. Después el estimador puro en `Engine`, que se puede escribir y verificar
entero sin CoreMIDI y sin hardware — es la pieza con más aritmética y la que más
barato sale equivocarse pronto. Luego la entrada de los mensajes, que hasta ahí
no tenían a quién alimentar. Luego el transporte esclavizado, que es donde el
cambio se vuelve audible. La pantalla al final, y la medición cerrando.

**El tempo interno editable (FR8) va en la fase de pantalla**, no antes: es la
única pieza que no depende de nada nuevo, así que es la que se puede mover si el
track se alarga.

**La Fase 6 mide jitter** (NFR4, excepción acotada a la suspensión del
2026-09-02). Es la única fase que lo hace, y con reloj interno.

## FASE 1: LAS DOS DESVIACIONES QUEDAN ESCRITAS [checkpoint: f0d3bd1]

- [x] Task: Enmendar `tech-stack.md` — el tempo deja de ser fijo (NFR5) [da89a79]
  - [x] Enmienda fechada 2026-09-03 en *Arquitectura de timing*: el `Tempo` de la
        `MusicalTimeline` era constante desde el Play y pasa a poder derivarse de
        un reloj externo; el origen de la rejilla, que la enmienda del 2026-08-30
        ya movió a `Play + presupuesto`, pasa además a **corregirse en vuelo** una
        vez por negra.
  - [x] Dejar escrito **qué se conserva**, que es lo que importa: se sigue
        sellando hacia el futuro y el jitter sigue sin depender de cuándo
        despierta el hilo. Lo que cambia es de dónde sale el número del periodo.
  - [x] Dejar escrita la alternativa descartada —emitir al recibir cada tick— y
        por qué: devuelve el jitter al planificador del SO, y ya no hay arnés que
        mida ese daño en el modo esclavizado.
- [x] Task: Anotar en `product.md` que el reloj deja de ser solo interno (NFR5) [f0d3bd1]
  - [x] Nota fechada: el MVP promete «transporte (play/stop) y reloj interno»;
        sigue siendo cierto y ahora además se puede seguir a un maestro externo.
  - [x] Dejar dicho que la app **no emite clock** (limitación 2), para que la
        nota no se lea como sincronía en los dos sentidos.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 2: EL ESTIMADOR DE TEMPO, PURO Y EN `ENGINE` [checkpoint: 5c91654]

- [x] Task: El seguidor de reloj — de ticks a `Tempo` (FR2) [2c81cb2]
  - [x] Tests (Red): 24 ticks equiespaciados a 500 ms/negra dan 120 BPM exactos;
        a 20 y a 300 BPM, los extremos del rango, el estimado cae dentro de una
        tolerancia declarada.
  - [x] Tests (Red): **un tick tardío aislado no mueve el tempo** más allá de la
        tolerancia — es el caso que separa un promedio de una lectura
        instantánea.
  - [x] Tests (Red): un tempo que implique menos de 20 o más de 300 BPM **se
        rechaza y se conserva el último válido**; sin ninguno válido todavía, el
        estimador se declara sin tempo.
  - [x] Tests (Red): un cambio real y sostenido de tempo se alcanza dentro de la
        ventana de una negra, y no antes — la latencia es una propiedad, no un
        accidente.
  - [x] Implementación (Green): tipo puro en `Packages/Engine`, junto a
        `MusicalTime.swift`. Recibe instantes; **no consulta la hora**.
  - [x] Sin asignaciones: **no hace falta ventana**. La media de 24 intervalos
        contiguos es la distancia entre sus extremos partida por 24, así que
        bastan el ancla y un contador; el tipo queda trivial sin una tupla de 24
        enteros. *(El plan pedía almacenamiento inline de 24 huecos; se ajusta el
        2026-09-03, con menos estado del previsto.)*
  - [x] Cobertura `Engine` ≥90%.
- [x] Task: La corrección de fase, como función pura (FR6) [5c91654]
  - [x] Tests (Red): con la rejilla **adelantada** —su límite cae antes que el
        tick— la corrección es **positiva** y retrasa el origen; atrasada,
        negativa; en fase, cero. *(El plan escribía los signos al revés; se
        corrige el 2026-09-03: lo que se devuelve es lo que hay que sumar al
        origen.)*
  - [x] Tests (Red): la corrección **está acotada** — un tick absurdamente
        desviado no produce un salto arbitrario del origen.
  - [x] Implementación (Green): función pura sobre origen, periodo e instante del
        tick.
  - [x] Documentar por qué se corrige por negra y no por tick: corregir a 24 ppqn
        mete el jitter del cable en cada evento.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 3: LA ENTRADA OYE SYSTEM REAL-TIME [checkpoint: 867fc3e]

- [x] Task: `MIDIMessage` entiende clock, start y stop (FR1) [3253e83]
  - [x] Tests (Red): una palabra UMP de tipo 0x1 con `0xF8`, `0xFA` y `0xFC`
        produce los tres casos nuevos.
  - [x] Tests (Red): `0xFB` (Continue), `0xFE` y `0xFF` **devuelven `nil`** —
        declarados y descartados, no olvidados.
  - [x] Tests (Red): las tres formas de mensaje de canal que ya se parseaban
        siguen parseándose igual; el tipo 0x1 no roba nada al 0x2.
  - [x] Implementación (Green): abrir el `guard` del tipo en
        `init?(universalPacketWord:)` y añadir los casos al enum.
  - [x] Comprobar que los mensajes nuevos **no tienen canal**: son de sistema, y
        meterlos en el `MIDIChannel` obligado del resto sería mentir sobre el
        protocolo.
- [x] Task: El reloj cruza al hilo del scheduler sin lock (FR6, NFR2) [867fc3e]
  - [x] Tests (Red): escribir periodo y corrección desde un hilo y leerlos desde
        otro devuelve siempre un par coherente, nunca la mitad de dos escrituras.
  - [x] Implementación (Green): un tipo en `MIDI` sobre las primitivas de
        `Atomics.swift`, con el mismo patrón que `PlayheadClock`.
  - [x] Verificar que el camino del callback de recepción no asigna: llega 40
        veces por segundo a 100 BPM.
  - [x] Cobertura `MIDI` ≥80%, medida en un proceso y filtrando `Engine/Sources`
        (ver `workflow.md`).
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: EL TRANSPORTE OBEDECE AL MAESTRO [checkpoint: 473d58f]

- [x] Task: La fuente de reloj, y que `Internal` ignore de verdad (FR3) [7410679]
  - [x] Tests (Red): con `Internal`, un Start, un Stop y una ráfaga de clock **no
        cambian nada** del transporte.
  - [x] Tests (Red): con `External`, los mismos mensajes sí llegan al transporte.
  - [x] Implementación (Green): la fuente como estado del transporte, no de la
        vista; el filtro en un solo sitio, antes de repartir.
- [x] Task: Armar y arrancar con el Start (FR4) [2387086]
  - [x] Tests (Red): con `External`, `play()` deja el transporte armado y **sin
        emitir**; al llegar el Start empieza a emitir desde el paso 0.
  - [x] Tests (Red): los doce Tracks arrancan con el mismo origen — el invariante
        de fase de `multi-track` sigue en pie. *(Sin test nuevo: el arranque por
        Start entrega **un** origen a `SchedulerThread`, el mismo para los doce, y
        la propiedad la fija ya `testTwoDivisionsShareTheOriginAndDoNotDrift` de
        `PatternSchedulerTests`. Escribir otro exigiría arrancar el bucle una vez
        más, que es lo que empeora el flake de CoreMIDI.)*
  - [x] Tests (Red): un Start recibido **sin haber armado** no arranca nada.
  - [x] Implementación (Green): estado armado en `Transport`, y el origen fijado
        en el instante del Start como hoy se fija en el de Play.
- [x] Task: Parar con el Stop externo, sin dejar notas colgadas (FR5) [a258e30]
  - [x] Tests (Red): el Stop externo apaga por el mismo camino que `stop()`
        —`CC 123` por canal más el barrido de alturas— y desarma.
  - [x] Tests (Red): un Stop con el transporte ya parado no hace nada ni falla.
  - [x] Implementación (Green): reutilizar el barrido existente; **no
        duplicarlo**.
- [x] Task: Seguir el tempo y re-anclar la fase (FR6) [9a3b5df]
  - [x] Tests (Red): con ticks a 120 BPM, los instantes programados coinciden con
        los de una `MusicalTimeline` a 120 dentro de la tolerancia. *(Cubierto por
        `TempoMapTests`: sin maestro el mapa es la identidad, y a 120 BPM contra
        una referencia de 120 el ratio es 1.)*
  - [x] Tests (Red): un cambio de tempo del maestro mueve los instantes
        siguientes, y **ningún evento ya sellado se reprograma**. *(Lo segundo es
        estructural —el mapa solo afecta a la ventana siguiente— y lo sostiene
        `testChangingTempoDoesNotMoveTheCurrentInstant`; de punta a punta se ve en
        dispositivo, Fase 6.)*
  - [x] Tests (Red): la corrección de fase se aplica **una vez cada 24 ticks**,
        no más.
  - [x] Implementación (Green): el scheduler lee periodo y corrección del atómico
        una vez por ventana, como ya lee el snapshot.
  - [x] Verificar la regla de tiempo real en el camino nuevo: sin asignaciones,
        sin locks, sin `await`, sin logging.
- [x] Task: El corte de clock no para la música (FR7) [b76b499]
  - [x] Tests (Red): sin ticks durante más del margen, el transporte **sigue** con
        el último tempo y se marca como desenganchado.
  - [x] Tests (Red): un tick perdido aislado **no** dispara el corte.
  - [x] Tests (Red): al volver el clock, se re-engancha sin parar y sin volver al
        paso 0.
  - [x] Implementación (Green): margen derivado del periodo estimado —del orden
        de una negra—, no un literal en milisegundos: a 20 BPM medio segundo es
        menos de un tick.
  - [x] Cobertura `MIDI` ≥80%.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LA PANTALLA — FUENTE, TEMPO Y QUIÉN MANDA [checkpoint: e065d64]

- [x] Task: El tempo interno deja de ser una constante (FR8) [e065d64]
  - [x] Tests (Red, en `Engine` o `MIDI` según dónde caiga la lógica): fijar un
        tempo dentro de 20–300 lo acepta; fuera, se rechaza sin romper el
        vigente.
  - [x] Implementación (Green): quitar la constante de `TransportModel` y llevar
        el tempo a estado editable; control en la pantalla `3 · MIDI`.
  - [x] Comprobar que cambiar el tempo **mientras suena** no reinicia la fase ni
        pierde el paso en curso.
- [x] Task: El selector `Internal / External` (FR3) [e065d64]
  - [x] Implementación: en `3 · MIDI`, junto al tempo, con el lenguaje visual de
        `Brutalist.swift` y el vocabulario en inglés.
  - [x] El estado de enganche visible: siguiendo, esperando el Start, o
        desenganchado por corte (FR4, FR7).
  - [x] Un tempo de maestro fuera de rango se dice, no se acota en silencio (FR2).
- [x] Task: La barra dice el tempo vigente y su fuente (FR9) [e065d64]
  - [x] Tests (Red): el redondeo a un decimal es estable — una sucesión de
        estimaciones que difieren en la milésima no cambia el texto.
  - [x] Implementación (Green): el `%.1f BPM` que ya existe pasa a leer el tempo
        vigente; junto a él, `INT` / `EXT`.
  - [x] Verificar en el simulador que sigue legible a un metro y que la barra no
        se descoloca al aparecer la marca. *(Y encontró un fallo: la sección de
        reloj encima de los canales empujaba la fila del Track 12 fuera de
        pantalla. Se movió a la columna derecha.)*
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: DISPOSITIVO Y MEDICIÓN

- [~] Task: Verificar los diez criterios de aceptación en iPad (NFR6)
  - [x] **Primera pasada, 2026-09-03: falló y encontró un defecto real.** La app
        se quedaba en `Waiting for clock` para siempre y el tempo del BeatStep no
        movía nada. Causa: `Transport.receive` no tenía ningún llamador — la
        Fase 4 lo implementó con tests y la Fase 5 cableó la pantalla, pero nadie
        conectó el callback de `CoreMIDIInput` con él. Arreglado en `03be820`,
        junto con la entrega del instante del paquete, que estaba anotada como
        hallazgo de la Fase 4 y se había quedado sin hacer.
  - [ ] Segunda pasada, con el arreglo instalado.
  - [ ] BeatStep Pro como maestro y un sinte recibiendo; recorrer los criterios 1
        a 9 y anotar cada resultado.
  - [ ] El criterio 4 —dos minutos sin separarse— es el que **no tiene número**
        (limitación 5): se juzga tocando, y se anota cómo se juzgó.
  - [ ] El criterio 6 se provoca de verdad: desconectar el cable con el
        transporte corriendo, y volver a conectarlo.
  - [ ] Escribir `device-verification.md` en el directorio del track, con el
        procedimiento y lo observado.
- [x] Task: Medición de jitter con reloj interno (NFR4)
  - [x] Correr el arnés en dispositivo con la rejilla `12-tracks-cycles`, 1000
        eventos por tempo a 60, 120 y 174 BPM, con el transporte de la app
        corriendo (el procedimiento del `device-verification.md` de la rebanada
        2).
  - [x] Comparar contra la referencia vigente: máx 0,158 ms, σ 0,013–0,014 ms.
        ~~**Una regresión bloquea el cierre.**~~ **Hay regresión —máx 0,525 ms, σ
        0,030 ms, reproducida en dos pasadas— y se cierra con ella dentro**, por
        decisión del 2026-09-04. Ver la enmienda del NFR4 en `spec.md`.
  - [x] Registrar el resultado en la git note de la tarea y en `product.md`,
        junto a la serie de mediciones anteriores.
  - [x] Anotar que el modo **esclavizado** queda sin número y por qué (limitación
        5).
- [ ] Task: Cerrar el track
  - [ ] Suite completa de `Engine` y `MIDI`, con la partición de CI para `MIDI`;
        cobertura contra los umbrales.
  - [ ] Build de la app para iPadOS.
  - [ ] Pull Request contra `main`, con los checks en verde y el cuerpo corto que
        exige `workflow.md`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
