# OpenSpecsTest — Portal de reservas de pistas con SDD potenciado por agentes

Demo de **Spec-Driven Development** con [OpenSpec](https://github.com/Fission-AI/OpenSpec) y GitHub Copilot: la IA hace todo el trabajo (requisitos → spec → código → pruebas → revisión → PR) y el humano solo aprueba.

- 📋 [Plan del proyecto y metodología](./PLAN-PROYECTO-SDD.md)
- 🗺️ [Roadmap](./ROADMAP.md)
- ✅ [Registro de decisiones](./docs/decisions.md)
- 🔬 Spikes: [VS Code agents](./docs/spikes/vscode-agents.md) · [Copilot CLI](./docs/spikes/copilot-cli.md)
- 📈 [Observabilidad del proceso de agentes](./observability/README.md)

> Estado: **Fase F1 — Repositorio y gobierno** (PR #1 en revisión).

## Cómo trabajan los agentes en este repo

- Los agentes firman commits y PRs como **`sdd-agent-mapps[bot]`** (GitHub App). El humano solo aprueba.
- Para actuar como el bot en una sesión local: `. ./scripts/agent-auth.ps1` (requiere `~/.sdd/sdd-agent.json` y `sdd-agent.pem`, creados con `node scripts/bootstrap/create-agent-app.mjs`).
- `main` está protegida: solo se modifica mediante PR con aprobación del code owner.
