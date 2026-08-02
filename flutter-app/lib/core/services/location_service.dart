import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/providers/core_providers.dart';

/// 定位结果
class LocationResult {
  const LocationResult({required this.address, this.latitude, this.longitude});

  final String address;
  final double? latitude;
  final double? longitude;
}

/// 位置服务
class LocationService {
  final Geocoding _geocoding;

  LocationService() : _geocoding = Geocoding();

  Future<bool> ensurePermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) {
      throw const LocationException('定位服务未开启');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('定位权限被拒绝');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('定位权限被永久拒绝，请在设置中开启');
    }
    return true;
  }

  /// 获取当前定位并逆地理编码为可读地址。
  Future<LocationResult> getCurrent() async {
    await ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
    final address = await _reverseGeocode(
      position.latitude,
      position.longitude,
    );
    return LocationResult(
      address: address,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// 逆地理编码：将坐标转为可读地址。
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty)
        return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      final p = placemarks.first;
      final parts = <String>[
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
          p.administrativeArea!,
        if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
      ];
      if (parts.isEmpty) {
        final fallback = [
          if (p.name != null && p.name!.isNotEmpty) p.name!,
          if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty)
            p.thoroughfare!,
        ];
        if (fallback.isEmpty) {
          return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        }
        return fallback.join(' ');
      }
      return parts.join(' ');
    } catch (_) {
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }
  }
}

/// 定位异常
class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 位置服务 Provider
final locationServiceProvider = Provider<LocationService>((ref) {
  ref.watch(sharedPrefsStorageProvider);
  return LocationService();
});
