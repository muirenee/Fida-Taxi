final class Money implements Comparable<Money> {
  Money({required this.minorUnits, required String currency})
    : currency = _normalizeCurrency(currency);

  final int minorUnits;
  final String currency;

  factory Money.zero(String currency) {
    return Money(minorUnits: 0, currency: currency);
  }

  static String _normalizeCurrency(String value) {
    final normalized = value.trim().toUpperCase();

    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'currency',
        'Currency must be a three-letter code.',
      );
    }

    return normalized;
  }

  bool get isNegative => minorUnits < 0;
  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) {
    _ensureSameCurrency(other);

    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _ensureSameCurrency(other);

    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  Money multiplyBy(int multiplier) {
    return Money(minorUnits: minorUnits * multiplier, currency: currency);
  }

  void _ensureSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot operate on $currency and ${other.currency}.');
    }
  }

  @override
  int compareTo(Money other) {
    _ensureSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'minor_units': minorUnits, 'currency': currency};
  }

  factory Money.fromJson(Map<String, dynamic> json) {
    final minorUnitsValue = json['minor_units'];
    final currencyValue = json['currency'];

    if (minorUnitsValue is! num) {
      throw const FormatException('Money.minor_units must be numeric.');
    }

    if (currencyValue is! String) {
      throw const FormatException('Money.currency must be a string.');
    }

    return Money(minorUnits: minorUnitsValue.toInt(), currency: currencyValue);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Money &&
            other.minorUnits == minorUnits &&
            other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() {
    return 'Money(minorUnits: $minorUnits, currency: $currency)';
  }
}
