---
name: dotnet-quality-gate
description: Run and interpret the .NET quality gate (build without warnings, format, tests, coverage, architecture, OpenSpec validation, traceability) and fix failures without suppressing checks. Use before declaring an implementation done or after fixing review findings.
license: MIT
---

# Quality gate .NET

El gate es **el mismo en local y en CI**: si pasa en local, pasará en la PR.

## Ejecutar

```powershell
./scripts/quality-gate.ps1                  # gate completo (creado en la fase F5)
./scripts/quality-gate.ps1 -Change <id>     # incluye trazabilidad de los escenarios del change
```

Mientras `scripts/quality-gate.ps1` no exista (antes de F5), ejecuta el equivalente:

```powershell
dotnet restore
dotnet build --no-restore -warnaserror
dotnet format --verify-no-changes --no-restore
dotnet test --no-build
openspec validate --all --strict
```

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
