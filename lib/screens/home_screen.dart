import 'dart:async';
import 'package:flutter/material.dart';
import '../services/websocket_server.dart';
import '../services/accessibility_bridge.dart';
import '../services/shizuku_service.dart';
import '../services/command_handler.dart';
import '../models/command.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebSocketServer _server = WebSocketServer();
  final AccessibilityBridge _accessibility = AccessibilityBridge();
  final ShizukuService _shizuku = ShizukuService();
  late CommandHandler _handler;

  bool _serverRunning = false;
  bool _accessibilityEnabled = false;
  bool _shizukuConnected = false;
  bool _shizukuAuthorized = false;
  int _clientCount = 0;
  final List<String> _logs = [];
  StreamSubscription<ServerEvent>? _serverSub;

  @override
  void initState() {
    super.initState();
    _handler = CommandHandler(_accessibility, _shizuku);
    _initServices();
  }

  Future<void> _initServices() async {
    // Check accessibility
    _accessibilityEnabled = await _accessibility.isEnabled();

    // Check Shizuku
    await _shizuku.init();
    _shizukuConnected = _shizuku.isConnected;
    _shizukuAuthorized = _shizuku.isAuthorized;

    // Start server
    await _startServer();

    setState(() {});
  }

  Future<void> _startServer() async {
    _serverSub = _server.events.listen((event) {
      setState(() {
        switch (event.type) {
          case 'started':
            _serverRunning = true;
            _addLog('Server started on port ${event.port}');
            break;
          case 'stopped':
            _serverRunning = false;
            _addLog('Server stopped');
            break;
          case 'client_connected':
            _clientCount = _server.clientCount;
            _addLog('Client connected: ${event.clientId}');
            break;
          case 'client_disconnected':
            _clientCount = _server.clientCount;
            _addLog('Client disconnected: ${event.clientId}');
            break;
          case 'error':
            _addLog('Server error: ${event.error}');
            break;
        }
      });
    });

    try {
      await _server.start(
        port: WebSocketServer.defaultPort,
        handler: (cmd) async {
          _addLog('← ${cmd.command} (${cmd.id.substring(0, 8)}...)');
          final response = await _handler.handle(cmd);
          _addLog('→ ${response.success ? "OK" : "FAIL"} (${cmd.id.substring(0, 8)}...)');
          return response;
        },
      );
    } catch (e) {
      _addLog('Failed to start server: $e');
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    _server.stop();
    _accessibility.dispose();
    _shizuku.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes Plugin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusCards(),
          const Divider(height: 1),
          _buildQuickActions(),
          const Divider(height: 1),
          Expanded(child: _buildLogPanel()),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statusCard(
                'WebSocket Server',
                _serverRunning ? 'Running' : 'Stopped',
                _serverRunning ? Colors.green : Colors.red,
                Icons.wifi,
                subtitle: '127.0.0.1:${WebSocketServer.defaultPort}',
              )),
              const SizedBox(width: 8),
              Expanded(child: _statusCard(
                'Clients',
                '$_clientCount connected',
                _clientCount > 0 ? Colors.green : Colors.grey,
                Icons.devices,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statusCard(
                'Accessibility',
                _accessibilityEnabled ? 'Enabled' : 'Disabled',
                _accessibilityEnabled ? Colors.green : Colors.orange,
                Icons.accessibility_new,
                onTap: () async {
                  await _accessibility.openSettings();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _statusCard(
                'Shizuku',
                _shizukuAuthorized
                    ? 'Authorized'
                    : (_shizukuConnected ? 'Connected' : 'Not Running'),
                _shizukuAuthorized
                    ? Colors.green
                    : (_shizukuConnected ? Colors.orange : Colors.red),
                Icons.security,
                onTap: () async {
                  if (_shizukuConnected && !_shizukuAuthorized) {
                    await _shizuku.requestPermission();
                    setState(() {
                      _shizukuAuthorized = _shizuku.isAuthorized;
                    });
                  }
                },
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String title, String status, Color color, IconData icon,
      {VoidCallback? onTap, String? subtitle}) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip('Screenshot', Icons.camera_alt, () async {
                if (_shizukuAuthorized) {
                  final result = await _handler.handle(Command(
                    id: 'test_screenshot',
                    command: Commands.screenshot,
                  ));
                  _addLog('Screenshot: ${result.success ? "OK" : result.error}');
                }
              }),
              _actionChip('Home', Icons.home, () async {
                await _handler.handle(Command(
                  id: 'test_home',
                  command: Commands.pressHome,
                ));
              }),
              _actionChip('Back', Icons.arrow_back, () async {
                await _handler.handle(Command(
                  id: 'test_back',
                  command: Commands.pressBack,
                ));
              }),
              _actionChip('Recent', Icons.tab, () async {
                await _handler.handle(Command(
                  id: 'test_recent',
                  command: Commands.pressRecent,
                ));
              }),
              _actionChip('Vol +', Icons.volume_up, () async {
                await _handler.handle(Command(
                  id: 'test_volup',
                  command: Commands.volumeUp,
                ));
              }),
              _actionChip('Vol -', Icons.volume_down, () async {
                await _handler.handle(Command(
                  id: 'test_voldown',
                  command: Commands.volumeDown,
                ));
              }),
              _actionChip('Screen On', Icons.screen_lock_portrait, () async {
                await _handler.handle(Command(
                  id: 'test_screen_on',
                  command: Commands.screenOn,
                ));
              }),
              _actionChip('Screen Off', Icons.screen_lock_landscape, () async {
                await _handler.handle(Command(
                  id: 'test_screen_off',
                  command: Commands.screenOff,
                ));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                'Activity Log',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _logs.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No activity yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _logs[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _refreshStatus() async {
    _accessibilityEnabled = await _accessibility.isEnabled();
    await _shizuku.init();
    _shizukuConnected = _shizuku.isConnected;
    _shizukuAuthorized = _shizuku.isAuthorized;
    setState(() {});
  }
}
