class SchoolContact {
  final String id;
  final String name;
  final String phoneNumber;
  final String role;
  final bool isKey;

  const SchoolContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.role,
    this.isKey = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'role': role,
        'isKey': isKey,
      };

  factory SchoolContact.fromJson(Map<String, dynamic> json) => SchoolContact(
        id: json['id'] as String,
        name: json['name'] as String,
        phoneNumber: json['phoneNumber'] as String,
        role: json['role'] as String,
        isKey: json['isKey'] ?? false,
      );

  SchoolContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? role,
    bool? isKey,
  }) =>
      SchoolContact(
        id: id ?? this.id,
        name: name ?? this.name,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        role: role ?? this.role,
        isKey: isKey ?? this.isKey,
      );
}
