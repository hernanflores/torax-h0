# Project Workflow — Torax H-0

## Guiding Principles

1.  **The Plan is the Source of Truth:** All work must be tracked in `plan.md`.
2.  **The Tech Stack is Deliberate:** Changes to the tech stack must be documented in `tech-stack.md` *before* implementation.
3.  **Test-Driven Development:** Write unit tests before implementing functionality.
4.  **Differentiated Coverage:** Engine ≥90%, MIDI ≥80%. `App` no se mide: si algo ahí merece un test, está en el sitio equivocado. See *Coverage Requirements*.
5.  **Timing is a Feature:** Any change touching the scheduler path must be validated with the jitter harness, not by ear alone.
6.  **Integration is by Pull Request:** No direct pushes to `main`. See *Branching and Pull Requests*.
7.  **Non-Interactive & CI-Aware:** Prefer non-interactive commands. Use `CI=true` and `xcodebuild` flags that avoid watch/interactive modes.

## Coverage Requirements

| Módulo | Umbral | Razón |
|---|---|---|
| `Engine` | **≥90%** | Puro y determinista: sin excusa para no cubrirlo. Es donde vive la corrección musical. |
| `MIDI` | **≥80%** | La lógica de scheduling es testeable; la entrega real de CoreMIDI se valida con el arnés de jitter. |
| `App` (SwiftUI) | **no se mide** | Ver la nota de abajo. Estado y presentación. No se escriben UI tests de bajo valor solo para subir el número. |

> **Nota del 2026-08-27 — por qué `App` no lleva umbral.**
>
> El umbral era ≥80%, pero **no se puede medir**: `ToraxH0.xcodeproj` tiene un
> solo target (`ToraxH0`, aplicación) y ninguno de test, y no hay runtimes de
> simulador instalados, así que un target de test iOS tampoco podría ejecutarse.
> Se descubrió al implementar la pantalla del track
> `mvp-shape-transport_20260827`.
>
> La respuesta no es bajar el listón sino **mover la lógica a donde sí se
> testea**: el texto de estado de Shape vive en `Engine`, y la selección de
> destino, la desconexión y el transporte en `MIDI`, todos cubiertos. Lo que
> queda en `App` es cableado y una vista SwiftUI sin lógica.
>
> La regla que sustituye al número: **si algo en `App` merece un test, es que
> está en el sitio equivocado.** Si alguna vez hace falta medirlo de verdad,
> exige añadir un target de test y `xcodebuild -downloadPlatform iOS`.

## Task Workflow

All tasks follow a strict lifecycle:

1.  **Select Task:** Choose the next available task from `plan.md` in sequential order.

2.  **Mark In Progress:** Edit `plan.md` and change the task from `[ ]` to `[~]`.

3.  **Write Failing Tests (Red Phase):**
    - Create a new test file for the feature or bug fix.
    - Write unit tests that define the expected behavior and acceptance criteria.
    - Where the Pre Spec states concrete behavior (euclidean 16/4, 16/5, 12/7; Rotate; PRNG reproducibility), those are literal test cases.
    - **CRITICAL:** Run the tests and confirm they fail. Do not proceed without failing tests.

4.  **Implement to Pass Tests (Green Phase):** Write the minimum code necessary. Confirm all tests pass.

5.  **Refactor:** With passing tests, improve clarity and remove duplication. Rerun tests.

6.  **Verify Coverage:** Run coverage and check it against the module's threshold in *Coverage Requirements*.

