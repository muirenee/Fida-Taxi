# Fida Taxi Architecture Invariants

1. Mobile clients are not authoritative for ride lifecycle, dispatch, fare settlement, payments, or driver earnings.
2. The shared `fida_core` package is pure Dart and has no Flutter, Firebase, HTTP, map SDK, database, or Riverpod dependencies.
3. Rider and Driver apps consume authoritative ride revisions from the backend and ignore stale events.
4. Secrets and service-account credentials never ship in client applications.
5. Realtime transport is an implementation detail behind application/domain boundaries.
6. CI must pass formatting, static analysis, unit tests, Flutter tests, and Android debug compilation before foundation changes are merged.
