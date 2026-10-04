import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';

export class RequestRideDto {
  @IsUUID()
  rider_id!: string;

  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-90)
  @Max(90)
  pickup_lat!: number;

  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-180)
  @Max(180)
  pickup_lng!: number;

  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-90)
  @Max(90)
  dropoff_lat!: number;

  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-180)
  @Max(180)
  dropoff_lng!: number;

  @IsIn(['taxi', 'moto', 'premium', 'tuk_tuk', 'ev', 'accessible', 'other'])
  vehicle_type!: string;

  @IsOptional()
  @IsIn(['cash', 'card', 'wallet'])
  payment_method?: string;
}

export class DriverAvailabilityDto {
  @IsBoolean()
  is_available!: boolean;

  @ValidateIf((dto: DriverAvailabilityDto) => dto.is_available)
  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-90)
  @Max(90)
  latitude?: number;

  @ValidateIf((dto: DriverAvailabilityDto) => dto.is_available)
  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-180)
  @Max(180)
  longitude?: number;
}

export class DriverLocationDto {
  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-90)
  @Max(90)
  latitude!: number;

  @Type(() => Number)
  @IsNumber({ allowNaN: false, allowInfinity: false })
  @Min(-180)
  @Max(180)
  longitude!: number;
}

export class DriverTripActionDto {
  @IsIn(['en_route', 'arrive', 'start', 'complete'])
  action!: 'en_route' | 'arrive' | 'start' | 'complete';
}

export class CancelRideDto {
  @IsOptional()
  @IsString()
  @MaxLength(255)
  reason?: string;
}
