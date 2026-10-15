---
description: "SDD · Llevar un Issue aprobado hasta la siguiente aprobación humana (spec o implementación)"
agent: sdd-conductor
argument-hint: "#<issue>"
---

Ejecuta el ciclo SDD para el Issue ${input:issue:#número del Issue aprobado}.

- Si la spec del change aún no está en `main`: **Etapa A**. Crea la spec y abre la PR de spec; para en el Gate 2.
- Si la spec ya está en `main`: **Etapa B**. Implementa con TDD, verifica, lanza las 4 revisiones en paralelo (máx. 3 iteraciones), archiva, captura lecciones y métricas y abre la PR de implementación; para en el Gate 3.

Prepara las herramientas de confianza (`$env:SDD_TOOLS`, AGENTS.md §3) y úsalas para todo: marca cada fase con `& "$env:SDD_TOOLS/scripts/sdd-phase.ps1"`, actualiza el tablero con `& "$env:SDD_TOOLS/scripts/sdd-board.ps1"` (nunca con la copia de la rama) y termina con un resumen corto: URL de la PR, qué debo revisar, veredictos de los revisores y métricas clave.