7.  **Verify Timing (when applicable):** Si el cambio altera **cuándo** cae un evento —la rejilla temporal, el scheduler o la matemática de tiempo—, corre el arnés de jitter y registra el resultado. Una regresión bloquea la tarea. Ver la nota de abajo para lo que ya no exige medición.

    > **Nota del 2026-08-28 — se mide cuando cambia el *cuándo*, no el *cuánto*.**
    >
    > La regla anterior exigía medir en cualquier cambio del camino de envío, y
    > tres mediciones seguidas dijeron lo mismo:
    >
    > | Medición | máx | σ | margen sobre σ |
    > |---|---|---|---|
    > | Spike, sin carga (2026-08-26) | 0,149 ms | 0,009 ms | 55× |
    > | Rebanada 1, motor + UI (2026-08-27) | 0,127 ms | 0,015 ms | 33× |
    > | Rebanada 3, anillo + playhead (2026-08-28) | 0,134 ms | 0,020 ms | 25× |
    > | Umbral | 2 ms | 0,5 ms | |
    >
    > La arquitectura explica por qué: con look-ahead, el jitter **no depende de
    > cuándo despierta el hilo** mientras su trabajo quepa en la ventana de
    > 20 ms. Añadir aritmética de enteros al hilo del scheduler son nanosegundos
    > contra veinte millones, y medirlo cada vez es ceremonia.
    >
    > **Lo que sí exige medición**, porque no es carga sino rejilla:
    >
    > - Cambios en `MusicalTimeline`, `LookAheadScheduler` o `SchedulerThread`.
    > - Swing (Timing), Delay y cualquier parámetro que desplace eventos respecto
    >   a la rejilla.
    > - Carga visual nueva que redibuje al ritmo del reloj.
    > - Antes de cerrar v1, una medición final.
    >
    > **Lo que no:** añadir trabajo acotado al camino de emisión sin mover ningún
    > instante — elegir una altura del pool, aplicar una velocity, decidir una
    > probabilidad.
    >
    > **El coste de la regla es la atribución.** La σ sube de forma monótona
    > —9 → 15 → 20 µs— y sin medir cada rebanada, cuando algo suene mal no se
    > sabrá cuál lo introdujo. Se acepta a cambio de no medir tres veces lo
    > mismo; si aparece una regresión, se bisecta con el arnés, que sigue ahí.

8.  **Document Deviations:** If implementation differs from `tech-stack.md` or the Pre Spec:
    - **STOP** implementation.
    - Update the relevant document with a dated note explaining the change.
    - Resume implementation.

9.  **Commit Code Changes:** One commit per task, **on a branch — never on `main`** (see *Branching and Pull Requests*). Stage all changes, propose a clear message (see *Commit Guidelines*), commit.

10. **Attach Task Summary with Git Notes:**
    - Get the commit hash: `git log -1 --format="%H"`.
    - Draft a summary: task name, summary of changes, files created/modified, and the core *why*.
    - Attach it: `git notes add -m "<note content>" <commit_hash>`.
    - Note: git notes are not pushed by default. To share them: `git push origin refs/notes/commits`.

11. **Record Task Commit SHA:** In `plan.md`, change `[~]` to `[x]` and append the first 7 characters of the commit hash.

12. **Commit Plan Update:** Stage `plan.md` and commit as `conductor(plan): Mark task '<name>' as complete`.

### Task Correction & Plan Amendment Workflows

1.  **In-Flight Refinements:** Minor gaps found while a task is `[~]` are fixed in the active stream, with passing tests, before committing.
2.  **Code Review Corrections (`conductor-review`):** Issues found in review are appended to `plan.md` as a `Review Fixes` phase so corrections are tracked.
3.  **Logical State Reversions (`conductor-revert`):** A fundamentally flawed task is reverted — rolls back the commits and resets the task to `[ ]` for a clean restart.

### Phase Completion Verification and Checkpointing Protocol

**Trigger:** executed immediately after a task completes that also concludes a phase in `plan.md`.

1.  **Announce Protocol Start.**

2.  **Ensure Test Coverage for Phase Changes:**
    - Find the previous phase's checkpoint SHA in `plan.md` (if none, scope is all changes since the first commit).
    - `git diff --name-only <previous_checkpoint_sha> HEAD`.
    - For each code file (exclude `.json`, `.md`, `.plist`), verify a corresponding test file exists. If missing, analyze existing test files for naming and style conventions, then write tests validating this phase's tasks.

3.  **Execute Automated Tests with Proactive Debugging:**
    - Announce the exact command before running it.
    - If tests fail, inform the user and debug. Propose a fix a **maximum of two times**; if they still fail, **stop**, report, and ask for guidance.

