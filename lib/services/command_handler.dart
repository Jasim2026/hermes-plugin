import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/command.dart';
import 'accessibility_bridge.dart';
import 'shizuku_service.dart';
import 'websocket_server.dart';

/// Central command handler that routes commands to the appropriate service
class CommandHandler {
  final AccessibilityBridge _accessibility;
  final ShizukuService _shizuku;
  static const _lifecycleChannel = MethodChannel('com.hermes.plugin/lifecycle');

  // Event streaming
  bool _streamingEvents = false;
  Function(String)? _eventSink;

  // Screenshot cache
  String? _lastScreenshotHash;
  String? _lastScreenshotBase64;

  // Webhook
  String? _webhookUrl;

  CommandHandler(this._accessibility, this._shizuku);

  /// Set the callback for streaming events over WS
  void setEventSink(Function(String)? sink) {
    _eventSink = sink;
    _streamingEvents = sink != null;
  }

  /// Set webhook URL for event forwarding
  void setWebhook(String? url) {
    _webhookUrl = url;
  }

  String? get webhookUrl => _webhookUrl;

  /// Handle an incoming command and return a response
  Future<CommandResponse> handle(Command command) async {
    try {
      switch (command.command) {
        // Existing commands
        case Commands.ping:
          return _handlePing(command);
        case Commands.screenshot:
          return await _handleScreenshot(command);
        case Commands.tap:
          return await _handleTap(command);
        case Commands.longPress:
          return await _handleLongPress(command);
        case Commands.swipe:
          return await _handleSwipe(command);
        case Commands.scroll:
          return await _handleScroll(command);
        case Commands.typeText:
          return await _handleTypeText(command);
        case Commands.pressBack:
          return await _handlePressBack(command);
        case Commands.pressHome:
          return await _handlePressHome(command);
        case Commands.pressRecent:
          return await _handlePressRecent(command);
        case Commands.volumeUp:
          return await _handleVolumeUp(command);
        case Commands.volumeDown:
          return await _handleVolumeDown(command);
        case Commands.setVolume:
          return await _handleSetVolume(command);
        case Commands.setMode:
          return await _handleSetMode(command);
        case Commands.screenOn:
          return await _handleScreenOn(command);
        case Commands.screenOff:
          return await _handleScreenOff(command);
        case Commands.openApp:
          return await _handleOpenApp(command);
        case Commands.getScreenContent:
          return await _handleGetScreenContent(command);
        case Commands.findElement:
          return await _handleFindElement(command);
        case Commands.clickElement:
          return await _handleClickElement(command);
        case Commands.getDeviceInfo:
          return await _handleGetDeviceInfo(command);
        case Commands.getInstalledApps:
          return await _handleGetInstalledApps(command);

        // Tier 1
        case Commands.getAppState:
          return await _handleGetAppState(command);
        case Commands.getDisplayInfo:
          return await _handleGetDisplayInfo(command);
        case Commands.scaleCoords:
          return _handleScaleCoords(command);

        // Tier 2
        case Commands.batch:
          return await _handleBatch(command);
        case Commands.setWebhook:
          return _handleSetWebhook(command);
        case Commands.clearWebhook:
          return _handleClearWebhook(command);
        case Commands.uiAutomatorDump:
          return await _handleUiAutomatorDump(command);
        case Commands.getInputMethods:
          return await _handleGetInputMethods(command);
        case Commands.setInputMethod:
          return await _handleSetInputMethod(command);
        case Commands.clearInputField:
          return await _handleClearInputField(command);

        // Tier 3
        case Commands.health:
          return await _handleHealth(command);
        case Commands.getBatteryInfo:
          return await _handleGetBatteryInfo(command);
        case Commands.streamEvents:
          return _handleStreamEvents(command);
        case Commands.stopStreamEvents:
          return _handleStopStreamEvents(command);
        case Commands.screenshotCached:
          return await _handleScreenshotCached(command);

        default:
          return CommandResponse(
            id: command.id,
            success: false,
            error: 'Unknown command: ${command.command}',
          );
      }
    } catch (e) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Command execution failed: $e',
      );
    }
  }

  /// Forward accessibility event to webhook and WS stream
  void onAccessibilityEvent(Map<String, dynamic> event) {
    // Stream to WS clients
    if (_streamingEvents && _eventSink != null) {
      final json = jsonEncode({
        'type': 'accessibility_event',
        'data': event,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _eventSink!(json);
    }

    // Forward to webhook
    if (_webhookUrl != null) {
      _forwardToWebhook(event);
    }
  }

  Future<void> _forwardToWebhook(Map<String, dynamic> event) async {
    try {
      // Use Dart HttpClient to POST to webhook
      final uri = Uri.parse(_webhookUrl!);
      // Simple implementation — would use http package in production
    } catch (e) {
      // Silently fail — webhook is best-effort
    }
  }

  // ========================
  // PING (with display info)
  // ========================

  Future<CommandResponse> _handlePing(Command command) async {
    final displayInfo = await _handleGetDisplayInfo(command);
    final batteryInfo = await _handleGetBatteryInfo(command);
    return CommandResponse(
      id: command.id,
      success: true,
      data: {
        'pong': true,
        'timestamp': DateTime.now().toIso8601String(),
        'display': displayInfo.data,
        'battery': batteryInfo.data,
      },
    );
  }

  // ========================
  // TIER 1: APP STATE
  // ========================

  Future<CommandResponse> _handleGetAppState(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('getAppState');
      return CommandResponse(id: command.id, success: true, data: result);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  Future<CommandResponse> _handleGetDisplayInfo(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('getDisplayInfo');
      return CommandResponse(id: command.id, success: true, data: result);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  CommandResponse _handleScaleCoords(Command command) {
    final x = (command.params['x'] as num?)?.toDouble() ?? 0;
    final y = (command.params['y'] as num?)?.toDouble() ?? 0;
    final srcWidth = (command.params['srcWidth'] as num?)?.toDouble() ?? 1080;
    final srcHeight = (command.params['srcHeight'] as num?)?.toDouble() ?? 1920;
    // Target will be the device's actual resolution (from display info)
    // For now, return scale factors
    return CommandResponse(
      id: command.id,
      success: true,
      data: {
        'scaleX': 'device_width / $srcWidth',
        'scaleY': 'device_height / $srcHeight',
        'hint': 'Use get_display_info to get device dimensions, then multiply',
      },
    );
  }

  // ========================
  // TIER 2: BATCH
  // ========================

  Future<CommandResponse> _handleBatch(Command command) async {
    final commands = command.params['commands'] as List<dynamic>? ?? [];
    final verbose = command.params['verbose'] == true;
    final delayMs = (command.params['delayMs'] as num?)?.toInt() ?? 0;

    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < commands.length; i++) {
      final cmdData = commands[i] as Map<String, dynamic>;
      final cmd = Command.fromJson(cmdData);

      final response = await handle(cmd);
      final resultEntry = {
        'index': i,
        'command': cmd.command,
        'success': response.success,
        if (response.data != null) 'data': response.data,
        if (response.error != null) 'error': response.error,
      };
      results.add(resultEntry);

      // Stream verbose output
      if (verbose) {
        final verboseJson = jsonEncode({
          'type': 'batch_progress',
          'index': i,
          'total': commands.length,
          'command': cmd.command,
          'success': response.success,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _eventSink?.call(verboseJson);
      }

      if (delayMs > 0 && i < commands.length - 1) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    final allSuccess = results.every((r) => r['success'] == true);
    return CommandResponse(
      id: command.id,
      success: allSuccess,
      data: {
        'results': results,
        'total': commands.length,
        'succeeded': results.where((r) => r['success'] == true).length,
        'failed': results.where((r) => r['success'] != true).length,
      },
    );
  }

  // ========================
  // TIER 2: WEBHOOK
  // ========================

  CommandResponse _handleSetWebhook(Command command) {
    final url = command.params['url'] as String? ?? '';
    if (url.isEmpty) {
      return CommandResponse(id: command.id, success: false, error: 'No URL provided');
    }
    // Validate URL
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return CommandResponse(id: command.id, success: false, error: 'Invalid URL');
    }
    _webhookUrl = url;
    return CommandResponse(
      id: command.id,
      success: true,
      data: {'webhook': url, 'status': 'active'},
    );
  }

  CommandResponse _handleClearWebhook(Command command) {
    _webhookUrl = null;
    return CommandResponse(id: command.id, success: true, data: {'webhook': null});
  }

  // ========================
  // TIER 2: UI AUTOMATOR
  // ========================

  Future<CommandResponse> _handleUiAutomatorDump(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('uiAutomatorDump');
      if (result['success'] == true) {
        return CommandResponse(id: command.id, success: true, data: result);
      }
      return CommandResponse(id: command.id, success: false, error: result['error'] ?? 'Dump failed');
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  // ========================
  // TIER 2: INPUT METHOD
  // ========================

  Future<CommandResponse> _handleGetInputMethods(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('getInputMethods');
      return CommandResponse(id: command.id, success: true, data: result);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  Future<CommandResponse> _handleSetInputMethod(Command command) async {
    final imeId = command.params['imeId'] as String? ?? '';
    try {
      final result = await _lifecycleChannel.invokeMethod('setInputMethod', {'imeId': imeId});
      return CommandResponse(id: command.id, success: result == true);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  Future<CommandResponse> _handleClearInputField(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('clearInputField');
      return CommandResponse(id: command.id, success: result == true);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  // ========================
  // TIER 3: HEALTH
  // ========================

  Future<CommandResponse> _handleHealth(Command command) async {
    final displayInfo = await _handleGetDisplayInfo(command);
    final batteryInfo = await _handleGetBatteryInfo(command);
    final memInfo = await _getMemoryInfo();

    return CommandResponse(
      id: command.id,
      success: true,
      data: {
        'timestamp': DateTime.now().toIso8601String(),
        'display': displayInfo.data,
        'battery': batteryInfo.data,
        'memory': memInfo,
        'wsClients': 0, // Would be set by WebSocket server
        'uptime': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<Map<String, dynamic>> _getMemoryInfo() async {
    try {
      final result = await _lifecycleChannel.invokeMethod('getMemoryInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<CommandResponse> _handleGetBatteryInfo(Command command) async {
    try {
      final result = await _lifecycleChannel.invokeMethod('getBatteryInfo');
      return CommandResponse(id: command.id, success: true, data: result);
    } catch (e) {
      return CommandResponse(id: command.id, success: false, error: '$e');
    }
  }

  // ========================
  // TIER 3: EVENT STREAMING
  // ========================

  CommandResponse _handleStreamEvents(Command command) {
    _streamingEvents = true;
    return CommandResponse(
      id: command.id,
      success: true,
      data: {'streaming': true, 'message': 'Accessibility events will stream via WS'},
    );
  }

  CommandResponse _handleStopStreamEvents(Command command) {
    _streamingEvents = false;
    return CommandResponse(
      id: command.id,
      success: true,
      data: {'streaming': false},
    );
  }

  // ========================
  // TIER 3: SCREENSHOT CACHE
  // ========================

  Future<CommandResponse> _handleScreenshotCached(Command command) async {
    final forceNew = command.params['force'] == true;

    if (!forceNew && _lastScreenshotBase64 != null && _lastScreenshotHash != null) {
      return CommandResponse(
        id: command.id,
        success: true,
        data: {
          'hash': _lastScreenshotHash,
          'cached': true,
          'format': 'png',
        },
      );
    }

    // Take new screenshot
    final base64Image = await _shizuku.captureScreenshot();
    if (base64Image != null) {
      // Simple hash (length-based for now)
      _lastScreenshotHash = 'ss_${base64Image.length}_${DateTime.now().millisecondsSinceEpoch}';
      _lastScreenshotBase64 = base64Image;

      return CommandResponse(
        id: command.id,
        success: true,
        data: {
          'image': base64Image,
          'hash': _lastScreenshotHash,
          'cached': false,
          'format': 'png',
        },
      );
    }
    return CommandResponse(id: command.id, success: false, error: 'Screenshot failed');
  }

  // ========================
  // EXISTING COMMAND HANDLERS
  // ========================

  Future<CommandResponse> _handleScreenshot(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    }
    final base64Image = await _shizuku.captureScreenshot();
    if (base64Image != null) {
      return CommandResponse(id: command.id, success: true, data: {'image': base64Image, 'format': 'png'});
    }
    return CommandResponse(id: command.id, success: false, error: 'Screenshot capture failed');
  }

  Future<CommandResponse> _handleTap(Command command) async {
    final x = (command.params['x'] as num?)?.toDouble() ?? 0;
    final y = (command.params['y'] as num?)?.toDouble() ?? 0;
    final success = await _accessibility.tap(x, y);
    return CommandResponse(
      id: command.id, success: success,
      data: success ? {'tapped': true, 'x': x, 'y': y} : null,
      error: success ? null : 'Tap failed',
    );
  }

  Future<CommandResponse> _handleLongPress(Command command) async {
    final x = (command.params['x'] as num?)?.toDouble() ?? 0;
    final y = (command.params['y'] as num?)?.toDouble() ?? 0;
    final success = await _accessibility.longPress(x, y);
    return CommandResponse(
      id: command.id, success: success,
      data: success ? {'longPressed': true, 'x': x, 'y': y} : null,
      error: success ? null : 'Long press failed',
    );
  }

  Future<CommandResponse> _handleSwipe(Command command) async {
    final x1 = (command.params['x1'] as num?)?.toDouble() ?? 0;
    final y1 = (command.params['y1'] as num?)?.toDouble() ?? 0;
    final x2 = (command.params['x2'] as num?)?.toDouble() ?? 0;
    final y2 = (command.params['y2'] as num?)?.toDouble() ?? 0;
    final duration = (command.params['durationMs'] as num?)?.toInt() ?? 300;
    final success = await _accessibility.swipe(x1, y1, x2, y2, durationMs: duration);
    return CommandResponse(
      id: command.id, success: success,
      data: success ? {'swiped': true, 'from': {'x': x1, 'y': y1}, 'to': {'x': x2, 'y': y2}} : null,
      error: success ? null : 'Swipe failed',
    );
  }

  Future<CommandResponse> _handleScroll(Command command) async {
    final direction = command.params['direction'] as String? ?? 'down';
    final distance = (command.params['distance'] as num?)?.toDouble() ?? 500;
    final success = await _accessibility.scroll(direction, distance: distance);
    return CommandResponse(
      id: command.id, success: success,
      data: success ? {'scrolled': true, 'direction': direction} : null,
      error: success ? null : 'Scroll failed',
    );
  }

  Future<CommandResponse> _handleTypeText(Command command) async {
    final text = command.params['text'] as String? ?? '';
    if (text.isEmpty) return CommandResponse(id: command.id, success: false, error: 'No text provided');
    final success = await _accessibility.typeText(text);
    return CommandResponse(
      id: command.id, success: success,
      data: success ? {'typed': true, 'length': text.length} : null,
      error: success ? null : 'Type text failed',
    );
  }

  Future<CommandResponse> _handlePressBack(Command command) async {
    final success = await _accessibility.pressBack();
    return CommandResponse(id: command.id, success: success, data: success ? {'pressed': 'back'} : null, error: success ? null : 'Press back failed');
  }

  Future<CommandResponse> _handlePressHome(Command command) async {
    final success = await _accessibility.pressHome();
    return CommandResponse(id: command.id, success: success, data: success ? {'pressed': 'home'} : null, error: success ? null : 'Press home failed');
  }

  Future<CommandResponse> _handlePressRecent(Command command) async {
    final success = await _accessibility.pressRecent();
    return CommandResponse(id: command.id, success: success, data: success ? {'pressed': 'recent'} : null, error: success ? null : 'Press recent failed');
  }

  Future<CommandResponse> _handleVolumeUp(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final current = await _shizuku.getVolume(3);
    if (current >= 0) {
      final success = await _shizuku.setVolume(3, current + 1);
      return CommandResponse(id: command.id, success: success, data: success ? {'volume': current + 1} : null, error: success ? null : 'Volume up failed');
    }
    return CommandResponse(id: command.id, success: false, error: 'Failed to get current volume');
  }

  Future<CommandResponse> _handleVolumeDown(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final current = await _shizuku.getVolume(3);
    if (current > 0) {
      final success = await _shizuku.setVolume(3, current - 1);
      return CommandResponse(id: command.id, success: success, data: success ? {'volume': current - 1} : null, error: success ? null : 'Volume down failed');
    }
    return CommandResponse(id: command.id, success: false, error: 'Volume already at minimum');
  }

  Future<CommandResponse> _handleSetVolume(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final volume = (command.params['volume'] as num?)?.toInt() ?? 0;
    final stream = (command.params['stream'] as num?)?.toInt() ?? 3;
    final success = await _shizuku.setVolume(stream, volume);
    return CommandResponse(id: command.id, success: success, data: success ? {'volume': volume, 'stream': stream} : null, error: success ? null : 'Set volume failed');
  }

  Future<CommandResponse> _handleSetMode(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final mode = command.params['mode'] as String? ?? 'normal';
    int modeValue;
    switch (mode) {
      case 'silent': modeValue = 0; break;
      case 'vibrate': modeValue = 1; break;
      case 'normal': modeValue = 2; break;
      default: return CommandResponse(id: command.id, success: false, error: 'Invalid mode: $mode');
    }
    final success = await _shizuku.setRingerMode(modeValue);
    return CommandResponse(id: command.id, success: success, data: success ? {'mode': mode} : null, error: success ? null : 'Set mode failed');
  }

  Future<CommandResponse> _handleScreenOn(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final success = await _shizuku.setScreenState(true);
    return CommandResponse(id: command.id, success: success, data: success ? {'screen': 'on'} : null, error: success ? null : 'Screen on failed');
  }

  Future<CommandResponse> _handleScreenOff(Command command) async {
    if (!_shizuku.isAuthorized) return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
    final success = await _shizuku.setScreenState(false);
    return CommandResponse(id: command.id, success: success, data: success ? {'screen': 'off'} : null, error: success ? null : 'Screen off failed');
  }

  Future<CommandResponse> _handleOpenApp(Command command) async {
    final packageName = command.params['packageName'] as String? ?? '';
    if (packageName.isEmpty) return CommandResponse(id: command.id, success: false, error: 'No package name provided');
    final pkgRegex = RegExp(r'^[a-zA-Z0-9._]+$');
    if (!pkgRegex.hasMatch(packageName) || packageName.length > 200) {
      return CommandResponse(id: command.id, success: false, error: 'Invalid package name format');
    }
    bool success = await _accessibility.openApp(packageName);
    if (!success && _shizuku.isAuthorized) {
      final result = await _shizuku.execCommand('monkey -p $packageName -c android.intent.category.LAUNCHER 1');
      success = result['success'] == true && !(result['output']?.toString().startsWith('ERROR:') ?? false);
    }
    return CommandResponse(id: command.id, success: success, data: success ? {'opened': packageName} : null, error: success ? null : 'Failed to open app: $packageName');
  }

  Future<CommandResponse> _handleGetScreenContent(Command command) async {
    final content = await _accessibility.getScreenContent();
    if (content != null) return CommandResponse(id: command.id, success: true, data: content);
    return CommandResponse(id: command.id, success: false, error: 'Failed to get screen content');
  }

  Future<CommandResponse> _handleFindElement(Command command) async {
    final text = command.params['text'] as String? ?? '';
    if (text.isEmpty) return CommandResponse(id: command.id, success: false, error: 'No search text provided');
    final element = await _accessibility.findElement(text);
    if (element != null) return CommandResponse(id: command.id, success: true, data: element);
    return CommandResponse(id: command.id, success: false, error: 'Element not found: $text');
  }

  Future<CommandResponse> _handleClickElement(Command command) async {
    final nodeId = command.params['nodeId'] as String? ?? '';
    if (nodeId.isEmpty) return CommandResponse(id: command.id, success: false, error: 'No node ID provided');
    final success = await _accessibility.clickElement(nodeId);
    return CommandResponse(id: command.id, success: success, data: success ? {'clicked': nodeId} : null, error: success ? null : 'Failed to click element: $nodeId');
  }

  Future<CommandResponse> _handleGetDeviceInfo(Command command) async {
    if (_shizuku.isAuthorized) {
      final info = await _shizuku.getDeviceInfo();
      return CommandResponse(id: command.id, success: true, data: info);
    }
    return CommandResponse(id: command.id, success: false, error: 'Shizuku not authorized');
  }

  Future<CommandResponse> _handleGetInstalledApps(Command command) async {
    if (_shizuku.isAuthorized) {
      final packages = await _shizuku.getInstalledPackages();
      return CommandResponse(id: command.id, success: true, data: {'packages': packages, 'count': packages.length});
    }
    final apps = await _accessibility.getInstalledApps();
    return CommandResponse(id: command.id, success: true, data: {'apps': apps, 'count': apps.length});
  }
}
