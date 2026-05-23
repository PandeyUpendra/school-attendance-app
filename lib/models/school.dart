import 'package:cloud_firestore/cloud_firestore.dart';

class School {
  final String id;
  final String name;
  final String address;
  final String contactNumber;
  final String email;
  final String logoUrl;
  final DateTime createdAt;
  final String subscriptionPlan;
  final bool isActive;

  /// PDF / report branding label. Stored at schools/{sid}.brandName.
  /// Each school sets this independently in the admin panel.
  /// Falls back to [name] when empty, so PDFs are always labelled.
  /// NEVER hardcode an institution name here — read from Firestore.
  final String brandName;

  School({
    required this.id,
    required this.name,
    required this.address,
    required this.contactNumber,
    required this.email,
    this.logoUrl = '',
    required this.createdAt,
    this.subscriptionPlan = 'free',
    this.isActive = true,
    this.brandName = '',
  });

  /// Effective branding: [brandName] if set, otherwise [name].
  String get effectiveBrandName =>
      brandName.trim().isNotEmpty ? brandName.trim() : name.trim();

  factory School.fromJson(Map<String, dynamic> json, String id) {
    return School(
      id: id,
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      contactNumber: json['contactNumber'] ?? '',
      email: json['email'] ?? '',
      logoUrl: json['logoUrl'] ?? '',
      createdAt:
          (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      subscriptionPlan: json['subscriptionPlan'] ?? 'free',
      isActive: json['isActive'] ?? true,
      brandName: (json['brandName'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'contactNumber': contactNumber,
      'email': email,
      'logoUrl': logoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'subscriptionPlan': subscriptionPlan,
      'isActive': isActive,
      'brandName': brandName,
    };
  }
}
