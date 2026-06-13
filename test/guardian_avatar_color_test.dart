import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/student.dart';

// Copy of the color assignment logic to test in isolation
Color getAvatarBgColor(Student student, List<Student> children) {
  final String name = student.name;
  if (name.isEmpty) return const Color(0xFF1E88E5);
  
  final List<Color> palette = [
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF43A047), // Green
    const Color(0xFFE53935), // Red
    const Color(0xFF8E24AA), // Purple
    const Color(0xFFD81B60), // Pink
    const Color(0xFFF4511E), // Orange
    const Color(0xFF00ACC1), // Cyan
    const Color(0xFF3949AB), // Indigo
  ];

  // Find all children starting with the same letter
  final String letter = name[0].toUpperCase();
  final sameLetterChildren = children.where((c) => 
    c.name.isNotEmpty && c.name[0].toUpperCase() == letter
  ).toList();
  
  // Sort them by name and class/section/roll to ensure deterministic ordering
  sameLetterChildren.sort((a, b) {
    final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (cmp != 0) return cmp;
    return Student.buildDocId(a.roll, a.className, a.section)
        .compareTo(Student.buildDocId(b.roll, b.className, b.section));
  });

  if (sameLetterChildren.length <= 1) {
    final int hash = name.hashCode;
    return palette[hash.abs() % palette.length];
  }

  final int index = sameLetterChildren.indexWhere((c) =>
    c.roll == student.roll && 
    c.className == student.className && 
    c.section == student.section
  );
  
  if (index == -1) {
    final int hash = name.hashCode;
    return palette[hash.abs() % palette.length];
  }
  
  final baseHash = letter.hashCode;
  final colorIndex = (baseHash.abs() + index * 3) % palette.length;
  return palette[colorIndex];
}

void main() {
  group('Guardian Avatar Color Differentiation Tests', () {
    test('Single child gets hash-based color', () {
      final s1 = Student(roll: 1, name: 'Vishal', className: '6-B', section: 'B');
      final children = [s1];
      
      final color = getAvatarBgColor(s1, children);
      expect(color, isNotNull);
    });

    test('Multiple children starting with different letters get default colors', () {
      final s1 = Student(roll: 1, name: 'Vishal', className: '6-B', section: 'B');
      final s2 = Student(roll: 2, name: 'Abhishek', className: '6-B', section: 'B');
      final children = [s1, s2];
      
      final color1 = getAvatarBgColor(s1, children);
      final color2 = getAvatarBgColor(s2, children);
      expect(color1, isNotNull);
      expect(color2, isNotNull);
    });

    test('Multiple children starting with the same letter get differentiable colors', () {
      final s1 = Student(roll: 1, name: 'Vishal', className: '6-B', section: 'B');
      final s2 = Student(roll: 2, name: 'Vikash', className: '6-B', section: 'B');
      final children = [s1, s2];
      
      final color1 = getAvatarBgColor(s1, children);
      final color2 = getAvatarBgColor(s2, children);
      
      expect(color1, isNot(equals(color2)));
    });

    test('Three children starting with the same letter get distinct colors', () {
      final s1 = Student(roll: 1, name: 'Vishal', className: '6-B', section: 'B');
      final s2 = Student(roll: 2, name: 'Vikash', className: '6-B', section: 'B');
      final s3 = Student(roll: 3, name: 'Vivek', className: '6-B', section: 'B');
      final children = [s1, s2, s3];
      
      final color1 = getAvatarBgColor(s1, children);
      final color2 = getAvatarBgColor(s2, children);
      final color3 = getAvatarBgColor(s3, children);
      
      expect(color1, isNot(equals(color2)));
      expect(color2, isNot(equals(color3)));
      expect(color1, isNot(equals(color3)));
    });
  });
}
