class Student {
  final int roll;
  final String name;
  final String? parentPhone;

  Student({
    required this.roll,
    required this.name,
    this.parentPhone,
  });
}
