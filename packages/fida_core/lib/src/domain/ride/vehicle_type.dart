enum VehicleType {
  taxi('taxi'),
  moto('moto'),
  premium('premium'),
  tukTuk('tuk_tuk'),
  ev('ev'),
  accessible('accessible'),
  other('other');

  const VehicleType(this.wireValue);

  final String wireValue;

  static VehicleType fromWire(String value) {
    for (final type in VehicleType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }

    throw FormatException('Unknown vehicle type: "$value".');
  }
}
