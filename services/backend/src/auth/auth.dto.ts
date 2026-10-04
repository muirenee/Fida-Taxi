import { IsEmail, IsIn, IsOptional, IsPhoneNumber, IsString, Length, MaxLength } from 'class-validator';

export class RequestOtpDto {
  @IsPhoneNumber()
  phone!: string;
}

export class VerifyOtpDto {
  @IsString()
  @Length(8, 128)
  challenge_id!: string;

  @IsString()
  @Length(4, 8)
  code!: string;
}

export class RegisterRiderDto {
  @IsString()
  @MaxLength(80)
  first_name!: string;

  @IsString()
  @MaxLength(80)
  last_name!: string;

  @IsPhoneNumber()
  phone!: string;

  @IsOptional()
  @IsEmail()
  email?: string;
}

export class RegisterDriverDto extends RegisterRiderDto {
  @IsIn(['taxi', 'moto', 'premium', 'tuk_tuk', 'ev', 'accessible', 'other'])
  vehicle_type!: string;

  @IsString()
  @MaxLength(32)
  license_plate!: string;
}
