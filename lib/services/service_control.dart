import 'dart:async';
import 'package:flutter/services.dart';
import '../models/command.dart';
import 'websocket_server.dart';
import 'command_handler.dart';
import 'accessibility_bridge.dart';
import 'shizuku_service.dart';

/// Manages WebSocket server, permissions, and command handling
class ServiceControl {
  static const _lifecycleChannel = MethodChannel('com.hermes.plugin/lifecycle');

  final WebSocketServer _server = WebSocketServer();
  final AccessibilityBridge _accessibility = AccessibilityBridge();
  final ShizukuService _shizuku = ShizukuService();
  CommandHandler? _handler;

  bool get isRunning => _server.isRunning;
  WebSocketServer get server => _server;
  CommandHandler? get handler => _handler;
  bool get accessibilityEnabled => _accessibilityEnabled;
  set accessibilityEnabled(bool val) => _accessibilityEnabled = val;
  AccessibilityBridge get accessibility => _accessibility;
  bool get shizukuConnected => _shizuku.isConnected;
  bool get shizukuAuthorized => _shizuku.isAuthorized;

  bool _accessibilityEnabled = false;

  ServiceControl();

  Future<void> init() async {
    _handler = CommandHandler(_accessibility, _shizuku);
    _accessibilityEnabled = await _accessibility.isEnabled();
    await _shizuku.init();
  }

  // ========================
  // SERVER CONTROL
  // ========================

  Future<void> startServer() async {
    if (_server.isRunning) return;
    _handler ??= CommandHandler(_accessibility, _shizuku);

    // Wire up event streaming: CommandHandler → WS broadcast
    _handler!.setEventSink((json) => _server.broadcastString(json));

    await _server.start(
      port: WebSocketServer.defaultPort,
      handler: (cmd) async => await _handler!.handle(cmd),
    );
  }

  Future<void> stopServer() async {
    if (!_server.isRunning) return;
    await _server.stop();
  }

  // ========================
  // PERMISSION HELPERS (use lifecycle channel)
  // ========================

  Future<void> openAppInfo() async {
    try {
      await _lifecycleChannel.invokeMethod('openAppInfo');
    } catch (e) {
      try {
        await _lifecycleChannel.invokeMethod('openSettings', {
          'action': 'APPLICATION_DETAILS_SETTINGS',
          'data': 'package:com.hermes.plugin',
        });
      } catch (e2) {}
    }
  }

  Future<bool> isNotificationPermissionGranted() async {
    try {
      return await _lifecycleChannel.invokeMethod('checkNotificationPermission') ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      return await _lifecycleChannel.invokeMethod('requestNotificationPermission') ?? false;
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
