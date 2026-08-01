import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Bridge to Shizuku for elevated permissions (screenshots, shell commands)
class ShizukuService {
  static const _channel = MethodChannel('com.hermes.plugin/shizuku');

  bool _connected = false;
  bool _authorized = false;
  bool get isConnected => _connected;
  bool get isAuthorized => _authorized;

  final StreamController<ShizukuEvent> _eventController =
      StreamController<ShizukuEvent>.broadcast();
  Stream<ShizukuEvent> get events => _eventController.stream;

  ShizukuService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Initialize Shizuku connection
  Future<void> init() async {
    try {
      _connected = await _channel.invokeMethod('checkShizukuRunning');
      if (_connected) {
        _authorized = await _channel.invokeMethod('checkShizukuPermission');
      } else {
        _authorized = false;
      }
    } catch (e) {
      _connected = false;
      _authorized = false;
    }
  }

  /// Re-check Shizuku permission (independent of cached state)
  Future<bool> checkPermission() async {
    try {
      _connected = await _channel.invokeMethod('checkShizukuRunning');
      if (_connected) {
        _authorized = await _channel.invokeMethod('checkShizukuPermission');
      } else {
        // Shizuku might not be running yet — try anyway
        _authorized = await _channel.invokeMethod('checkShizukuPermission');
      }
      return _authorized;
    } catch (e) {
      return false;
    }
  }

  /// Request Shizuku permission
  Future<bool> requestPermission() async {
    try {
      _authorized = await _channel.invokeMethod('requestPermission');
      return _authorized;
    } catch (e) {
      return false;
    }
  }

  /// Capture screenshot via Shizuku shell command
  Future<String?> captureScreenshot() async {
    try {
      // Use screencap command via Shizuku
      final result = await _channel.invokeMethod('execCommand', {
        'command': 'screencap -p /sdcard/hermes_screenshot.png',
      });
      final output = result?.toString() ?? '';
      if (!output.startsWith('ERROR:')) {
        // Get the file path from Kotlin (validates path is safe)
        final filePath = await _channel.invokeMethod('readFile', {
          'path': '/sdcard/hermes_screenshot.png',
        });
        if (filePath != null) {
          // Read file directly via Dart IO (avoids Binder 1MB limit)
          final file = File(filePath.toString());
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            // Delete temp file
            await _channel.invokeMethod('execCommand', {
              'command': 'rm /sdcard/hermes_screenshot.png',
            });
            return base64Encode(bytes);
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Execute a shell command via Shizuku
  Future<Map<String, dynamic>> execCommand(String command) async {
    try {
      final result = await _channel.invokeMethod('execCommand', {
        'command': command,
      });
      return {
        'success': true,
        'output': result?.toString() ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get device info via shell commands
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod('getDeviceInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Set volume level (0-15)
  Future<bool> setVolume(int stream, int level) async {
    try {
      return await _channel.invokeMethod('setVolume', {
        'stream': stream,
        'level': level,
      });
    } catch (e) {
      return false;
    }
  }

  /// Get current volume
  Future<int> getVolume(int stream) async {
    try {
      return await _channel.invokeMethod('getVolume', {'stream': stream});
    } catch (e) {
      return -1;
    }
  }

  /// Set ringer mode (0=silent, 1=vibrate, 2=normal)
  Future<bool> setRingerMode(int mode) async {
    try {
      return await _channel.invokeMethod('setRingerMode', {'mode': mode});
    } catch (e) {
      return false;
    }
  }

  /// Get ringer mode
  Future<int> getRingerMode() async {
    try {
      return await _channel.invokeMethod('getRingerMode');
    } catch (e) {
      return -1;
    }
  }

  /// Turn screen on/off via input event
  Future<bool> setScreenState(bool on) async {
    try {
      final cmd = on ? 'input keyevent KEYCODE_WAKEUP' : 'input keyevent KEYCODE_SLEEP';
      final result = await _channel.invokeMethod('execCommand', {'command': cmd});
      final output = result?.toString() ?? '';
      return !output.startsWith('ERROR:');
    } catch (e) {
      return false;
    }
  }

  /// Get list of installed packages
  Future<List<String>> getInstalledPackages() async {
    try {
      final result = await _channel.invokeMethod('execCommand', {
        'command': 'pm list packages',
      });
      if (result != null) {
        final lines = result.toString().split('\n');
        return lines
            .where((l) => l.startsWith('package:'))
            .map((l) => l.replaceFirst('package:', '').trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onShizukuEvent':
        final event = ShizukuEvent(
          type: call.arguments['type'] as String? ?? 'unknown',
          message: call.arguments['message'] as String?,
        );
        _eventController.add(event);
        break;
    }
  }

  void dispose() {
    _eventController.close();
  }
}

class ShizukuEvent {
  final String type;
  final String? message;

  ShizukuEvent({required this.type, this.message});
}
