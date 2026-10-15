---
name: sdd-metrics
description: Instrument SDD phases and produce per-change metrics (time per phase, tokens, cost, LLM calls, tools, subagents, review iterations) for the PR and the history trend. Use when running the SDD cycle or preparing a PR or retrospective.
license: MIT
---

# Métricas del ciclo SDD

Requiere el stack local de observabilidad (`docker compose -f observability/compose.yaml up -d`). Detalle en [observability/README.md](../../../observability/README.md).

## 1. Marcar fases

```powershell
& "$env:SDD_TOOLS/scripts/sdd-phase.ps1" -Change <id> -Phase apply -Action start
# … trabajo de la fase …
& "$env:SDD_TOOLS/scripts/sdd-phase.ps1" -Change <id> -Phase apply -Action end -Status ok      # o -Status error
& "$env:SDD_TOOLS/scripts/sdd-phase.ps1" -Change <id> -Phase review -Action start -Iteration 2   # fases repetidas: -Iteration
```

Fases: `explore`, `propose`, `apply`, `verify`, `review`, `archive`, `retrospective`, `pr`, `consolidation`.

## 2. Correlacionar la telemetría de los agentes

- **VS Code**: automático por la rama `sdd/<id>` (atributo `github.copilot.git.branch`).
- **Copilot CLI**: antes de lanzar agentes,
  ```powershell
  $env:SDD_CHANGE_ID = "<id>"; $env:SDD_PHASE = "<fase>"
  $env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
  $env:OTEL_RESOURCE_ATTRIBUTES = "sdd.change_id=<id>,sdd.phase=<fase>"
  ```

## 3. Obtener métricas

```powershell
& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id>                                         # tabla Markdown (sección 📈 de la PR)
& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id> -Format json                            # para análisis
& "$env:SDD_TOOLS/scripts/sdd-metrics.ps1" -Change <id> -ReviewIterations 2 -Blockers 1 -AppendHistory   # registra la fila en history.csv
```

## 4. Leer la tendencia

`.sdd/metrics/history.csv` (una fila por change) y el dashboard Grafana **SDD › SDD · Proceso de agentes** (<http://localhost:3000/d/sdd-process>). Lo que debe bajar de C0 a C8: iteraciones de revisión, bloqueantes, cambios pedidos por el humano y tokens por change normalizados por tamaño.
