# Registro de decisiones

Decisiones de la Fase F0 (F0-06 y F0-07). Cualquier cambio posterior se registra aquí mediante PR.

## Decisiones del proyecto (F0-07) — aprobadas el 2026-10-15

| ID | Decisión | Resolución |
|---|---|---|
| D-01 | Repositorio | <https://github.com/dpardora1/OpenSpecsTest> · **Público** desde el inicio. En el plan Free, un repo privado no permite rulesets, CodeQL ni secret scanning; público lo permite todo gratis |
| D-02 | Licencia | MIT |
| D-03 | Idioma | Specs, Issues y PRs en español; código, identificadores y commits en inglés |
| D-04 | Modelos por agente | Ver tabla F0-06 |
| D-05 | Copilot cloud agent | Local + cloud para changes paralelos (C6, C7) |
| D-06 | Backend de observabilidad | Grafana LGTM local (`docker compose`) |
| D-07 | `captureContent` en trazas | Sí (entorno local de demo) |
| D-08 | Experimento Mem0 / OpenMemory | Sí, desde C4, como experimento medible |
| D-09 | Preview por PR en Azure | No para la demo base (backlog futuro) |
| D-10 | PR de spec y PR de código | Separadas (modo rápido solo para cambios triviales) |

## Modelos por agente (F0-06) — propuesta pendiente de aprobación

Criterios:
- Los 4 revisores usan **familias de modelo distintas** entre sí y respecto al implementer, para reducir puntos ciegos compartidos.
- El conductor usa un modelo de nivel alto, porque un subagente no puede superar su nivel de coste.
- Las tareas mecánicas usan modelos rápidos y baratos.

| Agente | Modelo preferido | Fallback | Motivo |
|---|---|---|---|
| `sdd-conductor` | `claude-opus-5.5` | `claude-sonnet-5.5` | Orquestación larga; nivel alto para habilitar subagentes |
| `po-analyst` | `claude-sonnet-5.5` | `gpt-5.6-sol` | Redacción de historias y Gherkin |
| `spec-architect` | `claude-opus-5.5` | `gpt-6.1-sol` | Diseño y especificación |
| `implementer` | `claude-opus-5.5` | `gpt-5.3-codex` | Máxima calidad de código y TDD |
| `reviewer-spec` | `gpt-6.1-sol` | `gpt-6-sol` | Familia distinta al implementer |
| `reviewer-architecture` | `gemini-4-argon` | `gemini-3.8-flash` | Familia distinta |
| `reviewer-security` | `grok-4.7` | `grok-4.6` | Familia distinta |
| `reviewer-tests` | `claude-sonnet-5.5` | `kimi-k3` | Claude, pero distinto modelo que el implementer |
| `pr-author` | `claude-haiku-5.5` | `gpt-5.4-mini` | Tarea mecánica, bajo coste |
| `retrospective` | `gpt-6.1-sol` | `claude-sonnet-5.5` | Análisis y síntesis; perspectiva distinta al implementer |

> La disponibilidad real de cada modelo en la cuenta se comprueba en F4-12 (prueba en seco). Si alguno no está disponible, se usa el fallback y se registra aquí.
