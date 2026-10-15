# Copilot instructions — Court Booking portal

These instructions apply to code generation **and to Copilot code review** in this repository. Process rules for agents live in [AGENTS.md](../AGENTS.md).

## Product

Sports court booking portal (padel, tennis, futsal…): courts catalog, availability, authentication, bookings (create, cancel, list, limits). Functional source of truth: `openspec/specs/**/spec.md`.

## Stack and architecture

- .NET 10 (LTS), C# 14, nullable enabled, `TreatWarningsAsErrors`, latest-recommended analyzers. SDK pinned in `global.json`. Central Package Management (`Directory.Packages.props`).
- .NET Aspire: `CourtBooking.AppHost` orchestrates PostgreSQL + Api + Web; `CourtBooking.ServiceDefaults` provides OpenTelemetry, health checks and resilience.
- **Vertical Slice Architecture**: `src/CourtBooking.Api/Features/<Capability>/<UseCase>/` holds the endpoint, request/response contracts, validation and handler for one use case. Business rules live in `src/CourtBooking.Domain` (entities, value objects, domain services) with **no** dependency on ASP.NET Core or EF Core.
- ASP.NET Core **Minimal APIs** with endpoint groups and `TypedResults`; OpenAPI via `Microsoft.AspNetCore.OpenApi`.
- Errors: **ProblemDetails (RFC 9457)**. Expected business failures are returned as results (Result pattern), not thrown as exceptions.
- Persistence: EF Core 10 + PostgreSQL (Npgsql). One migration per change; never edit a migration that is already on `main`.
- Frontend: Blazor Web App (interactive Server rendering).

## Coding rules

- Time: inject `TimeProvider`; use `DateTimeOffset` in UTC. `DateTime.Now`/`DateTime.UtcNow` are forbidden in Domain and Api.
- Async all the way; accept and pass `CancellationToken`; no `.Result`/`.Wait()`.
- Validate all input at the endpoint boundary; return 400/422 with ProblemDetails.
- Every endpoint declares its authorization explicitly (`RequireAuthorization(...)` or `AllowAnonymous()` with a reason).
- Structured logging with message templates; never log personal data, tokens or full request bodies.
- No raw SQL string concatenation; prefer LINQ. If raw SQL is required, use parameters.
- Prefer small, explicit code over abstractions "for the future". No new dependency without a reason in the change's `design.md`.
- Public types and members get XML docs only when the intent is not obvious from the name.

## Tests

- xUnit v3 on Microsoft.Testing.Platform; Shouldly for assertions.
- Domain → unit tests; API slices → integration tests against real PostgreSQL (Aspire testing / Testcontainers); critical journeys → Playwright E2E; layering → architecture tests.
- Every test that covers a spec scenario carries `[Trait("Scenario", "<capability>/<scenario-slug>")]`.
- Tests must be deterministic: fixed `TimeProvider` (`FakeTimeProvider`), no sleeps, no dependency on machine time zone or culture.

## When reviewing pull requests

Prioritize, in this order: behavior that contradicts the spec scenarios · security (authorization, input validation, data exposure, secrets) · missing or weak tests for spec scenarios · concurrency and data integrity (double booking) · architecture boundaries. Do not comment on formatting (enforced by `dotnet format`). Lessons learned in `.sdd/memory/lessons.md` are project rules.
