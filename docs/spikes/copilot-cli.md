# Spike F0-05 · Copilot CLI no interactivo + OpenTelemetry

- **Fecha:** 2026-10-15
- **Versión probada:** GitHub Copilot CLI `1.0.78-2`
- **Resultado:** ✅ Validado

## Objetivo

Confirmar que el Copilot CLI puede ejecutar **agentes personalizados del repo en modo no interactivo** (necesario para la revisión paralela en local y en CI) y que **emite OpenTelemetry** con los datos que necesita `scripts/sdd-metrics.ps1`.

## Prueba realizada

```powershell
# Repo temporal con .github/agents/spike-reviewer.agent.md (tools: read, search)
$env:COPILOT_OTEL_FILE_EXPORTER_PATH = "$PWD\otel.jsonl"
$env:OTEL_RESOURCE_ATTRIBUTES = "sdd.change_id=spike,sdd.phase=f0-05"
copilot -p "Lee README.md y di qué contiene en una frase." `
  --agent spike-reviewer --allow-all-tools --no-ask-user -s
```

- Respuesta correcta siguiendo las instrucciones del agente (`SPIKE-OK: …`).
- Duración: ~25 s · código de salida 0 · 15 líneas JSONL de telemetría.

## Telemetría observada

| Span | Atributos útiles |
|---|---|
| `invoke_agent spike-reviewer` | `gen_ai.agent.name`, `gen_ai.agent.id` (`project:spike-reviewer`), `gen_ai.request.model`, `github.copilot.git.branch` |
| `chat <modelo>` | `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.usage.cache_read.input_tokens`, `gen_ai.usage.cache_creation.input_tokens`, `gen_ai.usage.reasoning.output_tokens`, `github.copilot.cost` |
| `execute_tool <tool>` | `gen_ai.tool.name`, `gen_ai.tool.call.id` |
| *resource* | `service.name=github-copilot`, `service.version`, **`sdd.change_id`, `sdd.phase`** (vía `OTEL_RESOURCE_ATTRIBUTES`) |

Métricas disponibles: `gen_ai.client.token.usage`, `gen_ai.invoke_agent.duration`, `gen_ai.invoke_agent.inference_calls`, `gen_ai.invoke_agent.tool_calls`, `github.copilot.tool.call.count`, `github.copilot.code.lines_added/removed`, etc.

## Opciones del CLI relevantes para el proyecto

| Opción | Uso en SDD |
|---|---|
| `-p, --prompt` | Ejecución no interactiva (revisores, retrospective en CI) |
| `--agent <nombre>` | Ejecuta un agente de `.github/agents/` |
| `--model <modelo>` | **Fijar siempre**: sin él, la prueba usó `claude-haiku-4.5` por defecto |
| `--effort <nivel>` | Esfuerzo de razonamiento por revisor |
| `--no-ask-user` | Autonomía total (sin preguntas) |
| `--allow-all-tools` / `--allow-tool` / `--deny-tool` | Permisos; revisores: solo lectura + `shell(dotnet:*)` |
| `--output-format json` | Salida JSONL parseable para consolidar informes |
| `--max-ai-credits <n>` | **Límite de gasto** por ejecución |
| `--secret-env-vars` | Redacción de secretos en salida y entorno |
| `--share <ruta>` | Exportar la sesión a Markdown (evidencia para la PR) |

Variables OTel: `COPILOT_OTEL_ENABLED`, `OTEL_EXPORTER_OTLP_ENDPOINT` (solo HTTP; `http/json` por defecto o `http/protobuf`), `COPILOT_OTEL_FILE_EXPORTER_PATH`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`.

## Conclusiones para el plan

1. ✅ La **revisión paralela tiene un camino garantizado**: `scripts/parallel-review.ps1` puede lanzar 4 procesos `copilot -p --agent reviewer-* --model <m>` en paralelo (`Start-Job`). Funciona igual en local y en GitHub Actions y no depende de que los subagentes de VS Code corran en paralelo.
2. ✅ La **correlación por change** funciona con `OTEL_RESOURCE_ATTRIBUTES=sdd.change_id=…,sdd.phase=…`, además de la rama.
3. ✅ El **coste por llamada** viene en `github.copilot.cost`, así que podemos mostrarlo en la sección 📈 de la PR.
4. ⚠️ Fijar `--model` en cada invocación y `--max-ai-credits` como límite de gasto.
