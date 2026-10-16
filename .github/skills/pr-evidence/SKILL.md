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
| 📈 Métricas | `& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id>` (pega la salida tal cual) |
| 🧪 Cómo probarlo | Comando del AppHost + endpoint o pantalla concreta del change |

## Comandos útiles

```powershell
openspec show <id> --json --deltas-only                     # requisitos/escenarios del change
git --no-pager diff --stat origin/main...HEAD               # tamaño (líneas de producción = src/**)
dotnet test --logger "console;verbosity=normal"             # resultado por test
& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id>                      # tabla 📈
```

## Crear la PR (como el bot)

`pr-author` **no tiene herramienta de edición de ficheros** (a propósito): genera el cuerpo en un fichero temporal **desde la terminal**, con un here-string de **comillas simples** (L-006) e insertando los datos con `.Replace()`.

**Seguridad (CWE-94):** el cuerpo cita material no revisado (diff, informes de revisores). Por eso:
1. Genera el fichero **antes** de cargar la identidad del bot y en una invocación de terminal **sin** `agent-auth.ps1`.
2. Ninguna línea del here-string puede empezar por `'@`; si aparece en un fragmento citado, añádele un espacio delante.
3. Inserta los datos generados por scripts (métricas, tablas de revisión) con `.Replace()` desde ficheros o variables, no pegándolos en el fuente.

```powershell
# Paso 1 · sin identidad del bot: solo genera el fichero
$metrics = (& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id> | Out-String).Trim()
$body = Join-Path ([IO.Path]::GetTempPath()) "pr-<id>.md"
@'
## 🎯 Qué y por qué
…
## 📈 Métricas del ciclo

__METRICS__
'@.Replace('__METRICS__', $metrics) | Set-Content $body -Encoding utf8
```

```powershell
# Paso 2 · con identidad del bot: solo publica
. "$env:SDD_TOOLS/scripts/agent-auth.ps1"
gh pr create --base main --head sdd/<id> --title "<tipo>(<cap>): <resumen> (<id>)" `
  --body-file $body --label implementation --milestone "<milestone del Issue>"
Remove-Item $body
gh pr view --json body --jq .body     # comprueba el Markdown publicado
```

No intentes usar herramientas de creación o edición de ficheros (`create`, `edit`): no están disponibles para este agente.

## Reglas de estilo para el aprobador

- Primero lo que requiere decisión humana (bloqueos, riesgos, dudas); después las evidencias.
- Tablas, no párrafos. Enlaces a ficheros y líneas concretas.
- Nunca afirmes "todo correcto" sin el dato que lo respalda.
