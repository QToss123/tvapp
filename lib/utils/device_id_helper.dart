import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Helper to get device ID from the actual device:
/// - Android/TV: IMEI (when available) or androidId
/// - Windows/Linux: deviceId/machineId + MAC address
class DeviceIdHelper {
  static const _channel = MethodChannel('com.liqvid.tv_app_books/device_id');

  /// Gets platform-specific device ID from the device. No fixed IDs.
  static Future<String> getPlatformDeviceId() async {
    try {
      if (Platform.isAndroid) {
        return _getAndroidDeviceId();
      } else if (Platform.isWindows) {
        return _getWindowsDeviceId();
      } else if (Platform.isLinux) {
        return _getLinuxDeviceId();
      } else {
        return _getFallbackDeviceId();
      }
    } catch (e) {
      return _getFallbackDeviceId();
    }
  }

  static Future<String> _getAndroidDeviceId() async {
    try {
      final id = await _channel.invokeMethod<String>('getDeviceId');
      if (id != null && id.isNotEmpty) {
        return id;
      }
    } catch (e) {
    }
    // Fallback: device_info_plus androidId
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final androidId = androidInfo.id;
    return 'android_$androidId';
  }

  static Future<String> _getWindowsDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final windowsInfo = await deviceInfo.windowsInfo;
    final deviceId = windowsInfo.deviceId;
    final mac = await _getWindowsMacAddress();
    final id = mac != null && mac.isNotEmpty
        ? 'win_${deviceId}_$mac'
        : 'win_$deviceId';
    return id;
  }

  static Future<String> _getLinuxDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final linuxInfo = await deviceInfo.linuxInfo;
    final machineId = linuxInfo.machineId ?? '';
    final mac = await _getLinuxMacAddress();
    final id = mac != null && mac.isNotEmpty
        ? 'linux_${machineId}_$mac'
        : 'linux_$machineId';
    return id;
  }

  static Future<String?> _getWindowsMacAddress() async {
    try {
      final result = await Process.run(
        'getmac',
        ['/fo', 'csv', '/nh'],
        runInShell: true,
      );
      if (result.exitCode == 0 && result.stdout != null) {
        final output = result.stdout.toString().trim();
        // Format: "","00-11-22-33-44-55",""
        final lines = output.split('\n');
        final macs = <String>[];
        for (final line in lines) {
          final parts = line.split(',');
          if (parts.length >= 2) {
            final mac = parts[1].replaceAll('"', '').trim();
            if (mac.isNotEmpty &&
                mac.contains('-') &&
                mac.length >= 17 &&
                !mac.startsWith('FF-FF-FF')) {
              macs.add(mac.replaceAll('-', '').toLowerCase());
            }
          }
        }
        macs.sort();
        return macs.isNotEmpty ? macs.first : null;
      }
    } catch (e) {
    }
    return null;
  }

  static Future<String?> _getLinuxMacAddress() async {
    try {
      final interfaces = ['eth0', 'enp0s3', 'eno1', 'wlan0', 'en0'];
      for (final iface in interfaces) {
        final file = File('/sys/class/net/$iface/address');
        if (await file.exists()) {
          final mac = (await file.readAsString()).trim().toLowerCase();
          if (mac.isNotEmpty && mac.contains(':')) {
            return mac.replaceAll(':', '');
          }
        }
      }
      // Fallback: list /sys/class/net and get first non-loopback
      final netDir = Directory('/sys/class/net');
      if (await netDir.exists()) {
        await for (final entity in netDir.list()) {
          if (entity is Directory && entity.path != '/sys/class/net/lo') {
            final addrFile = File('${entity.path}/address');
            if (await addrFile.exists()) {
              final mac = (await addrFile.readAsString()).trim().toLowerCase();
              if (mac.isNotEmpty && mac.contains(':')) {
                return mac.replaceAll(':', '');
              }
            }
          }
        }
      }
    } catch (e) {
    }
    return null;
  }

  static String _getFallbackDeviceId() {
    return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
  }
}
