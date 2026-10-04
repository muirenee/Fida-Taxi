# Fida Taxi Architecture Invariants

1. Mobile clients are not authoritative for ride lifecycle, dispatch, fare settlement, payments, or driver earnings.
2. The shared `fida_core` package is pure Dart and has no Flutter, Firebase, HTTP, map SDK, database, or Riverpod dependencies.
3. Rider and Driver apps consume authoritative ride revisions from the Fida-Taxi backend and ignore stale events.
4. Secrets and service-account credentials never ship in client applications.
5. Realtime transport is an implementation detail behind application/domain boundaries.
6. CI must pass backend type checking/builds, formatting, static analysis, unit tests, Flutter tests, and Android debug compilation before changes are merged.
7. Fida-Taxi and Fida-Ride are separate projects and must never share databases, Redis state, container names, secrets, volumes, or deployment lifecycle.

## Repository boundaries

`muirenee/Fida-Taxi` owns the complete Fida-Taxi product:

- Rider Flutter app
- Driver Flutter app
- shared Dart domain and API packages
- NestJS business API under `services/backend`
- PostgreSQL/PostGIS schema dedicated to Fida-Taxi
- Redis instance dedicated to Fida-Taxi
- Go telemetry service under `services/telemetry`
- Docker deployment under `deploy/`

`muirenee/Fida-Ride` is a different project. Fida-Taxi does not clone, start, stop, migrate, or reuse Fida-Ride runtime services.

`fida_core` remains transport-agnostic. Backend-specific field names are translated inside `fida_api`, not inside the domain package.

## Backend contract

The Fida-Taxi database is authoritative for supported vehicle types. Mobile wire values are:

`taxi`, `moto`, `premium`, `tuk_tuk`, `ev`, `accessible`, and `other`.

The Fida-Taxi trip persistence states map to the mobile lifecycle as follows:

- `created` -> `quoting`
- `matching` -> `searching`
- `accepted` -> `driver_assigned`
- `en_route` -> `driver_en_route`
- `arrived` -> `driver_arrived`
- `picked_up` -> `in_progress`
- `completed` -> `completed`
- `cancelled` -> `cancelled_by_rider` or `cancelled_by_driver` according to `cancellation_actor`

All authoritative ride mutations increment the server revision.
