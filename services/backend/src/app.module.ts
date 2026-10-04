import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthController } from './auth/auth.controller';
import { AuthService } from './auth/auth.service';
import { DatabaseService } from './database.service';
import { HealthController } from './health.controller';
import { RedisService } from './redis.service';
import { RidesController } from './rides/rides.controller';
import { RidesService } from './rides/rides.service';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  controllers: [HealthController, AuthController, RidesController],
  providers: [DatabaseService, RedisService, AuthService, RidesService],
})
export class AppModule {}
