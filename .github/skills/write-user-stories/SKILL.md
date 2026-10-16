---
name: write-user-stories
description: Write INVEST user stories with Gherkin acceptance criteria (in Spanish) and create them as GitHub Issues ready for the human Gate 1. Use when turning an idea, epic or need into requirements for the SDD cycle.
license: MIT
---

# Escribir historias de usuario para el ciclo SDD

## 1. Calidad de una historia (INVEST + Definition of Ready)

| Criterio | Comprobación |
|---|---|
| Independiente | Se puede implementar y entregar sola (o sus dependencias están explícitas) |
| Negociable | Describe el *qué* y el *para qué*, no el *cómo* |
| Valiosa | Un usuario (jugador, administrador) nota la diferencia |
| Estimable / Pequeña | **S** < 150 líneas de producción, **M** 150–400. **L → dividir** antes de proponerla |
| Testeable | Cada criterio es un escenario Gherkin observable |

## 2. Escenarios Gherkin (español)

- Mínimo **uno feliz y uno de error** por historia; añade los bordes evidentes (límites de horario, solapamientos exactos, pasado/futuro).
- **Datos concretos**: `Dado que la pista "Pádel 1" abre de 08:00 a 22:00` en lugar de `Dado que la pista está abierta`.
- Para errores de API indica el resultado observable: `Entonces recibe 409 y un ProblemDetails de tipo "booking-overlap"`.
- Títulos de escenario únicos dentro de la capacidad (se convertirán en trazas de tests).

```gherkin
Escenario: Reserva de una franja libre
  Dado que la pista "Pádel 1" está libre el 2026-11-10 de 18:00 a 19:30
  Cuando el jugador "ana@example.com" reserva esa franja
  Entonces la reserva queda confirmada
  Y la franja deja de aparecer como disponible

Escenario: Reserva solapada rechazada
  Dado que existe una reserva confirmada en "Pádel 1" el 2026-11-10 de 18:00 a 19:30
  Cuando otro jugador intenta reservar de 19:00 a 20:30 en la misma pista
  Entonces recibe 409 con un ProblemDetails de tipo "booking-overlap"
```

## 3. Cuerpo del Issue

Replica las secciones del Issue Form `.github/ISSUE_TEMPLATE/user-story.yml` (los formularios no se aplican vía API):

````markdown
### Change ID (OpenSpec)

add-create-booking

### Capacidad

bookings

### Historia de usuario

Como jugador
quiero reservar una franja libre de una pista
para asegurarme de que puedo jugar a esa hora

### Criterios de aceptación (Gherkin)

```gherkin
Escenario: …
```

### Fuera de alcance

- Pagos

### Prioridad

Alta

### Tamaño estimado

M (150-400 líneas)

### Dependencias

Depende de #12 (add-authentication)

### Definition of Ready

- [x] La historia aporta valor y es independiente (INVEST)
- [x] Hay al menos un escenario feliz y uno de error
- [x] Cabe en una PR pequeña (S/M)
````

## 4. Crear los Issues

Este agente **no tiene herramienta de edición de ficheros** (a propósito): el cuerpo se escribe en un fichero temporal **desde la terminal**, con un here-string de **comillas simples** (lección L-006: no interpreta `` ` `` ni `$`).

**Seguridad (CWE-94):** el cuerpo contiene texto de la idea, que no es de confianza. Por eso:
1. Escribe **todos** los cuerpos **antes** de cargar la identidad del bot y en una invocación de terminal **sin** `agent-auth.ps1`: si el texto rompiera el here-string, no habría token al alcance.
2. Ninguna línea del cuerpo puede empezar por `'@`, porque cerraría el here-string. Si aparece, añádele un espacio delante.

```powershell
# Paso 1 · sin identidad del bot: solo escribe ficheros temporales
$body = Join-Path ([IO.Path]::GetTempPath()) "story-<change-id>.md"
@'
### Change ID (OpenSpec)

add-create-booking
…resto del cuerpo de la sección 3…
'@ | Set-Content $body -Encoding utf8
```

```powershell
# Paso 2 · con identidad del bot: solo publica
. "$env:SDD_TOOLS/scripts/agent-auth.ps1"
gh issue create --title "[C4] bookings: crear reserva" --body-file $body `
  --label needs-approval --milestone "M4 · MVP de reservas"
Remove-Item $body
& "$env:SDD_TOOLS/scripts/sdd-board.ps1" -Issue <n> -Status idea -ChangeId add-create-booking
```

- No intentes usar herramientas de creación o edición de ficheros (`create`, `edit`): no están disponibles para este agente.
- Comprueba el resultado publicado: `gh issue view <n> --json body --jq .body` (sin `\` sueltos ni backticks perdidos).

- Título: `[Cn] <capacidad>: <resumen en minúscula>`; `Cn` según el backlog del ROADMAP (§5, F9) o el siguiente libre.
- Épica: un Issue `[Épica] …` con una lista de tareas `- [ ] #<n>` que enlaza cada historia.
- Nunca añadas el label `approved`: es el Gate 1 del humano.
