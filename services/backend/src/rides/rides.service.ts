import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database.service';
import { RedisService } from '../redis.service';
import { AuthPrincipal } from '../auth/auth.types';
import { DriverAvailabilityDto, RequestRideDto } from './rides.dto';

interface TripRow {
  id: string;
  rider_id: string;
  driver_id: string | null;
  status: string;
  revision: number;
  vehicle_type: string;
  fare_amount: string | null;
  currency: string;
  surge_multiplier: string;
  payment_method: string;
  pickup_lat: string;
  pickup_lng: string;
  dropoff_lat: string;
  dropoff_lng: string;
  cancellation_actor: string | null;
  cancellation_reason: string | null;
  created_at: Date;
  updated_at: Date;
  accepted_at: Date | null;
  arrived_at: Date | null;
  picked_up_at: Date | null;
  completed_at: Date | null;
  cancelled_at: Date | null;
}

interface DriverRow {
  id: string;
  user_id: string;
  vehicle_type: string;
  verification_status: string;
  is_online: boolean;
  is_available: boolean;
}

const ACTIVE_STATUSES = ['created', 'matching', 'accepted', 'en_route', 'arrived', 'picked_up'];
const DRIVER_ACTIVE_STATUSES = ['accepted', 'en_route', 'arrived', 'picked_up'];
const CANCELLABLE = ['created', 'matching', 'accepted', 'en_route', 'arrived'];