4.  **Propose a Manual Verification Plan:**
    - Analyze `product.md`, `product-guidelines.md`, and `plan.md` to determine the user-facing goals of the phase.
    - Give step-by-step instructions with specific expected outcomes.

    Example for this project:

    ```
    The automated tests have passed. For manual verification:

    **Manual Verification Steps:**
    1. **Connect** the BeatStep Pro to the iPad and a MIDI destination (hardware synth).
    2. **Build and run** on device: select the iPad target in Xcode and Run.
    3. **Press Play** and confirm: the ring shows the playhead advancing, and the
       destination receives notes on the euclidean positions shown.
    4. **Turn the Pulses knob** and confirm: the value appears large and fades, the
       ring redistributes pulses, and the change is audible on the next step —
       with no value jump.
    ```

5.  **Await Explicit User Feedback:** Ask "**Does this meet your expectations? Please confirm with yes or provide feedback on what needs to be changed.**" **PAUSE** until an explicit confirmation.

6.  **Identify Target Commit:** the last functional commit of the phase. Do NOT create an empty commit.

7.  **Attach Verification Report with Git Notes:** test command, manual steps, and the user's confirmation, attached to that commit.

8.  **Record Phase Checkpoint SHA:** append `[checkpoint: <sha>]` to the phase heading in `plan.md`.

9.  **Commit Plan Update:** `conductor(plan): Mark phase '<PHASE NAME>' as complete`.

10. **Announce Completion.**

### Quality Gates

Before marking any task complete:

-   [ ] All tests pass
-   [ ] Coverage meets the module's threshold (Engine ≥90%, MIDI ≥80%; `App` no se mide)
-   [ ] Code follows `code_styleguides/general.md` and `code_styleguides/swift.md`
-   [ ] No allocations, locks, or `await` introduced on the scheduler path
-   [ ] Jitter harness shows no regression (if the change touches timing)
-   [ ] `Engine` still imports nothing beyond the stdlib
-   [ ] Domain vocabulary matches the Pre Spec — no new synonyms
-   [ ] Public types and functions are documented
-   [ ] No new third-party dependencies without explicit justification
-   [ ] Documentation updated if needed

## Development Commands

### Setup

```bash
# Xcode 26.3 con la plataforma iOS instalada.
# Si xcodebuild falla al cargar plugins:  sudo xcodebuild -runFirstLaunch
# Si falta la plataforma iOS:             xcodebuild -downloadPlatform iOS
xcode-select -p   # debe apuntar a /Applications/Xcode.app/Contents/Developer
```

### Daily Development

```bash
# Tests de paquete — corren en host (macOS), sin simulador ni dispositivo
swift test --package-path Packages/Engine
swift test --package-path Packages/MIDI

# Compilar la app para iPadOS
xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'

# Formateo
swift format --in-place --recursive App Packages
```

### Before Committing

```bash
swift test --package-path Packages/Engine --enable-code-coverage
swift test --package-path Packages/MIDI --enable-code-coverage
xcodebuild build -scheme ToraxH0 -destination 'generic/platform=iOS'
```

### Ejecutar los tests desde Xcode

**No funciona desde el proyecto `ToraxH0.xcodeproj`.** El proyecto es iOS-only
(`SDKROOT = iphoneos`, `TARGETED_DEVICE_FAMILY = 2`), asi que Xcode acota los
tests de los paquetes a iOS — y no hay runtime de simulador instalado para
ejecutarlos. El esquema `ToraxH0` no tiene accion de test, y los esquemas
autogenerados `Engine` y `MIDI` del proyecto tampoco.

**Abre el paquete directamente:**

```bash
open Packages/MIDI/Package.swift     # o Packages/Engine/Package.swift
```

Xcode lo abre como proyecto propio. Elige **My Mac** como destino y pulsa Cmd+U.

Equivalente por linea de comandos:

```bash
cd Packages/MIDI && xcodebuild test -scheme MIDI -destination 'platform=macOS'
```

### Notas del entorno

