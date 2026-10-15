---
description: "SDD · Consolidar la memoria del proceso (cada 3 changes)"
agent: retrospective
---

Ejecuta el modo `consolidate` del agente retrospective siguiendo la skill `capture-lessons`:

1. Promociona las lecciones con Ocurrencias ≥ 2 al destino más automático posible y poda las obsoletas (`lessons.md` ≤ 150 líneas).
2. Incorpora los Issues `lesson-candidate` pendientes a `approver-preferences.md` o `lessons.md`.
3. Resume en 5 líneas la tendencia de `.sdd/metrics/history.csv`.
4. Abre una PR `chore(process): consolidación de memoria` con label `process` como `sdd-agent-mapps[bot]` (skill `pr-evidence`).
