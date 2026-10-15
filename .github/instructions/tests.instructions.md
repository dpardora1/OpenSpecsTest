---
description: Testing conventions (xUnit v3, Shouldly, spec traceability, deterministic tests).
applyTo: "tests/**"
---

# Testing conventions

- Write the test **before** the implementation, derived from a spec scenario (WHEN/THEN). Run it and confirm it fails for the right reason.
- Name tests `<Method>_<Scenario>_<ExpectedResult>` or a readable sentence; arrange/act/assert separated by blank lines.
- Trace every scenario test: `[Trait("Scenario", "<capability>/<scenario-slug>")]` where the slug is the scenario title in kebab-case, lowercase, without accents (see skill `spec-traceability`).
- Use Shouldly assertions with meaningful messages; one logical assertion group per test; assert on behavior (HTTP status, ProblemDetails `type`/`title`, persisted state), not on implementation details.
- Time: `FakeTimeProvider` with explicit dates; never `DateTime.Now`. Culture-independent assertions.
- Integration tests use a real PostgreSQL (Aspire testing or Testcontainers) and reset state between tests; no shared mutable state across test classes.
- Concurrency scenarios (e.g. two simultaneous bookings for the same slot) need an explicit test that runs the operations in parallel and asserts exactly one wins.
- No `Thread.Sleep`, no `Skip` without a linked Issue, no tests without assertions, no catch-all `try/catch` in tests.
- E2E (Playwright): stable `data-testid` selectors; capture trace and screenshot on failure.