- **Hay runtimes de simulador instalados** (iOS 26.3, desde el 2026-08-28; esta
  nota decía lo contrario y era falsa). Sirven para **verificar la interfaz sin
  hardware**, que es cómo se encontró que las posiciones vacías del anillo
  desaparecían contra el panel:

  ```bash
  SIM=$(xcrun simctl list devices available | grep -m1 'iPad Pro 11-inch' | grep -oE '[0-9A-F-]{36}')
  xcrun simctl boot "$SIM"
  xcodebuild build -scheme ToraxH0 -destination "id=$SIM" -derivedDataPath /tmp/dd
  xcrun simctl install "$SIM" /tmp/dd/Build/Products/Debug-iphonesimulator/ToraxH0.app
  xcrun simctl launch "$SIM" com.toraxh0.ToraxH0
  xcrun simctl io "$SIM" screenshot captura.png
  ```

  **Lo que el simulador no puede verificar:** no tiene destinos ni fuentes MIDI,
  así que `canPlay` es falso y no se ve el transporte, ni el playhead corriendo,
  ni nada que dependa de un knob. Y la medición de jitter sigue exigiendo
  dispositivo real: el timing del simulador no es representativo.
- **`DEVELOPMENT_TEAM` sí está fijado** (`QRPT98J2U2`), en Debug y en Release.
  Instalar en un iPad real no exige configurar nada más. *(Corregido el
  2026-08-27: esta nota decía lo contrario y era falsa.)*
- El SDK instalado (iOS 26.2) es muy posterior al deployment target (17.0):
  **compilar sin avisos no garantiza compatibilidad con iPadOS 17**, porque las
  APIs más recientes compilan igualmente. Verificar en dispositivo.

## Testing Requirements

### Unit Testing (Engine)

- Every module has corresponding tests.
- Engine tests run without simulator or hardware.
- Test success and failure cases, and boundary values from the Pre Spec (Steps 1/16/64, Pulses 1..Steps, Probability 0/100).
- Seeded PRNG reproducibility is tested explicitly: same seed, same sequence.

### Timing Verification

- The jitter harness measures real delivery timestamps against a MIDI destination and reports deviation.
- Timing is verified with a **number**, not an impression. Record the measurement in the task's git note.
- Run it on device, never only on simulator — simulator timing is not representative.

### Device Testing

- Test on a real iPad with the BeatStep Pro connected. Simulator cannot validate the primary success criterion.
- **Los encoders del BeatStep Pro tienen que estar en `Relative #2`.** Es el único
  modo que `RelativeEncoding` decodifica hoy: complemento a dos (`0x01` = +1,
  `0x7F` = −1). Se configura en MIDI Control Center.

  > **Nota del 2026-08-28.** Descubierto verificando `mvp-control-input_20260827`
  > en iPad. Con los encoders en otro modo, un solo clic se decodifica como un
  > delta de ±63 y **todos los parámetros saltan a su extremo**: Steps, Pulses y
  > Division quedan clavados en 1 o 16. Rotate parece funcionar porque es el
  > único que envuelve módulo Steps en vez de acotar — y eso lo hace el peor
  > testigo de los cuatro, no el mejor. Síntoma de configuración, no de código:
  > el decodificador hace lo que declara. Los otros modos entran con el preset
  > del BeatStep Pro, que es un track posterior.
- Verify knob response: relative mode, no value jumps, change audible within the next step.
- Verify legibility at ~1 metre: playhead and the transient parameter value.
- Verify behavior with no controller connected: read-only and transport, per `product-guidelines.md`.

## Code Review Process

### Self-Review Checklist

1.  **Functionality** — behaves as specified; edge cases handled; MIDI disconnection handled as an expected state, not an error.
2.  **Code Quality** — follows style guides; clear names from the Pre Spec vocabulary; comments explain *why*.
3.  **Testing** — engine tests deterministic; coverage adequate for the module.
4.  **Realtime Safety** — no allocations, locks, `await`, logging, or UI calls on the scheduler path; realtime functions carry the `/// Realtime:` marker.
5.  **Model Fidelity** — no fixed note-per-step representation; pool semantics preserved; random is seeded and repeatable.
6.  **iPad Experience** — touch targets adequate; readable without zoom; no modals blocking while transport runs.

## Branching and Pull Requests

**Nada entra en `main` sin pasar por un Pull Request.** Desde el 2026-08-26.

