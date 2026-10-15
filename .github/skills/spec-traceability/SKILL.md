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
./scripts/traceability.ps1 -Change <id>     # (fase F5) falla si algún escenario del change no tiene test o su test falla
dotnet test --filter "Scenario=bookings/reserva-solapada-rechazada"   # ejecutar los tests de un escenario
```

## Tabla para la PR

| Escenario (spec) | Test | Resultado |
|---|---|---|
| bookings/reserva-solapada-rechazada | `CreateBookingTests.CreateBooking_OverlappingSlot_Returns409` | ✅ |

Un escenario sin test o con test en rojo es un **BLOCKER** en la revisión.
