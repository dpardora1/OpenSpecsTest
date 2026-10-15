---
description: Conventions for OpenSpec specs and changes in this repository.
applyTo: "openspec/**"
---

# OpenSpec conventions

- Artifacts in **Spanish**; OpenSpec structural headings and the keywords `SHALL`/`MUST` stay in English (`## ADDED Requirements`, `### Requirement:`, `#### Scenario:`).
- Capabilities (one folder each under `openspec/specs/`): `platform`, `courts`, `availability`, `identity`, `bookings`. Do not create new capabilities without a reason in `design.md`.
- Change IDs are kebab-case verbs (`add-create-booking`, `update-cancellation-policy`) and must match the Issue's "Change ID" field and the branch `sdd/<change-id>`.
- Every requirement has at least one happy-path and one error scenario. Scenarios use concrete data (dates, times, durations, prices) and, for API errors, the HTTP status and ProblemDetails `type`.
- Scenario titles are unique within a capability: they become test traits (`<capability>/<scenario-slug>`).
- `proposal.md` links the source Issue (`Closes #n` in the implementation PR, `Refs #n` in the spec PR) and has a "Fuera de alcance" section.
- `tasks.md`: tests first (one task per scenario), then implementation, then docs; final task "Ejecutar scripts/quality-gate.ps1 en verde".
- Always run `openspec validate <change-id> --strict` after editing a change. Never edit `openspec/specs/` directly: only through archiving a change.
