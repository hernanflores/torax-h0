# Verificación en dispositivo — v2 rebanada 4: Persistencia

**Track:** `persistence_20260907`
**Fecha:** _(pendiente)_
**Dispositivo:** iPad Air 4ª generación
**Controlador:** BeatStep Pro, encoders en `Relative #2`

## Por qué esta verificación es la que decide

La rebanada existe para que **cerrar la app no pierda el trabajo**, y eso no se
puede comprobar desde un test: los tests prueban que un Bank sobrevive a ida y
vuelta por memoria y por un directorio temporal, no que el ciclo de vida real de
iPadOS —bloquear el iPad, matar la app desde el conmutador— llegue a escribir.

Y hay dos cosas más que solo se ven aquí:

- **La app arranca leyendo el disco**, antes de construir la entrada de control y
  el transporte. Si esa lectura fuera lenta o fallara, se vería como un arranque
  raro y no como un error.
- **La pantalla `banks` no se ha visto nunca.** El simulador no se puede tocar
  desde esta sesión —`simctl` no tiene gesto y no hay `idb`— así que los cuatro
  estados, la cuenta atrás y los controles de guardado **están sin verificar
  visualmente**.

## Lo que hay que comprobar

### 1. El ciclo completo — es el criterio principal de la rebanada

1. Abrir la app. Comprobar que abre **como abría antes**: anillo 16/5, `minor` /
   root `C`, pool `c3`, `120 bpm`.
2. Construir material reconocible: **dos Tracks con pool distinto**, uno con otra
   Scale y otro Root, y un tempo que no sea 120.
3. Ir a `banks`, copiar el Pattern 01 al 02, y variarlo.
4. **Matar la app desde el conmutador** —no solo mandarla al fondo—.
5. Reabrir. **Tiene que estar todo**: el mismo Bank, el mismo Pattern, el mismo
   Track seleccionado, el material hasta el último Cycle, y el tempo.

### 2. La pantalla `banks`, que es lo que no se ha visto

- Los dieciséis huecos de banco y los dieciséis de pattern.
- El pattern con material dice **`ready`**; los vacíos, **`empty`**.
- Con Play, el que suena dice **`playing`**.
- El pie del card de bancos dice el tempo y cuántos patterns tienen material.
- `track assignments` dice el **Pattern real**, no `pattern 01` doce veces.
- **Legible a un metro**, que es condición de uso.

### 3. El cambio cuantizado — el núcleo de la fase de riesgo

1. Con el transporte **corriendo**, pulsar el Pattern 02.
2. El hueco tiene que decir **`queued`** y aparecer la cuenta atrás (`in 4`,
   `in 3`, …) contando negras.
3. **El cambio cae en el compás**, no antes. Se juzga de oído: la frase entra
   donde el pie la espera.
4. **No se oye ningún corte** al cruzar, ni queda ninguna nota colgada.
5. Alternar entre 01 y 02 varios compases seguidos.
6. Pulsar un Pattern y darle a **Stop** antes del compás: el pendiente pasa a
   ser el vigente, y el Play siguiente arranca con él.

### 4. Save Bank y Reload

1. En un Bank que **nunca se ha guardado**, `reload` tiene que estar apagado y
   decir por qué.
2. Pulsar `save bank`. Editar algo. Pulsar `reload`: vuelve **exactamente** al
   estado guardado.
3. Con el transporte corriendo, `reload` entra **en el compás**, como un cambio
   de Pattern.

### 5. Cambio de Bank y tempo

1. Con reloj `Internal`: cambiar de Bank adopta **su tempo**.
2. Con reloj `External` y el BeatStep mandando: cambiar de Bank **no toca el
   tempo**, y el material entra igual.
3. Volver a `Internal`: el tempo del Bank vuelve a mandar.

### 6. El Autosave, que tiene que ser invisible

1. Con el transporte corriendo varios minutos, girar knobs.
2. **No se puede oír nada al escribir.** Ningún hipo, ningún salto.
3. Mandar la app al fondo y volver: el trabajo está.

### 7. El coste de guardar, NFR3

Medir en dispositivo que serializar y escribir un Bank lleno queda **por debajo
de 100 ms**. La línea base en host es de 15,5 ms.

## Lo que NO se verifica aquí

**No hay medición de jitter**, y por dos razones independientes: está suspendida
desde el 2026-09-02, y esta rebanada **no mueve ningún instante** —cambia qué
material se emite en un límite que ya existía—. Ni bajo la regla anterior a la
suspensión habría exigido arnés.

## Resultado

_(pendiente)_
