import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { AuthenticatedRequest, JwtAuthGuard } from './auth.guard';
import { RegisterDriverDto, RegisterRiderDto, RequestOtpDto, VerifyOtpDto } from './auth.dto';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('phone/request')
  request(@Body() dto: RequestOtpDto) {
    return this.auth.requestPhoneLogin(dto.phone);
  }

  @Post('phone/verify')
  verify(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyPhoneLogin(dto.challenge_id, dto.code);
  }

  @Post('register/rider')
  registerRider(@Body() dto: RegisterRiderDto) {
    return this.auth.registerRider(dto);
  }

  @Post('register/driver')
  registerDriver(@Body() dto: RegisterDriverDto) {
    return this.auth.registerDriver(dto);
  }

  @Post('telemetry-session')
  @UseGuards(JwtAuthGuard)
  telemetrySession(@Req() request: AuthenticatedRequest) {
    return this.auth.createTelemetrySession(
      request.user.user_id,
      request.user.driver_id,
    );
  }
}
