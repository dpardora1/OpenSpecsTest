---
description: "SDD · Convertir una idea en Issues aprobables (Gate 1)"
agent: po-analyst
argument-hint: Describe la idea, épica o necesidad
---

Convierte la siguiente idea en historias de usuario para el ciclo SDD siguiendo la skill `write-user-stories`:

${input:idea:Describe la idea o épica}

1. Revisa specs vigentes, Issues abiertos y el backlog del ROADMAP para no duplicar.
2. Muestra primero el borrador (tabla resumen + historias con Gherkin) y espera confirmación antes de crear Issues.
3. Tras la confirmación, crea los Issues como `sdd-agent-mapps[bot]` con label `needs-approval`, milestone y tarjeta en "💡 Idea".
4. Termina con la tabla de Issues creados y recuérdame que el Gate 1 es añadir el label `approved`.
