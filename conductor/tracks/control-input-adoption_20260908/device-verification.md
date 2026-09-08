# Verificación en dispositivo — `ControlInput` no adopta el Pattern del Bank nuevo

**Track:** `control-input-adoption_20260908`
**Fecha:** 2026-09-08
**Dispositivo:** el iPad del proyecto (iPad Air 4ª generación, según la
verificación de `note-repeater_20260906`)
**Controlador:** BeatStep Pro, encoders en `Relative #2`, preset versión 4

> **El preset no cambia.** Este track no añade ni mueve ningún control: los
> cuarenta y ocho siguen significando lo mismo. Si el iPad ya tenía el preset 4
> cargado desde `note-repeater_20260906`, no hay que tocar MIDI Control Center.

## Por qué esta verificación es la que decide

**El fallo se encontró aquí y solo aquí se puede dar por cerrado.** Se descubrió
el 2026-09-07 verificando la Fase 4 de `note-repeater_20260906`, porque un
ratchet sobre un Bank que se creía vacío es inconfundible; el resto de las veces
pasaba por «no cambió nada». Ningún test lo habría visto, porque los tests
construyen el `ControlInput` con el Pattern que quieren probar y el fallo era
justamente que nadie lo reseedeaba después.

Y la mitad cara —la vía de vuelta— **solo existe con el transporte corriendo**:
el material entra en el límite de compás dentro del hilo del scheduler, y el
simulador no tiene destinos MIDI ni fuentes, así que no hay transporte que correr
ni knob que girar.

**Sin medición de jitter** (NFR4): la suspensión del 2026-09-02 manda, y además
este cambio no mueve ningún instante — cambia quién conoce el material, no cuándo
suena.

## Lo que se comprobó

### 1. El fallo reportado, primero — transporte parado

1. Sobre el Bank 1, material reconocible: Steps y Pulses movidos, notas metidas
   con los pads.
2. Cambiar a un Bank **vacío** y girar un knob.
3. **El Pattern del Bank 1 no vuelve.** Steps, Pulses, pool, Groove y marco
   tonal siguen siendo los del Bank nuevo. Antes del cambio volvía entero.

### 2. Los otros dos caminos parados

4. `selectPattern`: cambiar de hueco dentro de un Bank y girar un knob escribe en
   el hueco nuevo.
5. `reloadBank`: editar, pulsar Reload y girar un knob no resucita lo editado.

### 3. Lo que es del dedo sobrevive

6. Con el Track 5 seleccionado, cambiar de Bank y girar un knob **sigue editando
   el Track 5** (FR2).

### 4. Los modificadores

7. Temp (step 13) hundido, girar, **cambiar de Bank sin soltar**, soltar: **no
   escribe nada**. El Pattern queda como lo dejó la adopción (FR5).
8. Lo mismo con Ctrl All (step 14).

### 5. Con el transporte corriendo — la vía de vuelta

9. Play. Cambiar de Pattern: aparece la cuenta atrás y el hueco se pinta
   `queued`; el material **entra en el límite de compás**.
10. **En cuanto suena, la cuenta atrás desaparece y la rejilla marca el hueco
    nuevo.** Antes se quedaba clavada en el viejo — es el defecto hermano que
    este track absorbe.
11. **Girar un knob justo después escribe en el hueco que está sonando**, no en
    el anterior (FR10). Es la consecuencia que destruía trabajo.
12. Cambiar de Bank sonando: mismo comportamiento.
13. Dos Patterns seguidos antes del compás: entra el último, y la rejilla acaba
    marcando ese.
14. Armar y pulsar Stop antes del compás: lo armado pasa a vigente y la pantalla
    lo refleja.

## Resultado

**Sin discrepancias.** Confirmación del usuario el 2026-09-08: «Funcionó».

## Lo que esta verificación no cubre

- **Los mutes al cambiar de Bank** quedan como estén. No viajan en el `Pattern` y
  este track no cambia ese comportamiento — está declarado fuera de alcance en el
  `spec.md`, y se anota aquí para que no se confunda con algo que se comprobó.
- **Jitter**: no se mide (NFR4), y la última referencia válida sigue siendo la de
  la rebanada 2 de la v2 (2026-09-02, máx 0,158 ms).
- **El retraso de hasta un cuadro** entre lo que suena y lo que la pantalla
  refleja (FR9) no se puede observar a ojo, que es exactamente por qué se aceptó.