La razón es la CI. El workflow de GitHub Actions falló en los tres primeros
pushes a `main` —ejecutaba `swift build` desde la raíz, donde no hay
`Package.swift`— y acabó desactivado manualmente, así que el track
`timing-spike_20260826` se desarrolló entero sin comprobación automática.
Con el workflow arreglado, el PR es lo que hace que los checks corran *antes*
de que el código entre en `main`. Pushear directo desperdicia exactamente lo
que se acaba de reparar.

### Procedimiento

```bash
git checkout -b <tipo>/<descripcion-corta>    # fix/…, feat/…, chore/…, docs/…
# … trabajo, uno o más commits siguiendo el Task Workflow …
git push -u origin <rama>
gh pr create --base main --title "<titulo>" --body "<cuerpo>"
```

Aplica también a los commits que genera Conductor —`conductor(plan): …`,
fixes de revisión, archivado de tracks—: van en la misma rama y el mismo PR,
no sueltos sobre `main`.

### El check puede fallar sin culpa del cambio

`MIDITests` arrastra un flake conocido: `clientCreationFailed(-50)` al crear
clientes CoreMIDI, medido ~1 de cada 12 pasadas sobre `main` limpio. Antes de
atribuir un fallo `-50` al cambio bajo revisión, correr la suite 3–4 veces y
comparar contra `main` con el mismo número de pasadas — una sola pasada no
distingue nada.

> **Ampliación del 2026-08-27.** El fallo no es solo un flake de frecuencia: la
> creación de endpoints de CoreMIDI se rompe cuando la suite ha arrancado
> suficientes hilos de scheduler a prioridad máxima. Con el transporte del track
> `mvp-shape-transport_20260827` la suite pasó de 2 a 7 hilos, y en el runner de
> CI el fallo dejó de ser intermitente: **determinista**, con
> `clientCreationFailed(-2)` en las cuatro pruebas de `VirtualLoopbackTests`.
> Comprobado que no es el entorno: `main` relanzado en el mismo runner pasa.
>
> Mitigación en `.github/workflows/swift.yml`: los tests que tocan CoreMIDI
> corren **primero y en su propio proceso**, antes de que exista ningún hilo. No
> se pierde ni un test — 14 + 111 = los mismos 125. Es una mitigación, no un
> arreglo; la causa pertenece a `midi-test-flake_20260826`, que bloquea a
> `scheduler-lifecycle_20260826`.
>
> **Efecto secundario: la cobertura de `MIDI` hay que medirla en un proceso.**
> Cada mitad de la partición genera su propio `.profdata`, así que ejecutar los
> dos pasos y leer cualquiera de los dos informes da una cifra falsamente baja
> —los ficheros de la otra mitad cuentan como no cubiertos—. Medido el
> 2026-08-28: la partición reporta 77,7% de líneas; la suite entera en un solo
> proceso, 95,8%. Para verificar el umbral de `MIDI` usar siempre:
>
> ```bash
> swift test --package-path Packages/MIDI --enable-code-coverage
> ```
>
> La CI no mide cobertura, así que esto no afecta a ningún gate automático.

> **Ampliación del 2026-08-29 — al leer el informe, excluir `Engine/Sources`.**
>
> El binario de test de `MIDI` compila dentro las fuentes de `Engine`, así que
> el informe las lista **a 0%**: las cubre la suite del otro paquete, no ésta.
> Contarlas diluye la cifra de `MIDI` sin que nada esté peor cubierto —medido el
> 2026-08-29: 86,68% con ellas dentro, **91,54%** sin ellas—.
>
> Para verificar el umbral de `MIDI`, filtrar el informe:
>
> ```bash
> B=Packages/MIDI/.build/arm64-apple-macosx/debug
> xcrun llvm-cov report \
>   "$B/MIDIPackageTests.xctest/Contents/MacOS/MIDIPackageTests" \
>   -instr-profile "$B/codecov/default.profdata" \
>   -ignore-filename-regex='\.build|Tests|Engine/Sources'
> ```
>
> Descubierto cerrando el track `mvp-groove-static_20260829`. La cifra que se
> compara contra el umbral es la de **líneas**, no la de regiones.

