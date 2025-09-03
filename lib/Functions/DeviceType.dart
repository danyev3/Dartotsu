import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

Future<bool> isAndroidTV() async {
  if (Platform.isAndroid) {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return androidInfo.systemFeatures
            .contains('android.software.leanback_only') ||
        androidInfo.systemFeatures.contains('android.hardware.type.television');
  }
  return false;
}
