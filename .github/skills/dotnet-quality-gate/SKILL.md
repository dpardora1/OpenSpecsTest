---
name: dotnet-quality-gate
description: Run and interpret the .NET quality gate (build without warnings, format, tests, coverage, architecture, OpenSpec validation, traceability) and fix failures without suppressing checks. Use before declaring an implementation done or after fixing review findings.
license: MIT
---

# Quality gate .NET

El gate es **el mismo en local y en CI**: si pasa en local, pasará en la PR.

## Ejecutar

```powershell
& "$env:SDD_TOOLS/scripts/quality-gate.ps1"                        # gate completo
& "$env:SDD_TOOLS/scripts/quality-gate.ps1" -Change <id>           # + trazabilidad de los escenarios del change
& "$env:SDD_TOOLS/scripts/quality-gate.ps1" -Steps dotnet,coverage # solo algunos pasos mientras iteras
& "$env:SDD_TOOLS/scripts/parallel-review.ps1" -Change <id> -Iteration <i> -PrepareOnly   # crea la carpeta de evidencias
& "$env:SDD_TOOLS/scripts/quality-gate.ps1" -Change <id> *> .sdd/reviews/<id>/iter-<i>/quality-gate.txt   # evidencia para los revisores
```

Pasos (cada uno PASS / FAIL / SKIP) y lo que comprueban:

| Paso | Comprueba | Se omite si |
|---|---|---|
| `customizations` | Frontmatter de agentes, skills, prompts e instrucciones; YAML de workflows, `github-script` que compila y Actions fijadas por SHA | — |
| `powershell` | Sintaxis de `scripts/` y `tests/` | — |
| `pester` | Tests de los scripts del proceso (`tests/scripts`) | no hay `tests/scripts` |
| `openspec` | `openspec validate --all --strict` | — |
| `dotnet` | `restore` → `build -warnaserror` → `format --verify-no-changes` → `test` con cobertura (Cobertura) y TRX | no hay `*.slnx`/`*.sln` (antes de C0) |
| `coverage` | Cobertura de líneas de los `.cs` de `src/` cambiados contra `origin/main` ≥ 80 % (sin migraciones ni código generado) | no hay cambios en `src/` |
| `traceability` | Cada escenario ADDED/MODIFIED del change tiene ≥ 1 test **que se ejecutó y pasó** (traits leídos del TRX) | sin `-Change` |

Requisitos del proyecto .NET para que `dotnet` funcione (detalle en [docs/spikes/dotnet-testing.md](../../../docs/spikes/dotnet-testing.md)): `global.json` con `"test": { "runner": "Microsoft.Testing.Platform" }` y, en cada proyecto de tests, `xunit.v3.mtp-v2`, `Microsoft.Testing.Extensions.CodeCoverage` y `Microsoft.Testing.Extensions.TrxReport`.

## Interpretar fallos

| Paso | Fallo típico | Cómo corregirlo |
|---|---|---|
| build | Warning de analizador (CAxxxx, IDExxxx, Sxxxx) | Corrige la causa. **Nunca** `#pragma warning disable`, `NoWarn` ni `[SuppressMessage]` sin justificación aprobada en un ADR o lección |
| format | Diferencias de formato | `dotnet format` y commit `style: …` |
| test | Test rojo | Determina si el fallo es del test o del código **comparando con el escenario de la spec**; la spec manda |
| arquitectura | Dependencia prohibida (p. ej. Domain → EF Core) | Mueve el código a la capa correcta; no relajes la regla |
| openspec | Delta inválido | `openspec validate <id> --strict` y corrige el artefacto (solo el spec-architect toca specs) |
| trazabilidad | Escenario sin test | Añade el test con su `[Trait("Scenario", …)]` (skill `spec-traceability`) |
| cobertura | < 80 % en código nuevo | Añade tests de comportamiento, no tests vacíos para subir el número |

## Reglas

- Termina **siempre** con el gate completo en verde y pega el resumen en tu respuesta.
- Si un fallo no depende de tu cambio (infraestructura, Docker caído), repórtalo con la salida exacta; no lo ocultes.