> **Ampliación del 2026-08-30 — en un proceso la suite ya no pasa, y en local
> hay que usar la partición.**
>
> La rebanada 6 necesita tests que arranquen el bucle del scheduler: el origen
> de la rejilla lo fija `SchedulerThread` y no se observa dándole el horizonte a
> mano. Con cuatro arranques más, el flake **deja de ser intermitente**. Medido
> el 2026-08-30, suite completa en un solo proceso:
>
> | | pasadas con `-50` |
> |---|---|
> | `feat/mvp-groove-temporal` | **4 de 4** |
> | `main` | 0 de 2 |
> | cualquiera, con la partición de CI | **0 fallos** (21 + 230 tests) |
>
> Es el mecanismo que ya describe la ampliación del 2026-08-27, llevado hasta el
> final: la creación de endpoints se rompe cuando la suite ha arrancado
> suficientes hilos a prioridad máxima. La firma sigue siendo la misma —las 4
> pruebas de `VirtualLoopbackTests`, ningún otro test—.
>
> **En local, correr `MIDI` como lo corre la CI:**
>
> ```bash
> swift test --package-path Packages/MIDI \
>   --filter 'VirtualLoopbackTests|JitterHarnessTests|CoreMIDIOutputTests|CoreMIDIInputTests'
> swift test --package-path Packages/MIDI \
>   --skip VirtualLoopbackTests --skip JitterHarnessTests \
>   --skip CoreMIDIOutputTests --skip CoreMIDIInputTests
> ```
>
> **Y la cobertura de `MIDI` exige un paso más.** Sigue midiéndose en un solo
> proceso —la partición da una cifra falsamente baja, ver arriba— pero esa
> pasada ahora falla, y **SwiftPM no fusiona el `.profdata` cuando la pasada
> falla**. Hay que fusionarlo a mano:
>
> ```bash
> B=Packages/MIDI/.build/arm64-apple-macosx/debug
> swift test --package-path Packages/MIDI --enable-code-coverage    # fallará: 4 de VirtualLoopbackTests
> xcrun llvm-profdata merge -sparse "$B"/codecov/*.profraw -o "$B/codecov/manual.profdata"
> xcrun llvm-cov report \
>   "$B/MIDIPackageTests.xctest/Contents/MacOS/MIDIPackageTests" \
>   -instr-profile "$B/codecov/manual.profdata" \
>   -ignore-filename-regex='\.build|Tests|Engine/Sources'
> ```
>
> **Se acepta a propósito**, por la decisión del 2026-08-29 de aplazar
> `midi-test-flake_20260826` a después de la v2. El coste está acotado —la CI no
> se ve afectada y la firma es reconocible— y la alternativa era dejar sin
> cubrir la pieza más delicada de la rebanada: que ningún evento se pida para un
> instante que ya pasó.

## Commit Guidelines

### Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

`feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

### Scopes

`engine`, `midi`, `ui`, `plan`, `docs`

### Examples

```bash
git commit -m "feat(engine): Add euclidean pulse distribution"
git commit -m "fix(midi): Correct swing offset sign on Timing"
git commit -m "test(engine): Cover 12/7 euclidean case from Pre Spec"
git commit -m "refactor(midi): Remove allocation from scheduler path"
```

## Definition of Done

A task is complete when:

1. Code implemented to specification
2. Unit tests written and passing
3. Coverage meets the module's threshold (`App` exento: ver *Coverage Requirements*)
4. Jitter verified if timing was touched
5. Documentation complete (if applicable)
6. Code follows the style guides
7. Verified on device when the change is user-facing
8. Task status and SHA recorded in `plan.md`
9. Changes committed with a proper message
10. Git note with task summary attached to the commit

## Emergency Procedures

### Timing Regression

1. Identify the last commit with a clean jitter measurement (`git log --notes`).
2. Bisect against the jitter harness.
3. Write a failing timing test if one can be expressed.
4. Fix, re-measure on device, document in `plan.md`.

### Corrupted Project State

1. Stop writes (disable Autosave).
2. Restore from the most recent Backup Project export.
3. Verify integrity of the Bank/Pattern tree.
4. Document the incident and add a schema-version guard if the cause was a migration.

## Continuous Improvement

- Review the workflow when it causes friction, not on a calendar.
- Document lessons learned in the relevant conductor document.
- Keep things simple and maintainable.
