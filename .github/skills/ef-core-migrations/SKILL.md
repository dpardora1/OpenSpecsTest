---
name: ef-core-migrations
description: Create, verify and review EF Core 10 migrations for the PostgreSQL database following project conventions (one migration per change, never edit applied migrations). Use when a change modifies the persistence model.
license: MIT
---

# Migraciones EF Core

## Convenciones

- **Una migración por change**, nombrada en PascalCase con el propósito: `AddCourts`, `AddBookingOverlapConstraint`.
- Proyecto de migraciones: `src/CourtBooking.Api`, carpeta `Infrastructure/Persistence/Migrations`.
- Nunca edites ni borres una migración que ya está en `main`; corrige con una migración nueva.
- Restricciones de integridad **en la base de datos** (únicos, `CHECK`, exclusión para solapamientos de reservas), no solo en código.
- Tipos: `timestamp with time zone` para `DateTimeOffset`; importes con precisión explícita.

## Comandos

```powershell
dotnet tool restore                                     # dotnet-ef fijado en el manifiesto de herramientas
dotnet ef migrations add <Name> --project src/CourtBooking.Api --output-dir Infrastructure/Persistence/Migrations
dotnet ef migrations has-pending-model-changes --project src/CourtBooking.Api   # debe salir 0 tras añadir la migración
dotnet ef migrations script --idempotent --project src/CourtBooking.Api -o $env:TEMP/migration.sql   # revisar el SQL generado
```

## Checklist antes de hacer commit

- [ ] La migración refleja **solo** los cambios de esquema descritos en `design.md`.
- [ ] El SQL generado es el esperado (índices, restricciones, nulabilidad).
- [ ] `has-pending-model-changes` no reporta cambios pendientes.
- [ ] Los tests de integración aplican la migración sobre PostgreSQL real y pasan.
- [ ] Si hay datos semilla, son deterministas (IDs y fechas fijas).
