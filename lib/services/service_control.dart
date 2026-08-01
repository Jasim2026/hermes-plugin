import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/command.dart';
import 'websocket_server.dart';
import 'command_handler.dart';
import 'accessibility_bridge.dart';
import 'shizuku_service.dart';

/// Handles start/stop via file-based signaling to Kotlin HermesService
class ServiceControl {
  static const _channel = MethodChannel('com.hermes.plugin/service_control');
  static const String _controlDir = '/sdcard/hermes_plugin';
  static const String _controlFile = 'control.txt';
  static const String _responseFile = 'response.txt';

  final WebSocketServer _server = WebSocketServer();
  final AccessibilityBridge _accessibility = AccessibilityBridge();
  final ShizukuService _shizuku = ShizukuService();
  CommandHandler? _handler;

  bool get isRunning => _server.isRunning;
  WebSocketServer get server => _server;
  bool get accessibilityEnabled => _accessibilityEnabled;
  set accessibilityEnabled(bool val) => _accessibilityEnabled = val;
  AccessibilityBridge get accessibility => _accessibility;
  bool get shizukuConnected => _shizuku.isConnected;
  bool get shizukuAuthorized => _shizuku.isAuthorized;

  bool _accessibilityEnabled = false;

  ServiceControl() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> init() async {
    _handler = CommandHandler(_accessibility, _shizuku);
    _accessibilityEnabled = await _accessibility.isEnabled();
    await _shizuku.init();
  }

  // ========================
  // FILE-BASED CONTROL
  // ========================

  /// Send command via file signal
  Future<String> _sendCommand(String command) async {
    try {
      final dir = Directory(_controlDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Write command
      final cmdFile = File('$_controlDir/$_controlFile');
      await cmdFile.writeAsString(command);

      // Poll for response (max 5 seconds)
      final respFile = File('$_controlDir/$_responseFile');
      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (await respFile.exists()) {
          final response = await respFile.readAsString();
          if (response.isNotEmpty && response != 'IDLE') {
            return response.trim();
          }
        }
      }
      return 'TIMEOUT';
    } catch (e) {
      return 'ERROR:$e';
    }
  }

  Future<void> startServer() async {
    await _sendCommand('START');
  }

  Future<void> stopServer() async {
    await _sendCommand('STOP');
  }

  // ========================
  // METHOD CHANNEL HANDLER
  // ========================

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'startWsServer':
        final port = call.arguments['port'] as int? ?? 8765;
        await _startServer(port);
        return true;
      case 'stopWsServer':
        await _stopServer();
        return true;
      default:
        return false;
    }
  }

  Future<void> _startServer(int port) async {
    if (_server.isRunning) return;

    // Wire up event streaming: CommandHandler → WS broadcast
    _handler?.setEventSink((json) => _server.broadcastString(json));

    await _server.start(
      port: port,
      handler: (cmd) async {
        if (_handler == null) {
          return CommandResponse(
            id: cmd.id,
            success: false,
            error: 'Handler not initialized',
          );
        }
        return await _handler!.handle(cmd);
      },
    );
  }

  Future<void> _stopServer() async {
    if (!_server.isRunning) return;
    await _server.stop();
  }

  // ========================
  // PERMISSION HELPERS
  // ========================

  Future<void> openAppInfo() async {
    try {
      await _channel.invokeMethod('openAppInfo');
    } catch (e) {
      try {
        await _channel.invokeMethod('openSettings', {
          'action': 'APPLICATION_DETAILS_SETTINGS',
          'data': 'package:com.hermes.plugin',
        });
      } catch (e2) {}
    }
  }

  Future<bool> isNotificationPermissionGranted() async {
    try {
      return await _channel.invokeMethod('checkNotificationPermission') ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod('requestNotificationPermission') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestShizukuPermission() async {
    try {
      return await _shizuku.requestPermission();
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _server.stop();
    _accessibility.dispose();
    _shizuku.dispose();
  }
}
