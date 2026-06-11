import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/shared/utils/currency_utils.dart';

void main() {
  group('CurrencyUtils.formatValues', () {
    test('formats small values without grouping', () {
      expect(CurrencyUtils.formatValues(0.0), '0');
      expect(CurrencyUtils.formatValues(5.0), '5');
      expect(CurrencyUtils.formatValues(99.0), '99');
      expect(CurrencyUtils.formatValues(350.0), '350');
    });

    test('formats thousands and lakhs with Indian grouping', () {
      expect(CurrencyUtils.formatValues(1000.0), '1,000');
      expect(CurrencyUtils.formatValues(12345.0), '12,345');
      expect(CurrencyUtils.formatValues(100000.0), '1,00,000');
      expect(CurrencyUtils.formatValues(123456.0), '1,23,456');
      expect(CurrencyUtils.formatValues(1234567.0), '12,34,567');
      expect(CurrencyUtils.formatValues(12345678.0), '1,23,45,678');
    });

    test('handles negative values correctly', () {
      expect(CurrencyUtils.formatValues(-500.0), '-500');
      expect(CurrencyUtils.formatValues(-123456.0), '-1,23,456');
    });

    test('respects showDecimals and handles existing decimals', () {
      expect(CurrencyUtils.formatValues(1234.56, showDecimals: true), '1,234.56');
      expect(CurrencyUtils.formatValues(1234.0, showDecimals: true), '1,234.00');
      expect(CurrencyUtils.formatValues(1234.5, showDecimals: false), '1,234.50'); // has decimal, shows it
      expect(CurrencyUtils.formatValues(1234.0, showDecimals: false), '1,234'); // no decimal, hides it
    });
  });

  group('CurrencyUtils.formatRupees', () {
    test('prefixes ₹ symbol correctly', () {
      expect(CurrencyUtils.formatRupees(123456.0), '₹1,23,456');
      expect(CurrencyUtils.formatRupees(0.0), '₹0');
    });

    test('positions negative sign before ₹ symbol', () {
      expect(CurrencyUtils.formatRupees(-123456.0), '-₹1,23,456');
    });
  });
}
