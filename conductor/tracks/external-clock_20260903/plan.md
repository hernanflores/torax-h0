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

## FASE 3: LA ENTRADA OYE SYSTEM REAL-TIME

- [ ] Task: `MIDIMessage` entiende clock, start y stop (FR1)
  - [ ] Tests (Red): una palabra UMP de tipo 0x1 con `0xF8`, `0xFA` y `0xFC`
        produce los tres casos nuevos.
  - [ ] Tests (Red): `0xFB` (Continue), `0xFE` y `0xFF` **devuelven `nil`** —
        declarados y descartados, no olvidados.
  - [ ] Tests (Red): las tres formas de mensaje de canal que ya se parseaban
        siguen parseándose igual; el tipo 0x1 no roba nada al 0x2.
  - [ ] Implementación (Green): abrir el `guard` del tipo en
        `init?(universalPacketWord:)` y añadir los casos al enum.
  - [ ] Comprobar que los mensajes nuevos **no tienen canal**: son de sistema, y
        meterlos en el `MIDIChannel` obligado del resto sería mentir sobre el
        protocolo.
- [ ] Task: El reloj cruza al hilo del scheduler sin lock (FR6, NFR2)
  - [ ] Tests (Red): escribir periodo y corrección desde un hilo y leerlos desde
        otro devuelve siempre un par coherente, nunca la mitad de dos escrituras.
  - [ ] Implementación (Green): un tipo en `MIDI` sobre las primitivas de
        `Atomics.swift`, con el mismo patrón que `PlayheadClock`.
  - [ ] Verificar que el camino del callback de recepción no asigna: llega 40
        veces por segundo a 100 BPM.
  - [ ] Cobertura `MIDI` ≥80%, medida en un proceso y filtrando `Engine/Sources`
        (ver `workflow.md`).
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 4: EL TRANSPORTE OBEDECE AL MAESTRO

- [ ] Task: La fuente de reloj, y que `Internal` ignore de verdad (FR3)
  - [ ] Tests (Red): con `Internal`, un Start, un Stop y una ráfaga de clock **no
        cambian nada** del transporte.
  - [ ] Tests (Red): con `External`, los mismos mensajes sí llegan al transporte.
  - [ ] Implementación (Green): la fuente como estado del transporte, no de la
        vista; el filtro en un solo sitio, antes de repartir.
- [ ] Task: Armar y arrancar con el Start (FR4)
  - [ ] Tests (Red): con `External`, `play()` deja el transporte armado y **sin
        emitir**; al llegar el Start empieza a emitir desde el paso 0.
  - [ ] Tests (Red): los doce Tracks arrancan con el mismo origen — el invariante
        de fase de `multi-track` sigue en pie.
  - [ ] Tests (Red): un Start recibido **sin haber armado** no arranca nada.
  - [ ] Implementación (Green): estado armado en `Transport`, y el origen fijado
        en el instante del Start como hoy se fija en el de Play.
- [ ] Task: Parar con el Stop externo, sin dejar notas colgadas (FR5)
  - [ ] Tests (Red): el Stop externo apaga por el mismo camino que `stop()`
        —`CC 123` por canal más el barrido de alturas— y desarma.
  - [ ] Tests (Red): un Stop con el transporte ya parado no hace nada ni falla.
  - [ ] Implementación (Green): reutilizar el barrido existente; **no
        duplicarlo**.
- [ ] Task: Seguir el tempo y re-anclar la fase (FR6)
  - [ ] Tests (Red): con ticks a 120 BPM, los instantes programados coinciden con
        los de una `MusicalTimeline` a 120 dentro de la tolerancia.
  - [ ] Tests (Red): un cambio de tempo del maestro mueve los instantes
        siguientes, y **ningún evento ya sellado se reprograma**.
  - [ ] Tests (Red): la corrección de fase se aplica **una vez cada 24 ticks**,
        no más.
  - [ ] Implementación (Green): el scheduler lee periodo y corrección del atómico
        una vez por ventana, como ya lee el snapshot.
  - [ ] Verificar la regla de tiempo real en el camino nuevo: sin asignaciones,
        sin locks, sin `await`, sin logging.
