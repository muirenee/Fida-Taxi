import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import * as jwt from 'jsonwebtoken';
import { DatabaseService } from '../database.service';
import { RedisService } from '../redis.service';
import { RegisterDriverDto, RegisterRiderDto } from './auth.dto';
import { AuthRole } from './auth.types';

interface AccountRow {
  id: string;
  phone: string;
  role: AuthRole;
  status: string;
}

interface DriverRow {
  id: string;
  user_id: string;
  verification_status: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
  ) {}

  async requestPhoneLogin(phone: string) {
    const challengeId = randomUUID();
    const code = String(randomInt(100000, 1000000));
    const ttl = Number(process.env.OTP_TTL_SECONDS ?? 300);
    const digest = this.otpDigest(challengeId, code);

    await this.redis.setEx(
      `auth:otp:${challengeId}`,
      ttl,
      JSON.stringify({ phone, digest, attempts: 0 }),
    );

    return {
      accepted: true,
      challenge_id: challengeId,
      expires_in_seconds: ttl,
      ...(process.env.OTP_DEV_ECHO === 'true' ? { dev_code: code } : {}),
    };
  }

  async verifyPhoneLogin(challengeId: string, code: string) {
    const key = `auth:otp:${challengeId}`;
    const raw = await this.redis.get(key);
    if (!raw) throw new UnauthorizedException('OTP challenge expired or invalid');

    const state = JSON.parse(raw) as { phone: string; digest: string; attempts: number };
    const expected = Buffer.from(state.digest, 'hex');
    const actual = Buffer.from(this.otpDigest(challengeId, code), 'hex');
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      throw new UnauthorizedException('Invalid verification code');
    }

    await this.redis.del(key);

    const result = await this.db.query<AccountRow>(
      `SELECT id, phone, role, status FROM taxi.accounts WHERE phone = $1 LIMIT 1`,
      [state.phone],
    );
    const account = result.rows[0];
    if (!account) {
      throw new NotFoundException('Account not registered for this phone number');
    }
    if (account.status !== 'active') {
      throw new UnauthorizedException('Account is not active');
    }

    let driverId: string | undefined;
    if (account.role === 'driver') {
      const driver = await this.db.query<DriverRow>(
        `SELECT id, user_id, verification_status FROM taxi.drivers WHERE user_id = $1 LIMIT 1`,
        [account.id],
      );
      driverId = driver.rows[0]?.id;
      if (!driverId) throw new UnauthorizedException('Driver profile not found');
    }

    const ttl = Number(process.env.JWT_ACCESS_TTL_SECONDS ?? 900);
    const token = jwt.sign(
      { role: account.role, ...(driverId ? { driver_id: driverId } : {}) },
      this.jwtSecret(),
      { algorithm: 'HS256', subject: account.id, expiresIn: ttl },
    );

    return {
      access_token: token,
      token_type: 'Bearer',
      expires_in_seconds: ttl,
      user_id: account.id,
      driver_id: driverId ?? null,
      role: account.role,
    };
  }

  async registerRider(dto: RegisterRiderDto) {
    try {
      const result = await this.db.query<{
        id: string;
        first_name: string;
        last_name: string;
        phone: string;
        email: string | null;
        status: string;
      }>(
        `INSERT INTO taxi.accounts (first_name, last_name, phone, email, role, status)
         VALUES ($1, $2, $3, $4, 'rider', 'active')
         RETURNING id, first_name, last_name, phone, email, status`,
        [dto.first_name.trim(), dto.last_name.trim(), dto.phone, dto.email ?? null],
      );
      return result.rows[0];
    } catch (error) {
      if ((error as { code?: string }).code === '23505') {
        throw new ConflictException('Phone number is already registered');
      }
      throw error;
    }
  }

  async registerDriver(dto: RegisterDriverDto) {
    return this.db.transaction(async (client) => {
      try {
        const accountResult = await client.query<{ id: string; phone: string }>(
          `INSERT INTO taxi.accounts (first_name, last_name, phone, email, role, status)
           VALUES ($1, $2, $3, $4, 'driver', 'active')
           RETURNING id, phone`,
          [dto.first_name.trim(), dto.last_name.trim(), dto.phone, dto.email ?? null],
        );
        const account = accountResult.rows[0];
        const driverResult = await client.query<{
          id: string;
          vehicle_type: string;
          license_plate: string;
          verification_status: string;
        }>(
          `INSERT INTO taxi.drivers (user_id, vehicle_type, license_plate, verification_status)
           VALUES ($1, $2, $3, 'approved')
           RETURNING id, vehicle_type, license_plate, verification_status`,
          [account.id, dto.vehicle_type, dto.license_plate.trim()],
        );
        const driver = driverResult.rows[0];
        return {
          user_id: account.id,
          driver_id: driver.id,
          phone: account.phone,
          vehicle_type: driver.vehicle_type,
          license_plate: driver.license_plate,
          verification_status: driver.verification_status,
        };
      } catch (error) {
        if ((error as { code?: string }).code === '23505') {
          throw new ConflictException('Phone number or license plate is already registered');
        }
        throw error;
      }
    });
  }

  async createTelemetrySession(userId: string, driverId?: string) {
    if (!driverId) throw new UnauthorizedException('Driver access token required');
    const sessionId = randomUUID();
    const sessionKey = randomUUID().replaceAll('-', '') + randomUUID().replaceAll('-', '');
    const ttl = 900;
    await this.redis.setEx(
      `telemetry:session:${sessionId}`,
      ttl,
      JSON.stringify({ user_id: userId, driver_id: driverId, session_key: sessionKey }),
    );
    return {
      session_id: sessionId,
      session_key: sessionKey,
      expires_at: new Date(Date.now() + ttl * 1000).toISOString(),
    };
  }

  private otpDigest(challengeId: string, code: string): string {
    const secret = process.env.OTP_HMAC_SECRET;
    if (!secret) throw new Error('OTP_HMAC_SECRET is required');
    return createHmac('sha256', secret).update(`${challengeId}:${code}`).digest('hex');
  }

  private jwtSecret(): string {
    const secret = process.env.JWT_HS256_SECRET;
    if (!secret) throw new Error('JWT_HS256_SECRET is required');
    return secret;
  }
}
