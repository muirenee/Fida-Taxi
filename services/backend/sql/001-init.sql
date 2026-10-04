CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE SCHEMA IF NOT EXISTS taxi;

CREATE TABLE IF NOT EXISTS taxi.accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    phone VARCHAR(32) NOT NULL UNIQUE,
    email VARCHAR(255),
    role VARCHAR(16) NOT NULL CHECK (role IN ('rider', 'driver')),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'disabled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS taxi.drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES taxi.accounts(id) ON DELETE CASCADE,
    vehicle_type VARCHAR(32) NOT NULL CHECK (vehicle_type IN ('taxi', 'moto', 'premium', 'tuk_tuk', 'ev', 'accessible', 'other')),
    license_plate VARCHAR(32) NOT NULL UNIQUE,
    verification_status VARCHAR(24) NOT NULL DEFAULT 'approved' CHECK (verification_status IN ('pending', 'approved', 'rejected', 'suspended')),
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    is_available BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS taxi.trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id UUID NOT NULL REFERENCES taxi.accounts(id),
    driver_id UUID REFERENCES taxi.drivers(id),
    status VARCHAR(24) NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'matching', 'accepted', 'en_route', 'arrived', 'picked_up', 'completed', 'cancelled')),
    revision BIGINT NOT NULL DEFAULT 0,
    vehicle_type VARCHAR(32) NOT NULL CHECK (vehicle_type IN ('taxi', 'moto', 'premium', 'tuk_tuk', 'ev', 'accessible', 'other')),
    fare_amount NUMERIC(19,4),
    currency CHAR(3) NOT NULL DEFAULT 'RWF',
    surge_multiplier NUMERIC(8,4) NOT NULL DEFAULT 1,
    payment_method VARCHAR(16) NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card', 'wallet')),
    pickup_lat NUMERIC(10,7) NOT NULL,
    pickup_lng NUMERIC(10,7) NOT NULL,
    dropoff_lat NUMERIC(10,7) NOT NULL,
    dropoff_lng NUMERIC(10,7) NOT NULL,
    cancellation_actor VARCHAR(16) CHECK (cancellation_actor IS NULL OR cancellation_actor IN ('rider', 'driver', 'system')),
    cancellation_reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    arrived_at TIMESTAMPTZ,
    picked_up_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_taxi_trips_rider_active
    ON taxi.trips (rider_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_taxi_trips_driver_active
    ON taxi.trips (driver_id, status, updated_at DESC)
    WHERE driver_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_taxi_trips_matching_vehicle
    ON taxi.trips (status, vehicle_type, created_at DESC);
