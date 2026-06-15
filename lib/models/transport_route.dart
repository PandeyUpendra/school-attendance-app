import 'package:cloud_firestore/cloud_firestore.dart';

class TransportStop {
  final String name;
  final String expectedTime;
  final int sequence;

  const TransportStop({
    required this.name,
    required this.expectedTime,
    required this.sequence,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'expectedTime': expectedTime,
        'sequence': sequence,
      };

  factory TransportStop.fromJson(Map<String, dynamic> json) => TransportStop(
        name: json['name']?.toString() ?? '',
        expectedTime: json['expectedTime']?.toString() ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      );
}

class TransportRoute {
  final String id;
  final String schoolId;
  final String name;
  final String driverName;
  final String driverPhone;
  final bool isActive;
  final int currentStopIndex;
  final DateTime lastUpdated;
  final List<TransportStop> stops;

  const TransportRoute({
    required this.id,
    required this.schoolId,
    required this.name,
    required this.driverName,
    required this.driverPhone,
    required this.isActive,
    required this.currentStopIndex,
    required this.lastUpdated,
    required this.stops,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolId': schoolId,
        'name': name,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'isActive': isActive,
        'currentStopIndex': currentStopIndex,
        'lastUpdated': Timestamp.fromDate(lastUpdated),
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  factory TransportRoute.fromJson(Map<String, dynamic> json) {
    var stopsList = json['stops'] as List? ?? [];
    var stops = stopsList
        .map((s) => TransportStop.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    stops.sort((a, b) => a.sequence.compareTo(b.sequence));

    return TransportRoute(
      id: json['id']?.toString() ?? '',
      schoolId: json['schoolId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      driverName: json['driverName']?.toString() ?? '',
      driverPhone: json['driverPhone']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? false,
      currentStopIndex: (json['currentStopIndex'] as num?)?.toInt() ?? -1,
      lastUpdated: (json['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      stops: stops,
    );
  }

  TransportRoute copyWith({
    String? id,
    String? schoolId,
    String? name,
    String? driverName,
    String? driverPhone,
    bool? isActive,
    int? currentStopIndex,
    DateTime? lastUpdated,
    List<TransportStop>? stops,
  }) =>
      TransportRoute(
        id: id ?? this.id,
        schoolId: schoolId ?? this.schoolId,
        name: name ?? this.name,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        isActive: isActive ?? this.isActive,
        currentStopIndex: currentStopIndex ?? this.currentStopIndex,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        stops: stops ?? this.stops,
      );
}
