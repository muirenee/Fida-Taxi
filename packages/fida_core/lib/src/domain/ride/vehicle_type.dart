enum VehicleType {
  standard('standard'),
  comfort('comfort'),
  xl('xl'),
  moto('moto'),
  electric('electric');

  const VehicleType(this.wireValue);

  final String wireValue;

  static VehicleType fromWire(String value) {
    for (final type in VehicleType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }

    throw FormatException(
      'Unknown vehicle type: "$value".',
    );
  }
}
