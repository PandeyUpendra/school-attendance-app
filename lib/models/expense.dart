import 'package:cloud_firestore/cloud_firestore.dart';

int _rupeesToPaise(num rupees) => (rupees * 100).round();
double _paiseToRupees(int paise) => paise / 100.0;

int _readPaise(Map<String, dynamic> json, String paiseKey, String rupeeKey) {
  final p = json[paiseKey];
  if (p is int) return p;
  if (p is num) return p.round();
  final r = json[rupeeKey];
  return r is num ? _rupeesToPaise(r) : 0;
}

class Expense {
  final String id;
  final int amountPaise;
  final String category; // e.g., 'Salaries', 'Rent', 'Utilities', 'Maintenance', 'Stationery'
  final String description;
  final DateTime expenseDate;
  final String recordedBy; // Email of the user who logged it
  final String paymentMode; // 'Cash' | 'Bank' | 'UPI' | 'Cheque'
  final DateTime? createdAt;

  double get amount => _paiseToRupees(amountPaise);

  Expense({
    required this.id,
    required double amount,
    required this.category,
    required this.description,
    required this.expenseDate,
    required this.recordedBy,
    required this.paymentMode,
    this.createdAt,
  }) : amountPaise = _rupeesToPaise(amount);

  const Expense._paise({
    required this.id,
    required this.amountPaise,
    required this.category,
    required this.description,
    required this.expenseDate,
    required this.recordedBy,
    required this.paymentMode,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'amountPaise': amountPaise,
        'amount': amount,
        'category': category,
        'description': description,
        'expenseDate': Timestamp.fromDate(expenseDate),
        'recordedBy': recordedBy,
        'paymentMode': paymentMode,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };

  factory Expense.fromDoc(String id, Map<String, dynamic> data) {
    final ed = data['expenseDate'];
    final ca = data['createdAt'];
    return Expense._paise(
      id: id,
      amountPaise: _readPaise(data, 'amountPaise', 'amount'),
      category: (data['category'] as String?) ?? 'General',
      description: (data['description'] as String?) ?? '',
      expenseDate: ed is Timestamp ? ed.toDate() : DateTime.now(),
      recordedBy: (data['recordedBy'] as String?) ?? '',
      paymentMode: (data['paymentMode'] as String?) ?? 'Cash',
      createdAt: ca is Timestamp ? ca.toDate() : null,
    );
  }
}
