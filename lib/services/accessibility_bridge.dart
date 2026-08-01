import 'dart:async';
import 'package:flutter/services.dart';

/// Bridge to Android AccessibilityService via MethodChannel
class AccessibilityBridge {
  static const _channel = MethodChannel('com.hermes.plugin/accessibility');
  static const _lifecycleChannel = MethodChannel('com.hermes.plugin/lifecycle');

  bool _connected = false;
  bool get isConnected => _connected;

  final StreamController<AccessibilityEvent> _eventController =
      StreamController<AccessibilityEvent>.broadcast();
  Stream<AccessibilityEvent> get events => _eventController.stream;

  AccessibilityBridge() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> init() async {
    try {
      _connected = await _channel.invokeMethod('checkAccessibilityEnabled');
    } catch (e) {
      _connected = false;
    }
  }

  /// Check if accessibility service is enabled
  Future<bool> isEnabled() async {
    try {
      _connected = await _lifecycleChannel.invokeMethod('getAccessibilityService');
      return _connected;
    } catch (e) {
      return false;
    }
  }

  /// Open accessibility settings
  Future<void> openSettings() async {
    try {
      await _lifecycleChannel.invokeMethod('openSettings', {
        'action': 'android.settings.ACCESSIBILITY_SETTINGS',
        'data': '',
      });
    } catch (e) {
      // fallback: try direct intent
      try {
        await _lifecycleChannel.invokeMethod('openSettings', {
          'action': 'android.settings.ACCESSIBILITY_SETTINGS',
        });
      } catch (e2) {}
    }
  }

  /// Tap at screen coordinates
  Future<bool> tap(double x, double y) async {
    try {
      return await _channel.invokeMethod('tap', {'x': x, 'y': y});
    } catch (e) {
      return false;
    }
  }

  /// Long press at screen coordinates
  Future<bool> longPress(double x, double y) async {
    try {
      return await _channel.invokeMethod('longPress', {'x': x, 'y': y});
    } catch (e) {
      return false;
    }
  }

  /// Swipe from (x1,y1) to (x2,y2)
  Future<bool> swipe(double x1, double y1, double x2, double y2,
      {int durationMs = 300}) async {
    try {
      return await _channel.invokeMethod('swipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
      });
    } catch (e) {
      return false;
    }
  }

  /// Scroll in direction: 'up', 'down', 'left', 'right'
  Future<bool> scroll(String direction, {double distance = 500}) async {
    try {
      return await _channel.invokeMethod('scroll', {
        'direction': direction,
        'distance': distance,
      });
    } catch (e) {
      return false;
    }
  }

  /// Type text into focused field
  Future<bool> typeText(String text) async {
    try {
      return await _channel.invokeMethod('typeText', {'text': text});
    } catch (e) {
      return false;
    }
  }

  /// Press back button
  Future<bool> pressBack() async {
    try {
      return await _channel.invokeMethod('pressBack');
    } catch (e) {
      return false;
    }
  }

  /// Press home button
  Future<bool> pressHome() async {
    try {
      return await _channel.invokeMethod('pressHome');
    } catch (e) {
      return false;
    }
  }

  /// Press recent apps button
  Future<bool> pressRecent() async {
    try {
      return await _channel.invokeMethod('pressRecent');
    } catch (e) {
      return false;
    }
  }

  /// Get screen content (accessibility tree)
  Future<Map<String, dynamic>?> getScreenContent() async {
    try {
      final result = await _channel.invokeMethod('getScreenContent');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return null;
    }
  }

  /// Find element by text
  Future<Map<String, dynamic>?> findElement(String text) async {
    try {
      final result = await _channel.invokeMethod('findElement', {'text': text});
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      return null;
    }
  }

  /// Click element by accessibility node ID
  Future<bool> clickElement(String nodeId) async {
    try {
      return await _channel.invokeMethod('clickElement', {'nodeId': nodeId});
    } catch (e) {
      return false;
    }
  }

  /// Get installed apps
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod('getInstalledApps');
      return (result as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
    } catch (e) {
      return [];
    }
  }

  /// Turn screen on via accessibility
  Future<bool> screenOn() async {
    try {
      return await _channel.invokeMethod('screenOn');
    } catch (e) {
      return false;
    }
  }

  /// Turn screen off via accessibility
  Future<bool> screenOff() async {
    try {
      return await _channel.invokeMethod('screenOff');
    } catch (e) {
      return false;
    }
  }

  /// Capture screenshot via accessibility service (API 30+)
  Future<String?> captureScreenshot() async {
    try {
      final completer = Completer<String?>();
      _screenshotCompleter = completer;
      await _channel.invokeMethod('takeScreenshot');
      return await completer.future;
    } catch (e) {
      return null;
    }
  }

  Completer<String?>? _screenshotCompleter;

  /// Open app by package name
  Future<bool> openApp(String packageName) async {
    try {
      return await _channel.invokeMethod('openApp', {
        'packageName': packageName,
      });
    } catch (e) {
      return false;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAccessibilityEvent':
        final event = AccessibilityEvent.fromMap(
          Map<String, dynamic>.from(call.arguments),
        );
        _eventController.add(event);
        break;
      case 'screenshotResult':
        final base64 = call.arguments as String?;
        if (_screenshotCompleter != null && !_screenshotCompleter!.isCompleted) {
          _screenshotCompleter!.complete(base64);
          _screenshotCompleter = null;
        }
        break;
      case 'screenshotError':
        if (_screenshotCompleter != null && !_screenshotCompleter!.isCompleted) {
          _screenshotCompleter!.complete(null);
          _screenshotCompleter = null;
        }
        break;
    }
  }

  void dispose() {
    _eventController.close();
  }
}

class AccessibilityEvent {
  final String eventType;
  final String? packageName;
  final String? className;
  final String? text;
  final String? description;

  AccessibilityEvent({
    required this.eventType,
    this.packageName,
    this.className,
    this.text,
    this.description,
  });

  factory AccessibilityEvent.fromMap(Map<String, dynamic> map) {
    return AccessibilityEvent(
      eventType: map['eventType'] as String? ?? 'unknown',
      packageName: map['packageName'] as String?,
      className: map['className'] as String?,
      text: map['text'] as String?,
      description: map['description'] as String?,
    );
  }
}
