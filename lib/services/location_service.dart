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
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

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
      
      if (addressData['amenity'] != null) addressParts.add(addressData['amenity'].toString());
      if (addressData['building'] != null) addressParts.add(addressData['building'].toString());
      if (addressData['house_number'] != null) addressParts.add(addressData['house_number'].toString());
      if (addressData['road'] != null) addressParts.add(addressData['road'].toString());
      if (addressData['neighbourhood'] != null) addressParts.add(addressData['neighbourhood'].toString());
      if (addressData['suburb'] != null) addressParts.add(addressData['suburb'].toString());
      
      String constructedAddress = addressParts.join(', ');
      
      // Fallback to display_name if constructed address is too short
      if (constructedAddress.length < 5) {
        constructedAddress = data['display_name'] ?? '';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get location: $errorStr'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
}
