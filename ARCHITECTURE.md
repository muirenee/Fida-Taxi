# Fida Taxi Architecture Invariants

1. Mobile clients are not authoritative for ride lifecycle, dispatch, fare settlement, payments, or driver earnings.
2. The shared `fida_core` package is pure Dart and has no Flutter, Firebase, HTTP, map SDK, database, or Riverpod dependencies.
3. Rider and Driver apps consume authoritative ride revisions from the backend and ignore stale events.
4. Secrets and service-account credentials never ship in client applications.
5. Realtime transport is an implementation detail behind application/domain boundaries.
6. CI must pass formatting, static analysis, unit tests, Flutter tests, and Android debug compilation before foundation changes are merged.

## Repository boundaries

- `muirenee/Fida-Taxi` owns the Rider and Driver mobile applications, the pure Dart domain model, transport clients, and the shared design system.
- `muirenee/Fida-Ride` owns the backend platform: NestJS business API, PostgreSQL/PostGIS, Redis, dispatch/bidding, finance, fraud controls, and the Go telemetry service.
- Backend functionality must not be duplicated in the mobile repository. Mobile code talks to the backend through `packages/fida_api`.
- `fida_core` remains transport-agnostic. Backend-specific field names and legacy backend trip states are translated inside `fida_api`, not inside the domain package.

## Backend contract alignment

The backend database is authoritative for supported vehicle types. Mobile wire values are therefore:

`taxi`, `moto`, `premium`, `tuk_tuk`, `ev`, `accessible`, and `other`.

The current backend trip table uses a smaller persistence state set than the mobile ride lifecycle. The API boundary maps only unambiguous states:

- `created` -> `quoting`
- `matching` -> `searching`
- `accepted` -> `driver_assigned`
- `picked_up` -> `in_progress`
- `completed` -> `completed`

Backend `cancelled` is intentionally not mapped to a domain cancellation state because the existing persistence value does not identify who cancelled the trip. The backend contract must carry an explicit cancellation reason/actor before the mobile domain consumes it as `cancelled_by_rider` or `cancelled_by_driver`.