- [ ] Task: El corte de clock no para la música (FR7)
  - [ ] Tests (Red): sin ticks durante más del margen, el transporte **sigue** con
        el último tempo y se marca como desenganchado.
  - [ ] Tests (Red): un tick perdido aislado **no** dispara el corte.
  - [ ] Tests (Red): al volver el clock, se re-engancha sin parar y sin volver al
        paso 0.
  - [ ] Implementación (Green): margen derivado del periodo estimado —del orden
        de una negra—, no un literal en milisegundos: a 20 BPM medio segundo es
        menos de un tick.
  - [ ] Cobertura `MIDI` ≥80%.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 5: LA PANTALLA — FUENTE, TEMPO Y QUIÉN MANDA

- [ ] Task: El tempo interno deja de ser una constante (FR8)
  - [ ] Tests (Red, en `Engine` o `MIDI` según dónde caiga la lógica): fijar un
        tempo dentro de 20–300 lo acepta; fuera, se rechaza sin romper el
        vigente.
  - [ ] Implementación (Green): quitar la constante de `TransportModel` y llevar
        el tempo a estado editable; control en la pantalla `3 · MIDI`.
  - [ ] Comprobar que cambiar el tempo **mientras suena** no reinicia la fase ni
        pierde el paso en curso.
- [ ] Task: El selector `Internal / External` (FR3)
  - [ ] Implementación: en `3 · MIDI`, junto al tempo, con el lenguaje visual de
        `Brutalist.swift` y el vocabulario en inglés.
  - [ ] El estado de enganche visible: siguiendo, esperando el Start, o
        desenganchado por corte (FR4, FR7).
  - [ ] Un tempo de maestro fuera de rango se dice, no se acota en silencio (FR2).
- [ ] Task: La barra dice el tempo vigente y su fuente (FR9)
  - [ ] Tests (Red): el redondeo a un decimal es estable — una sucesión de
        estimaciones que difieren en la milésima no cambia el texto.
  - [ ] Implementación (Green): el `%.1f BPM` que ya existe pasa a leer el tempo
        vigente; junto a él, `INT` / `EXT`.
  - [ ] Verificar en el simulador que sigue legible a un metro y que la barra no
        se descoloca al aparecer la marca.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)

## FASE 6: DISPOSITIVO Y MEDICIÓN

- [ ] Task: Verificar los diez criterios de aceptación en iPad (NFR6)
  - [ ] BeatStep Pro como maestro y un sinte recibiendo; recorrer los criterios 1
        a 9 y anotar cada resultado.
  - [ ] El criterio 4 —dos minutos sin separarse— es el que **no tiene número**
        (limitación 5): se juzga tocando, y se anota cómo se juzgó.
  - [ ] El criterio 6 se provoca de verdad: desconectar el cable con el
        transporte corriendo, y volver a conectarlo.
  - [ ] Escribir `device-verification.md` en el directorio del track, con el
        procedimiento y lo observado.
- [ ] Task: Medición de jitter con reloj interno (NFR4)
  - [ ] Correr el arnés en dispositivo con la rejilla `12-tracks-cycles`, 1000
        eventos por tempo a 60, 120 y 174 BPM, con el transporte de la app
        corriendo (el procedimiento del `device-verification.md` de la rebanada
        2).
  - [ ] Comparar contra la referencia vigente: máx 0,158 ms, σ 0,013–0,014 ms.
        **Una regresión bloquea el cierre.**
  - [ ] Registrar el resultado en la git note de la tarea y en `product.md`,
        junto a la serie de mediciones anteriores.
  - [ ] Anotar que el modo **esclavizado** queda sin número y por qué (limitación
        5).
- [ ] Task: Cerrar el track
  - [ ] Suite completa de `Engine` y `MIDI`, con la partición de CI para `MIDI`;
        cobertura contra los umbrales.
  - [ ] Build de la app para iPadOS.
  - [ ] Pull Request contra `main`, con los checks en verde y el cuerpo corto que
        exige `workflow.md`.
- [ ] Task: Phase Verification & Checkpoint (Refer to workflow.md)
