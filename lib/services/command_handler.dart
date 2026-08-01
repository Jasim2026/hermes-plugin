import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../models/command.dart';
import 'accessibility_bridge.dart';
import 'shizuku_service.dart';
import 'websocket_server.dart';

/// Central command handler that routes commands to the appropriate service
class CommandHandler {
  final AccessibilityBridge _accessibility;
  final ShizukuService _shizuku;

  CommandHandler(this._accessibility, this._shizuku);

  /// Handle an incoming command and return a response
  Future<CommandResponse> handle(Command command) async {
    try {
      switch (command.command) {
        case Commands.ping:
          return CommandResponse(
            id: command.id,
            success: true,
            data: {'pong': true, 'timestamp': DateTime.now().toIso8601String()},
          );

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

  Future<CommandResponse> _handleScreenshot(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final base64Image = await _shizuku.captureScreenshot();
    if (base64Image != null) {
      return CommandResponse(
        id: command.id,
        success: true,
        data: {'image': base64Image, 'format': 'png'},
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Screenshot capture failed',
    );
  }

  Future<CommandResponse> _handleTap(Command command) async {
    final x = (command.params['x'] as num?)?.toDouble() ?? 0;
    final y = (command.params['y'] as num?)?.toDouble() ?? 0;
    final success = await _accessibility.tap(x, y);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'tapped': true, 'x': x, 'y': y} : null,
      error: success ? null : 'Tap failed',
    );
  }

  Future<CommandResponse> _handleLongPress(Command command) async {
    final x = (command.params['x'] as num?)?.toDouble() ?? 0;
    final y = (command.params['y'] as num?)?.toDouble() ?? 0;
    final success = await _accessibility.longPress(x, y);
    return CommandResponse(
      id: command.id,
      success: success,
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
    final success = await _accessibility.swipe(x1, y1, x2, y2,
        durationMs: duration);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success
          ? {'swiped': true, 'from': {'x': x1, 'y': y1}, 'to': {'x': x2, 'y': y2}}
          : null,
      error: success ? null : 'Swipe failed',
    );
  }

  Future<CommandResponse> _handleScroll(Command command) async {
    final direction = command.params['direction'] as String? ?? 'down';
    final distance = (command.params['distance'] as num?)?.toDouble() ?? 500;
    final success = await _accessibility.scroll(direction, distance: distance);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'scrolled': true, 'direction': direction} : null,
      error: success ? null : 'Scroll failed',
    );
  }

