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
| D-11 | Identidad de los agentes | **GitHub App `sdd-agent-mapps`**: commits y PRs firmados como `sdd-agent-mapps[bot]`. GitHub no permite aprobar PRs propias, y así el humano hace una aprobación real y se puede medir "0 líneas escritas por el humano". Credenciales fuera del repo en `~/.sdd/`. La sesión cambia a esta identidad con `. ./scripts/agent-auth.ps1` |

## Modelos por agente — aprobada el 2026-10-15 (revisada en F4, D-12)

Criterios:
- Los 4 revisores usan **modelos distintos** entre sí y respecto al implementer, para reducir puntos ciegos compartidos.
- **Coste:** todos los modelos preferidos tienen multiplicador **1x** (medido con la telemetría, `github.copilot.cost` por llamada). Claude Opus 5.5 cuesta **15x** y queda solo como fallback.
- En VS Code un subagente no puede superar el nivel de coste del conductor: si el conductor cae a su fallback (Opus), los subagentes pueden usar el suyo; al revés no.

| Agente | Modelo preferido | Fallback | Motivo |
|---|---|---|---|
| `sdd-conductor` | Claude Sonnet 5.5 | Claude Opus 5.5 | Orquestación larga con muchas llamadas: 1x |
| `po-analyst` | Claude Sonnet 5.5 | GPT-5.6 Sol | Redacción de historias y Gherkin |
| `spec-architect` | Claude Sonnet 5.5 | Claude Opus 5.5 | Diseño y especificación |
| `implementer` | Claude Sonnet 5.5 | Claude Opus 5.5 | Código y TDD |
| `reviewer-spec` | GPT-6.1 Sol | GPT-6 Sol | Familia distinta al implementer |
| `reviewer-architecture` | Gemini 4 Argon | Gemini 3.8 Flash | Familia distinta |
| `reviewer-security` | Grok 4.7 | Grok 4.6 | Familia distinta |
| `reviewer-tests` | GPT-5.3-Codex | MAI-Code-1.1-Flash | Especializado en código y distinto del implementer (antes Claude Sonnet 5.5, que ahora usa el implementer) |
| `pr-author` | Claude Haiku 5.5 | GPT-5.4 mini | Tarea mecánica |
| `retrospective` | GPT-6.1 Sol | Claude Sonnet 5.5 | Análisis y síntesis; perspectiva distinta al implementer |

> Disponibilidad verificada en F4-12 (prueba en seco de los 10 agentes con su modelo preferido) y con sondas de 1 llamada para GPT-5.3-Codex, MAI-Code-1.1-Flash, Claude Sonnet 5 y 5.5 (todas 1x). `kimi-k3`, el fallback original de `reviewer-tests`, no está disponible en la cuenta.

**Formato en los agentes (F4):** el campo `model` de cada `.agent.md` es una **lista de nombres visibles** con fallback, p. ej. `model: ['Claude Sonnet 5.5', 'Claude Opus 5.5']`. VS Code prueba los modelos en orden y Copilot CLI acepta el mismo formato. El flag `--model` del CLI solo acepta ids, así que `scripts/parallel-review.ps1` convierte los nombres (lección L-004) y reintenta con el siguiente modelo si el primero falla.

## D-12 · Coste de modelos (F4) — aprobada el 2026-10-15

La prueba en seco mostró que Claude Opus 5.5 consume **15 créditos premium por llamada** frente a 1 del resto: 90 de los 104 créditos de la prueba. Decisión del aprobador: **Claude Sonnet 5.5 (1x)** en conductor, spec-architect e implementer, con Opus solo como fallback.