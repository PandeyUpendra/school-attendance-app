abstract class CurrencyUtils {
  CurrencyUtils._();

  /// Formats a number in Indian grouping format (e.g., 1,23,456.00 or 1,23,456).
  /// Grouping is 3 digits for the least significant portion, then groups of 2 digits.
  static String formatValues(double value, {bool showDecimals = false}) {
    final hasDecimal = value != value.truncateToDouble();
    final parts = value.toStringAsFixed(showDecimals || hasDecimal ? 2 : 0).split('.');
    var integerPart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    final isNegative = integerPart.startsWith('-');
    if (isNegative) {
      integerPart = integerPart.substring(1);
    }

    if (integerPart.length <= 3) {
      return (isNegative ? '-' : '') + integerPart + decimalPart;
    }

    final lastThree = integerPart.substring(integerPart.length - 3);
    var otherParts = integerPart.substring(0, integerPart.length - 3);

    final List<String> grouped = [];
    while (otherParts.length > 2) {
      grouped.insert(0, otherParts.substring(otherParts.length - 2));
      otherParts = otherParts.substring(0, otherParts.length - 2);
    }
    if (otherParts.isNotEmpty) {
      grouped.insert(0, otherParts);
    }

    final formattedInt = '${grouped.join(',')},$lastThree';
    return (isNegative ? '-' : '') + formattedInt + decimalPart;
  }

  /// Formats a number as rupees with the ₹ symbol (e.g., ₹1,23,456).
  static String formatRupees(double value, {bool showDecimals = false}) {
    final formatted = formatValues(value, showDecimals: showDecimals);
    if (formatted.startsWith('-')) {
      return '-₹${formatted.substring(1)}';
    }
    return '₹$formatted';
  }
}
