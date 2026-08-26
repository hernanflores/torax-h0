# Project Workflow — Torax H-0

## Guiding Principles

1.  **The Plan is the Source of Truth:** All work must be tracked in `plan.md`.
2.  **The Tech Stack is Deliberate:** Changes to the tech stack must be documented in `tech-stack.md` *before* implementation.
3.  **Test-Driven Development:** Write unit tests before implementing functionality.
4.  **Differentiated Coverage:** Engine ≥90%, UI/App ≥80%. See *Coverage Requirements*.
5.  **Timing is a Feature:** Any change touching the scheduler path must be validated with the jitter harness, not by ear alone.
6.  **Non-Interactive & CI-Aware:** Prefer non-interactive commands. Use `CI=true` and `xcodebuild` flags that avoid watch/interactive modes.

## Coverage Requirements

| Módulo | Umbral | Razón |
|---|---|---|
| `Engine` | **≥90%** | Puro y determinista: sin excusa para no cubrirlo. Es donde vive la corrección musical. |
| `MIDI` | **≥80%** | La lógica de scheduling es testeable; la entrega real de CoreMIDI se valida con el arnés de jitter. |
| `App` (SwiftUI) | **≥80%** | Estado y presentación. No se escriben UI tests de bajo valor solo para subir el número. |

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

7.  **Verify Timing (when applicable):** If the change touches the scheduler, MIDI send path, or timing math, run the jitter harness and record the result. A regression in jitter blocks the task.

8.  **Document Deviations:** If implementation differs from `tech-stack.md` or the Pre Spec:
    - **STOP** implementation.
    - Update the relevant document with a dated note explaining the change.
    - Resume implementation.

9.  **Commit Code Changes:** One commit per task. Stage all changes, propose a clear message (see *Commit Guidelines*), commit.

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
-   [ ] Coverage meets the module's threshold (Engine ≥90%, MIDI/App ≥80%)
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

- **No hay runtimes de simulador instalados.** No es bloqueante: los tests de
  paquete corren en host y la medición de jitter debe correr en dispositivo real
  (`workflow.md` → Timing Verification). Si en algún momento se necesita
  simulador: `xcodebuild -downloadPlatform iOS` y añadir `-destination
  'platform=iOS Simulator,name=<dispositivo>'`.
- **`DEVELOPMENT_TEAM` no está fijado** en el proyecto. Instalar en un iPad real
  exige configurarlo (Signing & Capabilities en Xcode), o pasar
  `DEVELOPMENT_TEAM=<TEAMID>` a `xcodebuild`.
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
3. Coverage meets the module's threshold
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
