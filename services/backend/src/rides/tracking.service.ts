import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { AuthPrincipal } from '../auth/auth.types';
import { DatabaseService } from '../database.service';
import { RedisService } from '../redis.service';
import { DriverLocationDto } from './rides.dto';

interface DriverRow {
  id: string;
  user_id: string;
  verification_status: string;
}

interface TripVisibilityRow {
  id: string;
  rider_id: string;
  driver_id: string | null;
  status: string;
}

@Injectable()
export class TrackingService {
  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
  ) {}

  async updateDriverLocation(
    principal: AuthPrincipal,
    dto: DriverLocationDto,
  ) {
    const driver = await this.requireDriver(principal);
    if (driver.verification_status !== 'approved') {
      throw new ForbiddenException('Driver is not approved');
    }

    const observedAt = new Date().toISOString();
    await this.redis.geoAdd(
      'drivers:locations',
      driver.id,
      dto.longitude,
      dto.latitude,
    );
    await this.redis.setEx(`driver:presence:${driver.id}`, 30, 'online');
    await this.redis.setEx(
      `driver:location:last:${driver.id}`,
      60,
      JSON.stringify({
        latitude: dto.latitude,
        longitude: dto.longitude,
        observed_at: observedAt,
      }),
    );

    const activeTrip = await this.db.query<{ id: string }>(
      `SELECT id FROM taxi.trips
       WHERE driver_id = $1
         AND status = ANY($2::text[])
       ORDER BY updated_at DESC
       LIMIT 1`,
      [driver.id, ['accepted', 'en_route', 'arrived', 'picked_up']],
    );

    return {
      driver_id: driver.id,
      active_trip_id: activeTrip.rows[0]?.id ?? null,
      latitude: dto.latitude,
      longitude: dto.longitude,
      observed_at: observedAt,
      presence_ttl_seconds: 30,
    };
  }

  async getDriverLocation(tripId: string, principal: AuthPrincipal) {
    const result = await this.db.query<TripVisibilityRow>(
      `SELECT id, rider_id, driver_id, status
       FROM taxi.trips
       WHERE id = $1
       LIMIT 1`,
      [tripId],
    );
    const trip = result.rows[0];
    if (!trip) throw new NotFoundException('Trip not found');

    if (principal.role === 'rider') {
      if (trip.rider_id !== principal.user_id) {
        throw new ForbiddenException('Trip is not visible to this rider');
      }
    } else if (principal.role === 'driver') {
      if (!principal.driver_id || principal.driver_id !== trip.driver_id) {
        throw new ForbiddenException('Trip is not visible to this driver');
      }
    } else {
      throw new ForbiddenException('Unsupported account role');
    }

    if (!trip.driver_id) {
      return {
        driver_id: null,
        location: null,
      };
    }

    const cached = await this.redis.get(`driver:location:last:${trip.driver_id}`);
    if (cached) {
      try {
        const value = JSON.parse(cached) as {
          latitude?: unknown;
          longitude?: unknown;
          observed_at?: unknown;
        };
        const latitude = Number(value.latitude);
        const longitude = Number(value.longitude);
        if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
          return {
            driver_id: trip.driver_id,
            location: {
              latitude,
              longitude,
              observed_at:
                typeof value.observed_at === 'string' ? value.observed_at : null,
            },
          };
        }
      } catch {
        // Fall through to the GEO index when the transient cache is malformed.
      }
    }

    const position = await this.redis.geoPosition(
      'drivers:locations',
      trip.driver_id,
    );
    return {
      driver_id: trip.driver_id,
      location: position
        ? {
            ...position,
            observed_at: null,
          }
        : null,
    };
  }

  private async requireDriver(principal: AuthPrincipal): Promise<DriverRow> {
    if (principal.role !== 'driver' || !principal.driver_id) {
      throw new ForbiddenException('Driver token required');
    }

    const result = await this.db.query<DriverRow>(
      `SELECT id, user_id, verification_status
       FROM taxi.drivers
       WHERE id = $1 AND user_id = $2
       LIMIT 1`,
      [principal.driver_id, principal.user_id],
    );
    const driver = result.rows[0];
    if (!driver) throw new ForbiddenException('Driver profile not found');
    return driver;
  }
}