  Future<CommandResponse> _handleTypeText(Command command) async {
    final text = command.params['text'] as String? ?? '';
    if (text.isEmpty) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'No text provided',
      );
    }
    final success = await _accessibility.typeText(text);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'typed': true, 'length': text.length} : null,
      error: success ? null : 'Type text failed',
    );
  }

  Future<CommandResponse> _handlePressBack(Command command) async {
    final success = await _accessibility.pressBack();
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'pressed': 'back'} : null,
      error: success ? null : 'Press back failed',
    );
  }

  Future<CommandResponse> _handlePressHome(Command command) async {
    final success = await _accessibility.pressHome();
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'pressed': 'home'} : null,
      error: success ? null : 'Press home failed',
    );
  }

  Future<CommandResponse> _handlePressRecent(Command command) async {
    final success = await _accessibility.pressRecent();
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'pressed': 'recent'} : null,
      error: success ? null : 'Press recent failed',
    );
  }

  Future<CommandResponse> _handleVolumeUp(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final current = await _shizuku.getVolume(3); // STREAM_MUSIC
    if (current >= 0) {
      final success = await _shizuku.setVolume(3, current + 1);
      return CommandResponse(
        id: command.id,
        success: success,
        data: success ? {'volume': current + 1} : null,
        error: success ? null : 'Volume up failed',
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Failed to get current volume',
    );
  }

  Future<CommandResponse> _handleVolumeDown(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final current = await _shizuku.getVolume(3);
    if (current > 0) {
      final success = await _shizuku.setVolume(3, current - 1);
      return CommandResponse(
        id: command.id,
        success: success,
        data: success ? {'volume': current - 1} : null,
        error: success ? null : 'Volume down failed',
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Volume already at minimum',
    );
  }

  Future<CommandResponse> _handleSetVolume(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final volume = (command.params['volume'] as num?)?.toInt() ?? 0;
    final stream = (command.params['stream'] as num?)?.toInt() ?? 3;
    final success = await _shizuku.setVolume(stream, volume);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'volume': volume, 'stream': stream} : null,
      error: success ? null : 'Set volume failed',
    );
  }

  Future<CommandResponse> _handleSetMode(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final mode = command.params['mode'] as String? ?? 'normal';
    int modeValue;
    switch (mode) {
      case 'silent':
        modeValue = 0;
        break;
      case 'vibrate':
        modeValue = 1;
        break;
      case 'normal':
        modeValue = 2;
        break;
      default:
        return CommandResponse(
          id: command.id,
          success: false,
          error: 'Invalid mode: $mode (use silent/vibrate/normal)',
        );
    }
    final success = await _shizuku.setRingerMode(modeValue);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'mode': mode} : null,
      error: success ? null : 'Set mode failed',
    );
  }

  Future<CommandResponse> _handleScreenOn(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final success = await _shizuku.setScreenState(true);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'screen': 'on'} : null,
      error: success ? null : 'Screen on failed',
    );
  }

  Future<CommandResponse> _handleScreenOff(Command command) async {
    if (!_shizuku.isAuthorized) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'Shizuku not authorized',
      );
    }
    final success = await _shizuku.setScreenState(false);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'screen': 'off'} : null,
      error: success ? null : 'Screen off failed',
    );
  }

  Future<CommandResponse> _handleOpenApp(Command command) async {
    final packageName = command.params['packageName'] as String? ?? '';
    if (packageName.isEmpty) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'No package name provided',
      );
    }

    // Try accessibility first, fall back to Shizuku
    bool success = await _accessibility.openApp(packageName);
    if (!success && _shizuku.isAuthorized) {
      final result = await _shizuku.execCommand(
        'monkey -p $packageName -c android.intent.category.LAUNCHER 1',
      );
      success = result['success'] == true;
    }

    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'opened': packageName} : null,
      error: success ? null : 'Failed to open app: $packageName',
    );
  }

  Future<CommandResponse> _handleGetScreenContent(Command command) async {
    final content = await _accessibility.getScreenContent();
    if (content != null) {
      return CommandResponse(
        id: command.id,
        success: true,
        data: content,
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Failed to get screen content',
    );
  }

  Future<CommandResponse> _handleFindElement(Command command) async {
    final text = command.params['text'] as String? ?? '';
    if (text.isEmpty) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'No search text provided',
      );
    }
    final element = await _accessibility.findElement(text);
    if (element != null) {
      return CommandResponse(
        id: command.id,
        success: true,
        data: element,
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Element not found: $text',
    );
  }

  Future<CommandResponse> _handleClickElement(Command command) async {
    final nodeId = command.params['nodeId'] as String? ?? '';
    if (nodeId.isEmpty) {
      return CommandResponse(
        id: command.id,
        success: false,
        error: 'No node ID provided',
      );
    }
    final success = await _accessibility.clickElement(nodeId);
    return CommandResponse(
      id: command.id,
      success: success,
      data: success ? {'clicked': nodeId} : null,
      error: success ? null : 'Failed to click element: $nodeId',
    );
  }

  Future<CommandResponse> _handleGetDeviceInfo(Command command) async {
    if (_shizuku.isAuthorized) {
      final info = await _shizuku.getDeviceInfo();
      return CommandResponse(
        id: command.id,
        success: true,
        data: info,
      );
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'Shizuku not authorized',
    );
  }

  Future<CommandResponse> _handleGetInstalledApps(Command command) async {
    if (_shizuku.isAuthorized) {
      final packages = await _shizuku.getInstalledPackages();
      return CommandResponse(
        id: command.id,
        success: true,
        data: {'packages': packages, 'count': packages.length},
      );
    }
    // Fallback to accessibility
    final apps = await _accessibility.getInstalledApps();
    return CommandResponse(
      id: command.id,
      success: true,
      data: {'apps': apps, 'count': apps.length},
    );
  }
}