@Injectable()
export class RidesService {
  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
  ) {}

  async requestRide(dto: RequestRideDto, principal: AuthPrincipal) {
    if (principal.role !== 'rider' || principal.user_id !== dto.rider_id) {
      throw new ForbiddenException('rider_id must match the authenticated rider');
    }

    const existing = await this.db.query<TripRow>(
      `SELECT * FROM taxi.trips
       WHERE rider_id = $1 AND status = ANY($2::text[])
       ORDER BY created_at DESC LIMIT 1`,
      [principal.user_id, ACTIVE_STATUSES],
    );
    if (existing.rows[0]) throw new ConflictException('Rider already has an active trip');

    const distanceMeters = this.distanceMeters(
      dto.pickup_lat,
      dto.pickup_lng,
      dto.dropoff_lat,
      dto.dropoff_lng,
    );
    const baseFare = Number(process.env.RIDE_BASE_FARE_RWF ?? 1000);
    const perKm = Number(process.env.RIDE_PER_KM_RWF ?? 500);
    const fare = Math.round(baseFare + (distanceMeters / 1000) * perKm);

    const inserted = await this.db.query<TripRow>(
      `INSERT INTO taxi.trips (
         rider_id, status, vehicle_type, fare_amount, currency,
         surge_multiplier, payment_method,
         pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
       ) VALUES ($1, 'matching', $2, $3, 'RWF', 1, $4, $5, $6, $7, $8)
       RETURNING *`,
      [
        principal.user_id,
        dto.vehicle_type,
        fare,
        dto.payment_method ?? 'cash',
        dto.pickup_lat,
        dto.pickup_lng,
        dto.dropoff_lat,
        dto.dropoff_lng,
      ],
    );
    const trip = inserted.rows[0];

    const radiusKm = Number(process.env.DISPATCH_RADIUS_KM ?? 5);
    const candidateIds = await this.redis.nearbyDriverIds(
      dto.pickup_lng,
      dto.pickup_lat,
      radiusKm,
      100,
    );

    let eligible: string[] = [];
    if (candidateIds.length > 0) {
      const drivers = await this.db.query<DriverRow>(
        `SELECT id, user_id, vehicle_type, verification_status, is_online, is_available
         FROM taxi.drivers
         WHERE id = ANY($1::uuid[])
           AND vehicle_type = $2
           AND verification_status = 'approved'
           AND is_online = true
           AND is_available = true`,
        [candidateIds, dto.vehicle_type],
      );
      eligible = drivers.rows.map((driver) => driver.id);
    }

    const offerTtl = Number(process.env.BIDDING_TTL_SECONDS ?? 120);
    await Promise.all(
      eligible.map((driverId) =>
        this.redis.setEx(`ride:offer:${trip.id}:${driverId}`, offerTtl, '1'),
      ),
    );

    return {
      trip_id: trip.id,
      status: trip.status,
      lifecycle_status: this.lifecycleStatus(trip),
      revision: Number(trip.revision),
      vehicle_type: trip.vehicle_type,
      payment_method: trip.payment_method,
      estimated_distance_meters: Math.round(distanceMeters),
      estimated_fare: trip.fare_amount,
      currency: trip.currency,
      surge_multiplier: trip.surge_multiplier,
      bidding: {
        state: 'broadcasted',
        expires_in_seconds: offerTtl,
      },
      dispatch: {
        radius_km: radiusKm,
        candidate_count: eligible.length,
        deferred: false,
      },
    };
  }

  async getTrip(tripId: string, principal: AuthPrincipal) {
    const trip = await this.requireTrip(tripId);
    await this.assertVisible(trip, principal);
    return this.snapshot(trip);
  }

  async getActiveRiderTrip(principal: AuthPrincipal) {
    if (principal.role !== 'rider') throw new ForbiddenException('Rider token required');
    const result = await this.db.query<TripRow>(
      `SELECT * FROM taxi.trips
       WHERE rider_id = $1 AND status = ANY($2::text[])
       ORDER BY updated_at DESC LIMIT 1`,
      [principal.user_id, ACTIVE_STATUSES],
    );
    return { trip: result.rows[0] ? this.snapshot(result.rows[0]) : null };
  }

  async getActiveDriverTrip(principal: AuthPrincipal) {
    const driver = await this.requireDriver(principal);
    const result = await this.db.query<TripRow>(
      `SELECT * FROM taxi.trips
       WHERE driver_id = $1 AND status = ANY($2::text[])
       ORDER BY updated_at DESC LIMIT 1`,
      [driver.id, DRIVER_ACTIVE_STATUSES],
    );
    return { trip: result.rows[0] ? this.snapshot(result.rows[0]) : null };
  }

  async setDriverAvailability(principal: AuthPrincipal, dto: DriverAvailabilityDto) {
    const driver = await this.requireDriver(principal);
    if (driver.verification_status !== 'approved') {
      throw new ForbiddenException('Driver is not approved');
    }

    if (!dto.is_available) {
      await this.db.query(
        `UPDATE taxi.drivers SET is_online = false, is_available = false, updated_at = NOW() WHERE id = $1`,
        [driver.id],
      );
      await this.redis.geoRemove('drivers:locations', driver.id);
      return {
        driver_id: driver.id,
        is_online: false,
        is_available: false,
        presence_ttl_seconds: 0,
      };
    }

    if (dto.latitude == null || dto.longitude == null) {
      throw new ConflictException('Latitude and longitude are required');
    }

    const active = await this.db.query<TripRow>(
      `SELECT id FROM taxi.trips WHERE driver_id = $1 AND status = ANY($2::text[]) LIMIT 1`,
      [driver.id, DRIVER_ACTIVE_STATUSES],
    );
    if (active.rows[0]) throw new ConflictException('Driver already has an active trip');

    await this.db.query(
      `UPDATE taxi.drivers SET is_online = true, is_available = true, updated_at = NOW() WHERE id = $1`,
      [driver.id],
    );
    await this.redis.geoAdd(
      'drivers:locations',
      driver.id,
      dto.longitude,
      dto.latitude,
    );
    await this.redis.setEx(`driver:presence:${driver.id}`, 30, 'available');

    return {
      driver_id: driver.id,
      is_online: true,
      is_available: true,
      latitude: dto.latitude,
      longitude: dto.longitude,
      presence_ttl_seconds: 30,
    };
  }

  async listDriverOffers(principal: AuthPrincipal) {
    const driver = await this.requireDriver(principal);
    if (!driver.is_online || !driver.is_available) {
      return { offers: [], generated_at: new Date().toISOString() };
    }

    const result = await this.db.query<TripRow>(
      `SELECT * FROM taxi.trips
       WHERE status = 'matching' AND vehicle_type = $1
       ORDER BY created_at DESC LIMIT 30`,
      [driver.vehicle_type],
    );

    const offers: TripRow[] = [];
    for (const trip of result.rows) {
      if (await this.redis.get(`ride:offer:${trip.id}:${driver.id}`)) {
        offers.push(trip);
      }
    }

    return {
      offers: offers.map((trip) => this.snapshot(trip)),
      generated_at: new Date().toISOString(),
    };
  }

  async acceptTrip(tripId: string, principal: AuthPrincipal) {
    const driver = await this.requireDriver(principal);
    if (!driver.is_online || !driver.is_available) {
      throw new ConflictException('Driver must be online and available');
    }
    const offer = await this.redis.get(`ride:offer:${tripId}:${driver.id}`);
    if (!offer) throw new ForbiddenException('Driver was not offered this trip');

    const lockKey = `ride:accept:${tripId}`;
    const lockToken = randomUUID();
    if (!(await this.redis.acquireLock(lockKey, lockToken, 10000))) {
      throw new ConflictException('Trip acceptance is already in progress');
    }

    try {
      return await this.db.transaction(async (client) => {
        const active = await client.query(
          `SELECT id FROM taxi.trips WHERE driver_id = $1 AND status = ANY($2::text[]) LIMIT 1`,
          [driver.id, DRIVER_ACTIVE_STATUSES],
        );
        if (active.rows[0]) throw new ConflictException('Driver already has an active trip');

        const updated = await client.query<TripRow>(
          `UPDATE taxi.trips
           SET driver_id = $2, status = 'accepted', accepted_at = NOW(),
               revision = revision + 1, updated_at = NOW()
           WHERE id = $1 AND status = 'matching' AND driver_id IS NULL
           RETURNING *`,
          [tripId, driver.id],
        );
        const trip = updated.rows[0];
        if (!trip) throw new ConflictException('Trip is no longer available');

        await client.query(
          `UPDATE taxi.drivers SET is_available = false, updated_at = NOW() WHERE id = $1`,
          [driver.id],
        );
        await this.redis.del(`ride:offer:${tripId}:${driver.id}`);
        return this.snapshot(trip);
      });
    } finally {
      await this.redis.releaseLock(lockKey, lockToken);
    }
  }

  async driverAction(
    tripId: string,
    action: 'en_route' | 'arrive' | 'start' | 'complete',
    principal: AuthPrincipal,
  ) {
    const driver = await this.requireDriver(principal);
    const transition = {
      en_route: { from: 'accepted', to: 'en_route', stamp: null },
      arrive: { from: 'en_route', to: 'arrived', stamp: 'arrived_at' },
      start: { from: 'arrived', to: 'picked_up', stamp: 'picked_up_at' },
      complete: { from: 'picked_up', to: 'completed', stamp: 'completed_at' },
    }[action];

    const stampSql = transition.stamp ? `, ${transition.stamp} = NOW()` : '';
    const updated = await this.db.query<TripRow>(
      `UPDATE taxi.trips
       SET status = $3, revision = revision + 1, updated_at = NOW()${stampSql}
       WHERE id = $1 AND driver_id = $2 AND status = $4
       RETURNING *`,
      [tripId, driver.id, transition.to, transition.from],
    );
    const trip = updated.rows[0];
    if (!trip) throw new ConflictException('Trip state changed or action is invalid');

    if (transition.to === 'completed') {
      await this.db.query(
        `UPDATE taxi.drivers SET is_available = false, updated_at = NOW() WHERE id = $1`,
        [driver.id],
      );
    }
    return this.snapshot(trip);
  }

  async cancelTrip(tripId: string, reason: string | undefined, principal: AuthPrincipal) {
    const trip = await this.requireTrip(tripId);
    if (!CANCELLABLE.includes(trip.status)) {
      throw new ConflictException('Trip can no longer be cancelled');
    }

    let actor: 'rider' | 'driver';
    if (principal.role === 'rider') {
      if (trip.rider_id !== principal.user_id) throw new ForbiddenException();
      actor = 'rider';
    } else {
      const driver = await this.requireDriver(principal);
      if (trip.driver_id !== driver.id) throw new ForbiddenException();
      actor = 'driver';
    }

    const updated = await this.db.query<TripRow>(
      `UPDATE taxi.trips
       SET status = 'cancelled', cancellation_actor = $3,
           cancellation_reason = $4, cancelled_at = NOW(),
           revision = revision + 1, updated_at = NOW()
       WHERE id = $1 AND status = $2
       RETURNING *`,
      [tripId, trip.status, actor, reason?.trim() || null],
    );
    const cancelled = updated.rows[0];
    if (!cancelled) throw new ConflictException('Trip state changed before cancellation');

    if (trip.driver_id) {
      await this.db.query(
        `UPDATE taxi.drivers SET is_available = false, updated_at = NOW() WHERE id = $1`,
        [trip.driver_id],
      );
    }
    return this.snapshot(cancelled);
  }

  private async requireTrip(id: string): Promise<TripRow> {
    const result = await this.db.query<TripRow>(`SELECT * FROM taxi.trips WHERE id = $1 LIMIT 1`, [id]);
    const trip = result.rows[0];
    if (!trip) throw new NotFoundException('Trip not found');
    return trip;
  }

  private async requireDriver(principal: AuthPrincipal): Promise<DriverRow> {
    if (principal.role !== 'driver' || !principal.driver_id) {
      throw new ForbiddenException('Driver token required');
    }
    const result = await this.db.query<DriverRow>(
      `SELECT id, user_id, vehicle_type, verification_status, is_online, is_available
       FROM taxi.drivers WHERE id = $1 AND user_id = $2 LIMIT 1`,
      [principal.driver_id, principal.user_id],
    );
    const driver = result.rows[0];
    if (!driver) throw new ForbiddenException('Driver profile not found');
    return driver;
  }

  private async assertVisible(trip: TripRow, principal: AuthPrincipal): Promise<void> {
    if (principal.role === 'rider' && trip.rider_id === principal.user_id) return;
    if (principal.role === 'driver' && principal.driver_id === trip.driver_id) return;
    throw new ForbiddenException('Trip is not visible to this account');
  }

  private snapshot(trip: TripRow) {
    return {
      trip_id: trip.id,
      rider_id: trip.rider_id,
      driver_id: trip.driver_id,
      status: trip.status,
      lifecycle_status: this.lifecycleStatus(trip),
      revision: Number(trip.revision),
      vehicle_type: trip.vehicle_type,
      fare_amount: trip.fare_amount,
      currency: trip.currency,
      surge_multiplier: trip.surge_multiplier,
      payment_method: trip.payment_method,
      pickup: {
        lat: Number(trip.pickup_lat),
        lng: Number(trip.pickup_lng),
      },
      dropoff: {
        lat: Number(trip.dropoff_lat),
        lng: Number(trip.dropoff_lng),
      },
      cancellation_actor: trip.cancellation_actor,
      cancellation_reason: trip.cancellation_reason,
      created_at: trip.created_at.toISOString(),
      updated_at: trip.updated_at.toISOString(),
      accepted_at: trip.accepted_at?.toISOString() ?? null,
      arrived_at: trip.arrived_at?.toISOString() ?? null,
      picked_up_at: trip.picked_up_at?.toISOString() ?? null,
      completed_at: trip.completed_at?.toISOString() ?? null,
      cancelled_at: trip.cancelled_at?.toISOString() ?? null,
    };
  }

  private lifecycleStatus(trip: TripRow): string | null {
    if (trip.status === 'cancelled') {
      if (trip.cancellation_actor === 'rider') return 'cancelled_by_rider';
      if (trip.cancellation_actor === 'driver') return 'cancelled_by_driver';
      return null;
    }
    return {
      created: 'quoting',
      matching: 'searching',
      accepted: 'driver_assigned',
      en_route: 'driver_en_route',
      arrived: 'driver_arrived',
      picked_up: 'in_progress',
      completed: 'completed',
    }[trip.status] ?? null;
  }

  private distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = (value: number) => (value * Math.PI) / 180;
    const radius = 6371000;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * radius * Math.asin(Math.sqrt(a));
  }
}
