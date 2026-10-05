import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/auth.guard';
import {
  PlaceSearchDto,
  ReverseGeocodeDto,
  RoutePreviewDto,
} from './maps.dto';
import { MapsService } from './maps.service';

@Controller('maps')
@UseGuards(JwtAuthGuard)
export class MapsController {
  constructor(private readonly maps: MapsService) {}

  @Get('search')
  search(@Query() dto: PlaceSearchDto) {
    return this.maps.search(dto);
  }

  @Get('reverse')
  reverse(@Query() dto: ReverseGeocodeDto) {
    return this.maps.reverse(dto);
  }

  @Get('route')
  route(@Query() dto: RoutePreviewDto) {
    return this.maps.route(dto);
  }
}
