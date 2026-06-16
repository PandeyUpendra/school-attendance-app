import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../theme.dart';

class LocationDetails {
  final String address;
  final String city;
  final String state;
  final String pinCode;

  LocationDetails({
    required this.address,
    required this.city,
    required this.state,
    required this.pinCode,
  });

  @override
  String toString() {
    return 'LocationDetails(address: $address, city: $city, state: $state, pinCode: $pinCode)';
  }
}

class LocationService {
  /// Hardcoded list of Indian states/UTs for mapping
  static const List<String> indianStates = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
    'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
    'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
    'West Bengal',
    'Andaman and Nicobar Islands', 'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
    'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ];

  /// Normalize state name to match the application's predefined list of states.
  static String normalizeState(String stateName) {
    if (stateName.isEmpty) return '';
    final lowerState = stateName.toLowerCase().trim();

    // Try exact/case-insensitive match first
    for (final s in indianStates) {
      if (s.toLowerCase().trim() == lowerState) {
        return s;
      }
    }

    // Try substring matching (e.g., "NCT of Delhi" -> "Delhi")
    for (final s in indianStates) {
      final lowerS = s.toLowerCase();
      if (lowerState.contains(lowerS) || lowerS.contains(lowerState)) {
        return s;
      }
    }

    return '';
  }

  /// Checks if a string looks like a Plus Code (Open Location Code) or a
  /// short coded identifier rather than a real address part.
  /// Examples of Plus Codes: "MDR93E", "7JVW+QR5", "MQRG+6HW"
  static bool _isPlusCodeOrJunk(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;

    // Plus Codes with '+' (e.g., "7JVW+QR5", "MQRG+6HW")
    if (RegExp(r'^[2-9A-Z]{4}\+[2-9A-Z0-9]{2,3}$', caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }

    // Short alphanumeric codes without spaces (e.g., "MDR93E", "XY4R2")
    // Real address parts usually have spaces or are longer meaningful words
    if (trimmed.length <= 8 &&
        RegExp(r'^[A-Z0-9]+$', caseSensitive: false).hasMatch(trimmed) &&
        RegExp(r'[0-9]').hasMatch(trimmed) &&
        RegExp(r'[A-Za-z]').hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  /// Requests permissions and fetches the current device location.
  /// Then reverse-geocodes using OpenStreetMap Nominatim API.
  static Future<LocationDetails> getCurrentLocation() async {
    // 1. Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled. Please enable GPS.';
    }

    // 2. Check and request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permissions are denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Location permissions are permanently denied. Please enable them in app settings.';
    }

    // 3. Fetch current coordinates
    // Try high accuracy first (GPS) with a generous timeout.
    // If that fails, fall back to lower accuracy (network/cell tower)
    // which is much faster but less precise.
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
    } on TimeoutException {
      // GPS timed out — fall back to network-based location
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 15),
      );
    }

    // 4. Reverse geocode via Nominatim OSM API
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1'
    );

    final response = await http.get(url, headers: {
      'User-Agent': 'SchoolAttendanceApp/1.0 (contact: support@schoolattendance.app)',
      'Accept-Language': 'en',
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final addressData = data['address'] as Map<String, dynamic>? ?? {};

      // Extract parts
      String city = addressData['city'] ?? 
                    addressData['town'] ?? 
                    addressData['village'] ?? 
                    addressData['suburb'] ?? 
                    addressData['county'] ?? '';
      
      String state = addressData['state'] ?? '';
      String pinCode = addressData['postcode'] ?? '';

      // Normalize state to match the app's predefined list
      String matchedState = normalizeState(state);

      // Clean pinCode to exact 6-digits if it is Indian pin code
      final pinMatch = RegExp(r'\d{6}').firstMatch(pinCode);
      if (pinMatch != null) {
        pinCode = pinMatch.group(0)!;
      } else {
        pinCode = pinCode.replaceAll(RegExp(r'\D'), '');
      }

      // Construct a readable full address
      List<String> addressParts = [];

      // Keys in priority order for building a readable address
      const addressKeys = [
        'amenity', 'building', 'house_number', 'road',
        'neighbourhood', 'quarter', 'residential',
        'hamlet', 'locality', 'suburb',
      ];

      for (final key in addressKeys) {
        final value = addressData[key]?.toString();
        if (value != null && value.isNotEmpty && !_isPlusCodeOrJunk(value)) {
          addressParts.add(value);
        }
      }
      
      String constructedAddress = addressParts.join(', ');
      
      // Fallback to display_name if constructed address is too short or empty
      if (constructedAddress.length < 10) {
        final displayName = data['display_name']?.toString() ?? '';
        // Strip country, state, city, and pincode from the tail of display_name
        // Nominatim display_name format: "part1, part2, ..., city, state, postcode, country"
        if (displayName.isNotEmpty) {
          final parts = displayName.split(', ');
          // Remove last parts that match country/state/postcode/city
          final strippedParts = <String>[];
          final lowerCity = city.toLowerCase();
          final lowerState = state.toLowerCase();
          for (final part in parts) {
            final lowerPart = part.toLowerCase().trim();
            // Skip parts that are country, state, city, postcode, or Plus Codes
            if (lowerPart == 'india' ||
                lowerPart == lowerState ||
                lowerPart == lowerCity ||
                lowerPart == pinCode ||
                _isPlusCodeOrJunk(part)) {
              continue;
            }
            strippedParts.add(part.trim());
          }
          constructedAddress = strippedParts.isNotEmpty
              ? strippedParts.join(', ')
              : displayName;
        }
      }

      return LocationDetails(
        address: constructedAddress,
        city: city,
        state: matchedState,
        pinCode: pinCode,
      );
    } else {
      throw 'Failed to get address from coordinates. Status: ${response.statusCode}';
    }
  }

  /// Displays a user-friendly dialog or SnackBar depending on the error type.
  /// If location services are disabled, prompts to turn them on.
  /// If location permissions are permanently denied, prompts to open app settings.
  static Future<void> handleLocationError(BuildContext context, Object error) async {
    final errorStr = error.toString();
    final isServiceDisabled = errorStr.contains('Location services are disabled') || 
                              errorStr.contains('Location services are turned off');
    final isPermissionPermanentlyDenied = errorStr.contains('permanently denied');

    if (isServiceDisabled) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.location_off_outlined, color: AppTheme.danger, size: 28),
              SizedBox(width: 10),
              Text('Location Services Off', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Location services (GPS) are turned off on your device. Please turn them on in your settings to pick your location.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Geolocator.openLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else if (isPermissionPermanentlyDenied) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.gpp_bad_outlined, color: AppTheme.danger, size: 28),
              SizedBox(width: 10),
              Text('Permission Denied', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Location permissions are permanently denied. Please enable them in your app settings to pick your location.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Geolocator.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      // Show a user-friendly message for timeout errors
      final isTimeout = errorStr.contains('TimeoutException') || 
                         errorStr.contains('Future not completed');
      final message = isTimeout 
          ? 'Location request timed out. Please try again in an open area with clear sky.'
          : 'Could not get location: $errorStr';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
}
