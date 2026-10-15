# Spike F0-04 · Agentes personalizados, subagentes, memoria y hooks en VS Code

- **Fecha:** 2026-10-15
- **Versión:** VS Code `1.141.1`
- **Resultado:** ✅ Formato confirmado en documentación oficial · ⏳ Paralelismo real de subagentes a medir en F7

## Agentes personalizados (`.github/agents/*.agent.md`)

Campos de frontmatter confirmados:

| Campo | Uso en el proyecto |
|---|---|
| `name`, `description`, `argument-hint` | Identidad y ayuda de cada agente |
| `tools` | Herramientas mínimas por rol (revisores: solo lectura) |
| `agents` | Subagentes permitidos. El `sdd-conductor` lista explícitamente sus trabajadores; requiere la herramienta `agent` en `tools` |
| `model` | Modelo o **lista priorizada con fallback**: si el primero no está disponible, prueba el siguiente |
| `user-invocable: false` | Oculta revisores y trabajadores del selector; solo los invoca el conductor |
| `disable-model-invocation` | Impide que un agente se use como subagente (p. ej. `po-analyst` solo bajo demanda humana) |
| `handoffs` | Botones de traspaso entre agentes (p. ej. spec-architect → implementer) |
| `hooks` | Hooks que solo se ejecutan para ese agente |
| `target` | `vscode` o `github-copilot` (cloud agent) |

## Subagentes

- El harness Local usa la herramienta `runSubagent`. Cada subagente trabaja en su propio contexto y devuelve un resultado acotado.
- Orden de selección de modelo: parámetro explícito → `model` del agente → Auto (si `chat.subagents.defaultToAuto`) → modelo de la conversación principal.
- ⚠️ **Restricción de nivel de coste:** si el modelo de un subagente supera el nivel de coste del modelo principal, **el subagente no se ejecuta**. El `sdd-conductor` debe correr con un modelo de nivel alto para que los revisores puedan usar el suyo.
- Las trazas OTel propagan el contexto: cada subagente aparece como hijo del `execute_tool runSubagent` de su padre.
- ⏳ **Paralelismo:** la documentación no garantiza explícitamente que se ejecuten en paralelo. Se medirá en F7-04 con Grafana. **Plan B ya validado:** procesos paralelos de Copilot CLI (ver [copilot-cli.md](./copilot-cli.md)).

## Memoria

- Herramienta de memoria del agente (`github.copilot.chat.tools.memory.enabled`), con ámbitos `/memories/` (usuario), `/memories/repo/` (workspace) y `/memories/session/`. Se inspecciona con *Chat: Show Memory Files*.
- GitHub Copilot Memory (nativa) se activa por usuario en <https://github.com/settings/copilot/memory>. **Acción humana: F0-03.**

## Hooks

- Ubicaciones: `.github/hooks/*.json` (workspace), `~/.copilot/hooks/*.json` (usuario), `hooks` en el frontmatter de un agente.
- Eventos confirmados: `PreToolUse`, `PostToolUse` (formato `{"hooks": {"PreToolUse": [{"type": "command", "command": "...", "windows": "powershell -File ...", "timeout": 15}]}}`).
- La sesión del harness Copilot usa la implementación de hooks del Copilot CLI. Los eventos de sesión y subagente se confirman en F3-04 con `/create-hook`.
- El hook recibe un JSON por stdin (`timestamp`, `tool_name`, …), lo que permite emitir eventos `sdd.phase.*` a `.sdd/telemetry/`.

## OpenTelemetry (Copilot Chat)

Ajustes confirmados: `github.copilot.chat.otel.enabled`, `exporterType` (`otlp-http` | `otlp-grpc` | `console` | `file`), `otlpEndpoint`, `captureContent`, `outfile`, `dbSpanExporter.enabled`. La telemetría de una sesión de Copilot CLI lanzada desde VS Code aparece como traza independiente (`service.name=github-copilot`).

## Decisiones derivadas

1. Los revisores y trabajadores llevan `user-invocable: false`. El conductor lista sus `agents` explícitamente.
2. Cada agente lleva `model` como lista priorizada (modelo preferido + fallback) para tolerar falta de disponibilidad.
3. El `sdd-conductor` corre con un modelo de nivel alto (restricción de coste de subagentes).
4. Revisión paralela con dos caminos: subagentes de VS Code (experiencia interactiva) y `parallel-review.ps1` con Copilot CLI (determinista, también en CI).
