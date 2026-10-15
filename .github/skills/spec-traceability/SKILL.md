---
name: spec-traceability
description: Link every OpenSpec scenario to the tests that verify it with xUnit traits and check coverage of scenarios. Use when writing tests for a change, reviewing test coverage or preparing PR evidence.
license: MIT
---

# Trazabilidad escenario → test

## Convención

Cada test que verifica un escenario lleva:

```csharp
[Fact]
[Trait("Scenario", "bookings/reserva-solapada-rechazada")]
public async Task CreateBooking_OverlappingSlot_Returns409() { … }
```

- Formato: `<capability>/<scenario-slug>`.
- `capability`: carpeta del delta (`openspec/changes/<id>/specs/<capability>/spec.md`).
- `scenario-slug`: el título de `#### Scenario: <título>` en minúsculas, sin acentos ni signos, con espacios → `-`. Ejemplo: `Scenario: Reserva solapada rechazada` → `reserva-solapada-rechazada`.
- Un escenario puede tener varios tests (unit + integración); un test puede trazar varios escenarios con varios `[Trait]`.

Cálculo del slug en PowerShell:

```powershell
$t = 'Reserva solapada rechazada'
($t.Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
```

## Comprobación

```powershell
& "$env:SDD_TOOLS/scripts/quality-gate.ps1" -Change <id>                 # ejecuta los tests y traza con el TRX resultante
& "$env:SDD_TOOLS/scripts/traceability.ps1" -Change <id> -ResultsDir <carpeta con *.trx>   # solo la trazabilidad
dotnet test --filter-trait "Scenario=bookings/reserva-solapada-rechazada" # ejecutar los tests de un escenario (MTP)
```

- **Fuente de verdad:** el TRX de Microsoft.Testing.Platform, que incluye los traits de cada test y su resultado. Un escenario pasa solo si ≥ 1 test con su trait **se ejecutó y pasó** y ninguno falló. Con `-RequireTrx` (lo usa el gate cuando hay solución .NET) la falta de TRX es un fallo.
- Sin TRX (p. ej. sin solución .NET), `traceability.ps1` busca los traits en `tests/**/*.cs` y sale con código **3**: es un diagnóstico, nunca un aprobado.
- Escenarios considerados: los de `## ADDED Requirements` y `## MODIFIED Requirements` de los deltas. Los `REMOVED`/`RENAMED` no necesitan test.
- Un change de tooling o documentación declara `skip_specs: true` en su `.openspec.yaml`. Solo se respeta si el change **no tiene escenarios** ADDED/MODIFIED: nunca puede ocultarlos.
- Avisa de **traits huérfanos**: traits de la misma capacidad que no corresponden a ningún escenario del change ni de las specs vigentes, normalmente una errata en el slug.

## Tabla para la PR

| Escenario (spec) | Test | Resultado |
|---|---|---|
| bookings/reserva-solapada-rechazada | `CreateBookingTests.CreateBooking_OverlappingSlot_Returns409` | ✅ |

Un escenario sin test o con test en rojo es un **BLOCKER** en la revisión.
