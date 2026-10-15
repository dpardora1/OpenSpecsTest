# OpenSpecsTest — Portal de reservas de pistas con SDD potenciado por agentes

Demo de **Spec-Driven Development** con [OpenSpec](https://github.com/Fission-AI/OpenSpec) y GitHub Copilot: la IA hace todo el trabajo (requisitos → spec → código → pruebas → revisión → PR) y el humano solo aprueba.

- 📋 [Plan del proyecto y metodología](./PLAN-PROYECTO-SDD.md)
- 🗺️ [Roadmap](./ROADMAP.md)
- ✅ [Registro de decisiones](./docs/decisions.md)
- 🔬 Spikes: [VS Code agents](./docs/spikes/vscode-agents.md) · [Copilot CLI](./docs/spikes/copilot-cli.md)
- 📈 [Observabilidad del proceso de agentes](./observability/README.md)

> Estado: **Fase F5 — Quality gate y CI** (PR en revisión). Quality gate local = CI: `./scripts/quality-gate.ps1`.

## Cómo trabajan los agentes en este repo

- Reglas para agentes: [AGENTS.md](./AGENTS.md) · agentes en [`.github/agents/`](./.github/agents) · skills en [`.github/skills/`](./.github/skills) · memoria en [`.sdd/memory/`](./.sdd/memory).
- Comandos en Copilot Chat: `/sdd-new-requirement <idea>` (Issues para el Gate 1) · `/sdd-deliver #<issue>` (ciclo completo hasta el siguiente gate) · `/sdd-consolidate` (memoria, cada 3 changes) · `/opsx-*` (OpenSpec).
- Los agentes firman commits y PRs como **`sdd-agent-mapps[bot]`** (GitHub App). El humano solo aprueba.
- Para actuar como el bot en una sesión local: `. "$env:SDD_TOOLS/scripts/agent-auth.ps1"`, siempre desde la copia de confianza de `origin/main` descrita en [AGENTS.md §3](./AGENTS.md) (requiere `~/.sdd/sdd-agent.json` y `sdd-agent.pem`, creados con `node scripts/bootstrap/create-agent-app.mjs`).
- `main` está protegida: solo se modifica mediante PR con aprobación del code owner.
