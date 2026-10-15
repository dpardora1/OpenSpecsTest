# Lecciones aprendidas

Memoria procedimental del proceso SDD. **Todos los agentes la leen al empezar** y aplican las lecciones con su rol en "Aplica a". La mantiene el agente `retrospective` (skill `capture-lessons`); cada cambio pasa por PR y lo aprueba el humano.

- Formato y criterios: [`.github/skills/capture-lessons/SKILL.md`](../../.github/skills/capture-lessons/SKILL.md)
- Promoción: Ocurrencias ≥ 2 → validación automática > skill > instrucción > AGENTS.md
- Límite: 150 líneas (lo promovido u obsoleto pasa a "Histórico" en una línea)

## Activas

### L-001 · Los hooks de Copilot CLI solo se ejecutan en carpetas de confianza
- Origen: F3 observabilidad · prueba de humo · los hooks no se disparaban en modo `-p`
- Contexto: la confianza se guarda en `~/.copilot/config.json` → `trustedFolders`, no en `settings.json`
- Regla: antes de depender de hooks en una máquina o runner nuevo, comprueba que la ruta del repo está en `trustedFolders`; si `.sdd/telemetry/events.jsonl` no recibe `sessionStart`, revisa esto primero
- Aplica a: sdd-conductor, retrospective · Tags: telemetría, hooks, entorno
- Ocurrencias: 1 · Estado: activa

### L-002 · Los ajustes OTel de Copilot Chat son de ámbito usuario
- Origen: F3/F4 observabilidad · las trazas de VS Code no llegaban con `.vscode/settings.json`
- Contexto: `github.copilot.chat.otel.*` tiene `scope: application`; VS Code lo ignora a nivel de workspace
- Regla: configúralo en los ajustes de usuario con `./scripts/bootstrap/enable-agent-telemetry.ps1`; no lo añadas a `.vscode/settings.json`
- Aplica a: sdd-conductor, retrospective · Tags: telemetría, vscode, entorno
- Ocurrencias: 1 · Estado: activa

### L-003 · Fechas con cultura invariante en los scripts
- Origen: F3 `sdd-phase.ps1` · `ConvertFrom-Json` convertía el timestamp con la cultura `es-ES` y `Parse` fallaba
- Contexto: PowerShell 7 convierte cadenas ISO a `DateTime` automáticamente al deserializar JSON
- Regla: en scripts usa `ConvertFrom-Json -DateKind String` y `[DateTimeOffset]::Parse(x, [CultureInfo]::InvariantCulture)`; nunca dependas de la cultura de la máquina (aplica también al código .NET: `CultureInfo.InvariantCulture` en parseo y formato técnico)
- Aplica a: implementer, reviewer-tests · Tags: tiempo, cultura, scripts
- Ocurrencias: 1 · Estado: activa

## Histórico

_(vacío)_
