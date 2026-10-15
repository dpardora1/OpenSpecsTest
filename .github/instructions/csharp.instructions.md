---
description: C# conventions for the Court Booking solution (.NET 10, vertical slices, Minimal APIs).
applyTo: "**/*.cs"
---

# C# conventions

- File-scoped namespaces matching the folder path; one public type per file.
- `sealed` by default for classes that are not designed for inheritance; `record` for immutable DTOs and value objects.
- Use primary constructors for DI in handlers and services; keep constructors free of logic.
- Endpoint mapping per slice: a static `Map<UseCase>(this IEndpointRouteBuilder app)` extension in the slice folder, registered from the capability's endpoint group. Return `TypedResults` with an explicit `Results<...>` union type.
- Request validation lives in the slice; domain invariants live in `CourtBooking.Domain` and are enforced there, not in the endpoint.
- Domain methods return `Result`/`Result<T>` for expected failures; exceptions only for programming errors.
- `DateTime.Now`, `DateTime.UtcNow`, `DateTimeOffset.Now` and `DateTimeOffset.UtcNow` are banned: use the injected `TimeProvider`.
- EF Core: configurations in `Infrastructure/Persistence/Configurations` via `IEntityTypeConfiguration<T>`; queries use `AsNoTracking()` for reads; project to DTOs with `Select` instead of loading graphs; avoid N+1 (no lazy loading).
- Concurrency-sensitive writes (e.g. creating a booking) must be protected at the database level (unique/exclusion constraint or serializable transaction), not only by a prior read.
- Logging: `ILogger<T>` with message templates and event names; no string interpolation in log calls; no personal data.
- No `#pragma warning disable` or `[SuppressMessage]` without a justification comment that references a lesson or ADR.
