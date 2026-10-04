import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthController } from './auth/auth.controller';
import { AuthService } from './auth/auth.service';
import { DatabaseService } from './database.service';
import { HealthController } from './health.controller';
import { MapsController } from './maps/maps.controller';
import { MapsService } from './maps/maps.service';
import { RedisService } from './redis.service';
import { RidesController } from './rides/rides.controller';
import { RidesService } from './rides/rides.service';
import { TrackingService } from './rides/tracking.service';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  controllers: [
    HealthController,
    AuthController,
    RidesController,
    MapsController,
  ],
  providers: [
    DatabaseService,
    RedisService,
    AuthService,
    RidesService,
    TrackingService,
    MapsService,
  ],
})
export class AppModule {}
