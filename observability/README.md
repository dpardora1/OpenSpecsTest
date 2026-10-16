# Observabilidad del proceso de agentes

Stack local para ver **tiempos, tokens, coste, agentes, subagentes y fases** del ciclo SDD (plan §9, decisiones D-06/D-07).

```mermaid
flowchart LR
    V[VS Code · Copilot Chat] -- OTLP http :4318 --> C[OTel Collector 0.162.0]
    CLI[Copilot CLI] -- OTLP http :4318 --> C
    P[scripts/sdd-phase.ps1] -- span sdd.phase --> C
    H[Hooks .github/hooks] -- JSONL --> E[(.sdd/telemetry/events.jsonl)]
    P -- JSONL --> E
    C -- redacción de secretos + etiquetas sdd --> G[Grafana LGTM 0.36.0<br/>Tempo · Prometheus · Loki]
    C --> F[(.sdd/telemetry/otel.jsonl)]
    F & E --> M[scripts/sdd-metrics.ps1]
    M --> PR[Sección 📈 de la PR]
    M --> HC[.sdd/metrics/history.csv]
```

## Arranque

```powershell
./scripts/bootstrap/enable-agent-telemetry.ps1 -TrustRepo   # una vez por máquina: ajustes de usuario de VS Code (+ hooks del CLI, opcional)
docker compose -f observability/compose.yaml up -d
```

Después, **reinicia VS Code por completo** (cierra todas las ventanas): las variables de entorno `COPILOT_OTEL_*` solo se leen al arrancar el proceso.

| Servicio | URL | Notas |
|---|---|---|
| Grafana | <http://localhost:3000> | Dashboard **SDD › SDD · Proceso de agentes**. Acceso anónimo de administrador: solo escucha en `127.0.0.1` |
| OTLP HTTP / gRPC | `http://localhost:4318` / `localhost:4317` | Endpoint para VS Code y Copilot CLI |

Para parar: `docker compose -f observability/compose.yaml down`. Para **borrar todos los datos** (p. ej. antes de la línea base de C0): añade `-v` y borra `.sdd/telemetry/`.

## Fuentes de telemetría

| Fuente | Configuración | Qué aporta |
|---|---|---|
| Sesiones de agentes en VS Code (harness de Copilot) | Variables de entorno de usuario `COPILOT_OTEL_ENABLED`, `COPILOT_OTEL_ENDPOINT` (siempre explícito: con ajustes de telemetría gestionados por la enterprise no se usa el endpoint por defecto) y `COPILOT_OTEL_CAPTURE_CONTENT`, que pone `enable-agent-telemetry.ps1` | Trazas de los agentes personalizados y prompts (`/sdd-*`), subagentes y tokens |
| Copilot Chat (VS Code) | **Ajustes de usuario** (`github.copilot.chat.otel.*`, ámbito *application*: VS Code los ignora en `.vscode/settings.json`). Se aplican con `./scripts/bootstrap/enable-agent-telemetry.ps1` | Trazas de agentes y subagentes, tokens, herramientas. Correlación por rama `sdd/<change>` |
| Copilot CLI | Variables de entorno (abajo) | Lo mismo + `sdd.change_id`/`sdd.phase` como atributos de recurso |
| `scripts/sdd-phase.ps1` | Lo invoca el `sdd-conductor` | Inicio/fin de cada fase. Al terminar, publica un span `sdd.phase <fase>`; todas las fases de un change comparten traza |
| Hooks (`.github/hooks/sdd-telemetry.json`) | Automático | `sessionStart/End`, `subagentStart/Stop`, `postToolUseFailure`, `errorOccurred` → `events.jsonl` (incluyen `traceparent`) |

Variables para ejecutar agentes con Copilot CLI:

```powershell
$env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
$env:OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = "true"
$env:OTEL_RESOURCE_ATTRIBUTES = "sdd.change_id=<change>,sdd.phase=<fase>"
$env:SDD_CHANGE_ID = "<change>"; $env:SDD_PHASE = "<fase>"   # para los hooks
```

## Métricas por change

```powershell
./scripts/sdd-metrics.ps1 -Change <change>                                   # tabla Markdown para la PR
./scripts/sdd-metrics.ps1 -Change <change> -ReviewIterations 2 -Blockers 1 -AppendHistory   # + fila en history.csv
./scripts/sdd-metrics.ps1 -Change <change> -Format json
```

Los tokens se suman desde los spans `chat` (los `invoke_agent` llevan totales de sesión y duplicarían). Cada llamada se atribuye a su `invoke_agent` más cercano, así que cada subagente (p. ej. los 4 revisores) tiene su fila.

## Lecciones de la puesta en marcha (F3)

- **Los hooks del repo solo se ejecutan en carpetas de confianza.** En Copilot CLI la lista está en `~/.copilot/config.json` → `trustedFolders` (no en `settings.json`). `enable-agent-telemetry.ps1 -TrustRepo` la configura de forma **explícita**: la confianza es por carpeta, así que cualquier rama que se haga checkout ahí ejecutará sus hooks. Las revisiones se aíslan en un worktree no confiable (lección L-001).
- **Los ajustes OTel de Copilot Chat son de usuario**, no de workspace, y solo cubren el proceso de la extensión. Las sesiones de agentes del harness de Copilot necesitan además las variables `COPILOT_OTEL_*` (lección L-002).
- **Procesos de vida corta:** cada ejecución del CLI exporta sus contadores una sola vez al terminar, así que `rate()`/`increase()` no devuelven nada. El dashboard usa `max_over_time(...[$__range])` por serie.
- **Grafana LGTM solo lee el aprovisionamiento de dashboards al arrancar:** tras editar `dashboards/*.json`, ejecuta `docker compose -f observability/compose.yaml restart lgtm`.
- **Redacción de secretos:** el collector enmascara tokens de GitHub (`gh*_`, `github_pat_`), cabeceras `Bearer/Basic` y claves privadas antes de exportar. Verificado con un token falso en el prompt: no aparece en ningún destino.
- **Etiquetas por change:** el collector copia `sdd.change_id` y `sdd.phase` del recurso a cada punto de métrica para poder agrupar en Prometheus.
