import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_unique_id';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }
}
