# Verificación en dispositivo — Torax H-0 como maestro de MIDI clock

**Fecha:** 2026-09-11
**Dispositivo:** iPad (modelo no anotado)
**Hardware:** iPad + BeatStep Pro + un esclavo con sync externo (modelo no
anotado)
**Resultado:** los ocho bloques **OK**, confirmados por el usuario.

> **Lo que este documento registra y lo que no.** Registra que los ocho bloques
> se ejecutaron y salieron bien. **No registra observaciones por bloque** —el
> usuario confirmó en bloque, «todo ok»— así que no hay aquí notas de lo que se
> oyó en cada uno. Se anota tal cual en vez de inventar detalle: lo que vale de
> una verificación en dispositivo es que ocurrió, y lo que no se escribió no se
> puede citar después.

## Por qué este guion sustituye a un número

No hay medición de jitter (NFR4, suspensión del 2026-09-02), y el arnés no sabría
medir esto aunque se retomara: mide instantes de nota contra su propio reloj, no
el pulso que sale hacia otro aparato. Lo que sustituye al número es **la escucha
larga del bloque 7**: un esclavo que se separa del maestro se oye, y se oye antes
de un compás.

## Preparación

1. Conectar el esclavo a la salida MIDI del iPad y ponerlo en **sync externo**.
2. En la pantalla `midi` de la app, elegir ese destino de salida.
3. Dejar el reloj en `Internal` para los bloques 1 a 4.

## Bloques

### 1 · Play arranca al esclavo (criterio 1)

- Pulsar Play en la app.
- **Esperado:** el esclavo arranca solo, sin tocarlo.
- **Resultado: OK.**

### 2 · Stop lo para (criterio 1)

- Pulsar Stop.
- **Esperado:** el esclavo para. Ninguna nota queda colgada, ni en el sinte ni en
  el esclavo.
- **Resultado: OK.**

### 3 · El tempo es el mismo, y se sigue al girarlo (criterio 2)

- Con el transporte corriendo, comprobar que el tempo del esclavo coincide con el
  de la app.
- Girar el tempo de la app arriba y abajo.
- **Esperado:** el esclavo lo sigue. No hay salto ni corte del pulso; el cambio
  entra de forma continua.
- **Resultado: OK.**

### 4 · Cambiar de Bank lleva su tempo (criterio 6)

- Con el transporte corriendo, cambiar a un Bank con otro tempo.
- **Esperado:** el esclavo adopta el tempo del Bank y el pulso no se corta.
- **Resultado: OK.**

### 5 · Parado no hay clock (criterio 4)

- Con el transporte parado, mirar un monitor MIDI —o el indicador de sync del
  esclavo—.
- **Esperado:** **cero mensajes**. El esclavo no muestra clock entrante y no
  arranca solo.
- **Resultado: OK.**

### 6 · Con reloj externo, los tres van juntos (criterio 3)

- Poner la app en `External` y arrancar desde el BeatStep Pro.
- **Esperado:** la app sigue al BeatStep y el esclavo sigue a la app. Los tres
  suenan alineados. Girar el tempo en el BeatStep mueve a los tres.
- **Lo que se acepta y hay que reconocer:** el esclavo va por detrás del BeatStep
  hasta una ventana más una negra cuando el tempo cambia de golpe — el pulso se
  regenera desde la estimación (limitación 1 del `spec.md`). Lo que **no** se
  acepta es que se separe y no vuelva.
- **Resultado: OK.**

### 7 · Escucha larga (lo que sustituye al arnés)

- Dejar sonando varios minutos con el esclavo, con reloj interno.
- **Esperado:** no se separan. Al final de la escucha siguen en fase, sin deriva
  acumulada.
- **Resultado: OK.**

### 8 · Carga: Repeats 8 y doce Tracks (criterio 7)

- Poner Repeats en 8 con varios Tracks sonando.
- **Esperado:** el pulso no se arrastra ni se atraganta; el esclavo no titubea.
- **Resultado: OK.**

## Lo que este guion no comprueba

- **Que el esclavo reciba su propio pulso de vuelta** si el destino elegido es el
  mismo aparato que manda el clock. Está decidido así (fuera de alcance del
  `spec.md`), y no se prueba aquí.
- **Continue y Song Position:** un esclavo que arranque a mitad no puede
  alinearse, porque no se emiten.
- **El número.** No hay medición de jitter, ni del pulso emitido ni de las notas.
