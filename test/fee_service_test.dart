import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/fee.dart';
import 'package:school_app/services/fee_service.dart';

void main() {
  group('FeeService.maskSensitiveInfo', () {
    test('masks typical 16-digit credit card numbers', () {
      const input = 'Paid using card 1234567812345678';
      final masked = FeeService().maskSensitiveInfo(input);
      expect(masked, 'Paid using card ****-****-****-5678');
    });

    test('masks 13-digit and 19-digit numbers', () {
      // 13-digit card
      expect(
        FeeService().maskSensitiveInfo('Card: 1234567890123'),
        'Card: ****-****-****-0123',
      );
      // 19-digit card
      expect(
        FeeService().maskSensitiveInfo('Card: 1234567890123456789'),
        'Card: ****-****-****-6789',
      );
    });

    test('leaves non-card/short numbers intact', () {
      expect(
        FeeService().maskSensitiveInfo('Amount paid was ₹15000'),
        'Amount paid was ₹15000',
      );
      expect(
        FeeService().maskSensitiveInfo('Receipt RCP-2026-000001'),
        'Receipt RCP-2026-000001',
      );
    });
  });

  group('FeeService.daysOverdue', () {
    final t1 = FeeInstallment(
      name: 'Term 1',
      amount: 1000.0,
      dueDate: DateTime(2026, 4, 1),
    );
    final t2 = FeeInstallment(
      name: 'Term 2',
      amount: 2000.0,
      dueDate: DateTime(2026, 8, 1),
    );

    final structure = FeeStructure(
      className: 'Class 6',
      totalAnnualFee: 3000.0,
      components: [],
      installments: [t1, t2],
    );

    test('returns 0 when structure installments list is empty', () {
      final emptyStructure = FeeStructure(
        className: 'Class 6',
        totalAnnualFee: 3000.0,
        components: [],
        installments: [],
      );
      final days = FeeService.daysOverdue(
        emptyStructure,
        0.0,
        DateTime(2026, 5, 1),
      );
      expect(days, 0);
    });

    test('returns 0 when total paid covers all installments', () {
      final days = FeeService.daysOverdue(
        structure,
        3000.0,
        DateTime(2026, 9, 1),
      );
      expect(days, 0);
    });

    test('returns 0 when total paid covers current due but not subsequent future installments', () {
      // Covers Term 1 (1000) but not Term 2 (2000). Evaluated before Term 2 due date.
      final days = FeeService.daysOverdue(
        structure,
        1500.0,
        DateTime(2026, 6, 1), // after Term 1 (4/1) but before Term 2 (8/1)
      );
      expect(days, 0);
    });

    test('returns correct positive days overdue when payment is short of current due date', () {
      // Total paid: 500 (earliest uncovered is Term 1, due 2026-04-01).
      // Evaluated on 2026-04-11 (10 days overdue).
      final days = FeeService.daysOverdue(
        structure,
        500.0,
        DateTime(2026, 4, 11),
      );
      expect(days, 10);
    });

    test('sorts installments by date to find the earliest uncovered correctly', () {
      // Structure with installments out of chronological order
      final unsortedStructure = FeeStructure(
        className: 'Class 6',
        totalAnnualFee: 3000.0,
        components: [],
        installments: [t2, t1], // t2 is 8/1, t1 is 4/1
      );

      // Paid 500. Uncovered is Term 1 (4/1). Evaluated on 4/11.
      final days = FeeService.daysOverdue(
        unsortedStructure,
        500.0,
        DateTime(2026, 4, 11),
      );
      expect(days, 10);
    });
  });

  group('FeeService.saveFeeStructure Validation', () {
    test('throws ArgumentError when sum of installments does not match total annual fee', () {
      final t1 = FeeInstallment(
        name: 'Term 1',
        amount: 1000.0,
        dueDate: DateTime(2026, 4, 1),
      );
      final t2 = FeeInstallment(
        name: 'Term 2',
        amount: 1500.0, // Total = 2500, but totalAnnualFee is 3000
        dueDate: DateTime(2026, 8, 1),
      );

      final structure = FeeStructure(
        className: 'Class 6',
        totalAnnualFee: 3000.0,
        components: [],
        installments: [t1, t2],
      );

      expect(
        () => FeeService().saveFeeStructure(structure: structure),
        throwsArgumentError,
      );
    });

    test('does not throw ArgumentError when sum of installments matches total annual fee (fails on Firebase init instead)', () async {
      final t1 = FeeInstallment(
        name: 'Term 1',
        amount: 1000.0,
        dueDate: DateTime(2026, 4, 1),
      );
      final t2 = FeeInstallment(
        name: 'Term 2',
        amount: 2000.0, // Total = 3000, matches totalAnnualFee
        dueDate: DateTime(2026, 8, 1),
      );

      final structure = FeeStructure(
        className: 'Class 6',
        totalAnnualFee: 3000.0,
        components: [],
        installments: [t1, t2],
      );

      // It passes the validation check, but then fails because Firebase is not initialized.
      // So it should NOT throw an ArgumentError.
      try {
        await FeeService().saveFeeStructure(structure: structure);
        fail('Should have failed with a Firebase exception since Firebase is not initialized.');
      } catch (e) {
        expect(e, isNot(isA<ArgumentError>()));
      }
    });
  });

  group('FeeService.deletePayment Validation', () {
    test('throws ArgumentError when reason is empty', () {
      expect(
        () => FeeService().deletePayment(
          className: 'Class 6',
          roll: 1,
          paymentId: 'PAY-1',
          reason: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}
