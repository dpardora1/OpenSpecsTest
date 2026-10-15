---
name: parallel-code-review
description: Run the four independent reviewers (spec, architecture, security, tests) in parallel on a change, consolidate their findings deterministically and decide whether another fix iteration is needed. Use in the review phase of the SDD cycle.
license: MIT
---

# Revisión paralela multi-agente

## Revisores

| Agente | Foco | Modelo (familia distinta) |
|---|---|---|
| `reviewer-spec` | Cumple todos los escenarios y solo lo especificado | GPT |
| `reviewer-architecture` | Vertical slices, límites, simplicidad, design.md | Gemini |
| `reviewer-security` | OWASP/ASVS, autorización, IDOR, datos, dependencias | Grok |
| `reviewer-tests` | Trazabilidad, calidad de aserciones, determinismo, concurrencia | Claude Sonnet |

## Lanzamiento

**Modo A — subagentes (VS Code / CLI interactivo):** en **una sola respuesta** emite las 4 invocaciones de subagente. Prompt para cada uno (autocontenido):

> Revisa el change `<id>` (iteración `<i>`) en la rama `sdd/<id>` contra `origin/main`. Obtén el diff con `git --no-pager diff origin/main...HEAD` y los artefactos en `openspec/changes/<id>/`. Devuelve EXCLUSIVAMENTE tu informe con el contrato de salida de tu agente.

**Modo B — script (determinista, también en CI):**

```powershell
./scripts/parallel-review.ps1 -Change <id> -Iteration <i>
```

Lanza 4 procesos de Copilot CLI en paralelo (cada uno con el modelo de su agente y telemetría `sdd.phase=review`), guarda los informes en `.sdd/reviews/<id>/iter-<i>/` y escribe `consolidated.md` + `consolidated.json`. Sale con código 1 si hay bloqueantes.

## Contrato de salida de cada revisor

```markdown
## Review: <foco>
Veredicto: APPROVE | REQUEST_CHANGES
| # | Severidad | Archivo:línea | Hallazgo | Sugerencia | Confianza |
|---|---|---|---|---|---|
```

## Consolidación (determinista)

1. Normaliza cada fila: severidad (`BLOCKER|HIGH|MEDIUM|LOW`), fichero, línea, confianza.
2. **Deduplica**: mismo fichero y líneas a ≤ 5 de distancia con la misma idea → un único hallazgo con la lista de revisores. Coincidencia de ≥ 2 revisores = +2 de confianza (máx. 10).
3. **Bloqueante** = severidad en `blockingSeverities` (`BLOCKER`, `HIGH`) **y** confianza ≥ `blockingMinConfidence` (7), según `.sdd/sdd.config.json`.
4. Decisión:
   - Sin bloqueantes → continuar a `archive`.
   - Con bloqueantes e iteración < 3 → `implementer` en modo `fix` con la lista → quality gate → nueva iteración.
   - Con bloqueantes en la iteración 3 → PR en **draft** con label `blocked-by-review` y la decisión pendiente explicada al humano.
5. `MEDIUM`/`LOW` y bloqueantes con baja confianza → "Observaciones no bloqueantes" en la PR.

## Tabla resumen para la PR

| Revisor | Modelo | Veredicto | Bloqueantes resueltos | Observaciones abiertas |
|---|---|---|---|---|
| Spec & Correctness | GPT-6.1 Sol | APPROVE | 1 (iter. 1) | 0 |

Si un revisor no pudo ejecutarse (modelo no disponible, error), dilo explícitamente: una revisión ausente **no** es un APPROVE.
