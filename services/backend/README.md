# Fida-Taxi Backend

This backend belongs only to the Fida-Taxi project. It does not use or control the Fida-Ride database, Redis instance, containers, environment file, or runtime checkout.

Services:
- NestJS business API under `services/backend`
- PostgreSQL/PostGIS in `fida-taxi-postgres`
- Redis in `fida-taxi-redis`
- Go telemetry service under `services/telemetry`

The mobile apps use the API contract under `/api/v1`.
