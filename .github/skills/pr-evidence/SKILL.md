---
name: pr-evidence
description: Gather the evidence and fill the pull request template (scenarios to tests, coverage, API contract, reviewer verdicts, lessons, metrics) so the human approver can decide in minutes. Use when opening or updating an SDD pull request.
license: MIT
---

# Evidencias para la PR

El aprobador debe poder decidir **solo con la PR**. Cada afirmación lleva su evidencia; lo que no esté disponible se marca `N/D (motivo)`.

## Secciones y de dónde sale cada dato

| Sección de la plantilla | Fuente |
|---|---|
| 🎯 Qué y por qué | `openspec/changes/<id>/proposal.md` (3 líneas) · `Closes #<issue>` (implementación) o `Refs #<issue>` (spec) |
| ✅ Escenarios cubiertos | Deltas del change + tests con `[Trait("Scenario", …)]` (skill `spec-traceability`); resultado de `dotnet test` |
| 📊 Evidencias | Cobertura de código nuevo (informe del quality gate), mutation score (CI), diff de OpenAPI (CI), capturas/trazas de Playwright (artefactos de CI) |
| 🤖 Revisiones multi-agente | `.sdd/reviews/<id>/iter-<n>/consolidated.md` (skill `parallel-code-review`) |
| ⚠️ Riesgos y decisiones | `design.md`, observaciones no bloqueantes, falsos positivos descartados con su razón |
| 🧠 Lecciones | IDs nuevos o actualizados en `.sdd/memory/lessons.md` (los devuelve `retrospective`) |
| 📈 Métricas | `./scripts/sdd-metrics.ps1 -Change <id>` (pega la salida tal cual) |
| 🧪 Cómo probarlo | Comando del AppHost + endpoint o pantalla concreta del change |

## Comandos útiles

```powershell
openspec show <id> --json --deltas-only                     # requisitos/escenarios del change
git --no-pager diff --stat origin/main...HEAD               # tamaño (líneas de producción = src/**)
dotnet test --logger "console;verbosity=normal"             # resultado por test
./scripts/sdd-metrics.ps1 -Change <id>                      # tabla 📈
```

## Crear la PR (como el bot)

```powershell
. ./scripts/agent-auth.ps1
$body = Join-Path $env:TEMP "pr-<id>.md"                      # genera aquí el cuerpo completo
gh pr create --base main --head sdd/<id> --title "<tipo>(<cap>): <resumen> (<id>)" `
  --body-file $body --label implementation --milestone "<milestone del Issue>"
```

## Reglas de estilo para el aprobador

- Primero lo que requiere decisión humana (bloqueos, riesgos, dudas); después las evidencias.
- Tablas, no párrafos. Enlaces a ficheros y líneas concretas.
- Nunca afirmes "todo correcto" sin el dato que lo respalda.
