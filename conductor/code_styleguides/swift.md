# Swift Style Guide — Torax H-0

Complementa `general.md` con convenciones de Swift y las reglas de tiempo real específicas de este proyecto.

> Nota: esta guía es propia del proyecto. La librería de Conductor no incluye una guía de Swift.

## Convenciones de lenguaje

- Sigue las [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) de Swift.
- `UpperCamelCase` para tipos, `lowerCamelCase` para todo lo demás.
- `struct` por defecto; `class` solo cuando se necesita identidad o ciclo de vida por referencia.
- `let` por defecto; `var` solo cuando la mutación es intencional.
- Sin abreviaturas inventadas: `pulses`, no `pls`.
- Evita el `self.` explícito salvo donde el lenguaje lo exija.

## Vocabulario del dominio

**Los nombres del código usan los términos de la Pre Spec, en inglés, sin sinónimos:** `steps`, `pulses`, `rotate`, `division`, `velocity`, `sustain`, `timing`, `delay`, `probability`, `scale`, `root`, `pitch`, `cycle`, `bank`, `pattern`, `track`.

No inventes un segundo nombre para un concepto ya nombrado. `trigger` y `pulse` no son intercambiables; `pool` no es `chord`.

## Tipado del dominio

Prefiere tipos específicos a primitivos desnudos donde el dominio tiene unidades o rangos:

- Ticks musicales, timestamps de host y valores MIDI no son `Int` intercambiables.
- Los rangos de la Pre Spec (Steps 1–64, Probability 0–100%) se validan en el tipo o en el inicializador, no en cada sitio de uso.

## Reglas de tiempo real — el camino del scheduler

Estas reglas aplican a **todo código que se ejecute en el hilo del scheduler MIDI**. Violarlas produce jitter, que es exactamente el criterio de éxito del proyecto.

En ese camino, **nunca**:

- Asignar memoria (sin `Array` que crezca, sin `String`, sin boxing de existenciales).
- Tomar locks o esperar en semáforos.
- Usar `await` o cualquier construcción que pueda suspender.
- Llamar a Objective-C dinámico, `print`, logging o I/O de fichero.
- Tocar UIKit o SwiftUI.

En su lugar:

- Buffers preasignados y estructuras de tamaño fijo.
- Lectura de un **snapshot inmutable** del estado, publicado atómicamente desde el hilo principal.
- Comunicación hacia la UI por valores publicados, nunca por callbacks síncronos.

**Marca esos límites en el código.** Toda función que corra en el hilo de timing lleva un comentario declarándolo:

```swift
/// Realtime: llamado desde el hilo del scheduler.
/// Sin asignaciones, sin locks, sin await.
```

## Pureza del motor

El paquete `Engine` no importa CoreMIDI, SwiftUI ni UIKit — solo la stdlib. El compilador lo garantiza; no lo relajes por conveniencia.

Las funciones del motor son **deterministas**: para el mismo estado y la misma semilla, la misma salida. El aleatorio entra siempre como PRNG sembrado y explícito; **nunca `Int.random()` ni `.randomElement()`**, que rompen la reproducibilidad que la Pre Spec exige.

## Concurrencia

- El estado compartido cruza hilos como valor inmutable, no como referencia mutable.
- El hilo principal es el único que muta el estado de edición.
- Si aparece un lock en el camino del scheduler, el diseño está mal: revísalo, no lo optimices.

## Errores

- `throws` para fallos recuperables; `fatalError` solo para invariantes rotos en tiempo de programación.
- Nada de `try!` ni de force unwrap (`!`) fuera de tests, salvo con un comentario que justifique el invariante.
- Los fallos de MIDI (dispositivo desconectado, envío fallido) son estados esperados, no errores excepcionales.

## Documentación

Documenta el *porqué*, según `general.md`. En este proyecto, dos cosas se documentan siempre:

1. **Decisiones de timing** — por qué un offset es el que es, por qué se calcula ahí.
2. **Divergencias de la Pre Spec** — si el código se aparta del documento de diseño, el comentario dice por qué.

## Tests

- Los tests del motor no requieren simulador ni hardware.
- Los casos de la Pre Spec son casos de test literales: 16/4, 16/5, 12/7 en distribución euclidiana.
- La reproducibilidad del PRNG sembrado se testea explícitamente: misma semilla, misma secuencia.
