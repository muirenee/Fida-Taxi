import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedRequest, JwtAuthGuard } from '../auth/auth.guard';
import {
  CancelRideDto,
  DriverAvailabilityDto,
  DriverLocationDto,
  DriverTripActionDto,
  RequestRideDto,
} from './rides.dto';
import { RidesService } from './rides.service';
import { TrackingService } from './tracking.service';

@Controller('rides')
@UseGuards(JwtAuthGuard)
export class RidesController {
  constructor(
    private readonly rides: RidesService,
    private readonly tracking: TrackingService,
  ) {}

  @Post('request')
  request(@Req() request: AuthenticatedRequest, @Body() dto: RequestRideDto) {
    return this.rides.requestRide(dto, request.user);
  }

  @Get('rider/active')
  activeRider(@Req() request: AuthenticatedRequest) {
    return this.rides.getActiveRiderTrip(request.user);
  }

  @Get('driver/active')
  activeDriver(@Req() request: AuthenticatedRequest) {
    return this.rides.getActiveDriverTrip(request.user);
  }

  @Get('driver/offers')
  driverOffers(@Req() request: AuthenticatedRequest) {
    return this.rides.listDriverOffers(request.user);
  }

  @Post('driver/availability')
  @HttpCode(HttpStatus.OK)
  availability(
    @Req() request: AuthenticatedRequest,
    @Body() dto: DriverAvailabilityDto,
  ) {
    return this.rides.setDriverAvailability(request.user, dto);
  }

  @Post('driver/location')
  @HttpCode(HttpStatus.OK)
  driverLocation(
    @Req() request: AuthenticatedRequest,
    @Body() dto: DriverLocationDto,
  ) {
    return this.tracking.updateDriverLocation(request.user, dto);
  }

  @Get(':tripId/driver-location')
  driverLocationForTrip(
    @Req() request: AuthenticatedRequest,
    @Param('tripId', new ParseUUIDPipe()) tripId: string,
  ) {
    return this.tracking.getDriverLocation(tripId, request.user);
  }

  @Get(':tripId')
  getTrip(
    @Req() request: AuthenticatedRequest,
    @Param('tripId', new ParseUUIDPipe()) tripId: string,
  ) {
    return this.rides.getTrip(tripId, request.user);
  }

  @Post(':tripId/accept')
  @HttpCode(HttpStatus.OK)
  accept(
    @Req() request: AuthenticatedRequest,
    @Param('tripId', new ParseUUIDPipe()) tripId: string,
  ) {
    return this.rides.acceptTrip(tripId, request.user);
  }

  @Post(':tripId/action')
  @HttpCode(HttpStatus.OK)
  action(
    @Req() request: AuthenticatedRequest,
    @Param('tripId', new ParseUUIDPipe()) tripId: string,
    @Body() dto: DriverTripActionDto,
  ) {
    return this.rides.driverAction(tripId, dto.action, request.user);
  }

  @Post(':tripId/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(
    @Req() request: AuthenticatedRequest,
    @Param('tripId', new ParseUUIDPipe()) tripId: string,
    @Body() dto: CancelRideDto,
  ) {
    return this.rides.cancelTrip(tripId, dto.reason, request.user);
  }
}
