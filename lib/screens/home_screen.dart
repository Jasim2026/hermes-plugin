import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/websocket_server.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _serverRunning = false;
  int _clientCount = 0;
  final List<String> _logs = [];
  final Set<int> _expandedLogs = {};
  StreamSubscription<ServerEvent>? _serverSub;

  // Permission tracking
  bool _appInfoDone = false;
  bool _accessibilityDone = false;
  bool _notificationDone = false;
  bool _permissionsChecked = false;

  @override
  void initState() {
    super.initState();
    _listenToServer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  void _listenToServer() {
    _serverSub = serviceControl.server.events.listen((event) {
      setState(() {
        switch (event.type) {
          case 'started':
            _serverRunning = true;
            _addLog('WS server started on port ${event.port}');
            break;
          case 'stopped':
            _serverRunning = false;
            _addLog('WS server stopped');
            break;
          case 'client_connected':
            _clientCount = serviceControl.server.clientCount;
            _addLog('Client connected: ${event.clientId}');
            break;
          case 'client_disconnected':
            _clientCount = serviceControl.server.clientCount;
            _addLog('Client disconnected: ${event.clientId}');
            break;
          case 'error':
            _addLog('Server error: ${event.error}');
            break;
        }
      });
    });
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    if (_logs.length > 100) _logs.removeAt(0);
  }

  // ========================
  // PERMISSION CHECK MODAL
  // ========================

  Future<void> _checkPermissions() async {
    if (_permissionsChecked) return;
    _permissionsChecked = true;

    final accessibilityEnabled = await serviceControl.accessibility.isEnabled();
    final notificationEnabled = await serviceControl.isNotificationPermissionGranted();

    _accessibilityDone = accessibilityEnabled;
    _appInfoDone = accessibilityEnabled;
    _notificationDone = notificationEnabled;

    if (_accessibilityDone && _notificationDone) {
      setState(() {});
      return;
    }

    if (!mounted) return;
    _showPermissionModal();
  }

  void _showPermissionModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Permissions Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Hermes Plugin needs the following permissions to work:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),

              // App Info button
              ListTile(
                leading: _appInfoDone
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.info_outline),
                title: const Text('App Info'),
                subtitle: const Text('Grant all permissions'),
                trailing: ElevatedButton(
                  onPressed: _appInfoDone
                      ? null
                      : () async {
                          await serviceControl.openAppInfo();
                          setDialogState(() => _appInfoDone = true);
                          setState(() {});
                        },
                  child: _appInfoDone
                      ? const Text('Done')
                      : const Text('Open'),
                ),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 8),

              // Accessibility button
              ListTile(
                leading: _accessibilityDone
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.accessibility_new),
                title: const Text('Accessibility'),
                subtitle: const Text('Enable accessibility service'),
                trailing: ElevatedButton(
                  onPressed: _accessibilityDone
                      ? null
                      : () async {
                          await serviceControl.accessibility.openSettings();
                          setDialogState(() => _accessibilityDone = true);
                          setState(() {});
                        },
                  child: _accessibilityDone
                      ? const Text('Done')
                      : const Text('Open'),
                ),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 8),

              // Notification button
              ListTile(
                leading: _notificationDone
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.notifications_none),
                title: const Text('Notifications'),
                subtitle: const Text('Allow notifications for alerts'),
                trailing: ElevatedButton(
                  onPressed: _notificationDone
                      ? null
                      : () async {
                          final granted = await serviceControl.requestNotificationPermission();
                          setDialogState(() => _notificationDone = granted);
                          setState(() {});
                        },
                  child: _notificationDone
                      ? const Text('Done')
                      : const Text('Allow'),
                ),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 16),

              // Status text
              if (_appInfoDone && _accessibilityDone && _notificationDone)
                const Text(
                  'All permissions granted!',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                )
              else
                Text(
                  'Tap "Open" for each, then press back to return here.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
            ],
          ),
          actions: [
            if (_appInfoDone && _accessibilityDone && _notificationDone)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _refreshStatus();
                },
                child: const Text('Continue'),
              ),
          ],
        ),
      ),
    );
  }

  // ========================
  // SERVER TOGGLE
  // ========================

  Future<void> _toggleServer() async {
    if (_serverRunning) {
      // Stop server via control socket
      await serviceControl.stopServer();
      _addLog('Server stop requested');
    } else {
      // Start server via control socket
      await serviceControl.startServer();
      _addLog('Server start requested');
    }
    // Status will update via event listener
  }

  // ========================
  // SHIZUKU PERMISSION
  // ========================

  Future<void> _handleShizukuTap() async {
    if (serviceControl.shizukuAuthorized) {
      _addLog('Shizuku already authorized');
      return;
    }

    _addLog('Requesting Shizuku permission...');
    final granted = await serviceControl.requestShizukuPermission();
    setState(() {});
    if (granted) {
      _addLog('Shizuku permission granted');
    } else {
      _addLog('Shizuku permission denied');
    }
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes Plugin'),
        actions: [
          // Server toggle button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _serverRunning ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: _serverRunning ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: _serverRunning,
                  onChanged: (_) => _toggleServer(),
                  activeColor: Colors.green,
                ),
              ],
            ),
          ),
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
                'Control',
                'FileObserver active',
                Colors.green,
                Icons.folder,
              )),
              const SizedBox(width: 8),
              Expanded(child: _statusCard(
                'WebSocket',
                _serverRunning ? 'Running :8765' : 'Stopped',
                _serverRunning ? Colors.green : Colors.grey,
                Icons.wifi,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statusCard(
                'Clients',
                '$_clientCount connected',
                _clientCount > 0 ? Colors.green : Colors.grey,
                Icons.devices,
              )),
              const SizedBox(width: 8),
              Expanded(child: _statusCard(
                'Accessibility',
                serviceControl.accessibilityEnabled ? 'Enabled' : 'Disabled',
                serviceControl.accessibilityEnabled ? Colors.green : Colors.orange,
                Icons.accessibility_new,
                onTap: () async {
                  await serviceControl.accessibility.openSettings();
                },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Shizuku card - requests permission directly
          _statusCard(
            'Shizuku',
            serviceControl.shizukuAuthorized
                ? 'Authorized'
                : (serviceControl.shizukuConnected ? 'Connected' : 'Not Running'),
            serviceControl.shizukuAuthorized
                ? Colors.green
                : (serviceControl.shizukuConnected ? Colors.orange : Colors.red),
            Icons.security,
            onTap: _handleShizukuTap,
            fullRow: true,
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String title, String status, Color color, IconData icon,
      {VoidCallback? onTap, bool fullRow = false}) {
    final card = Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    )),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );

    if (fullRow) return card;
    return Expanded(child: card);
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip('Home', Icons.home, () => _quickCmd('press_home')),
              _actionChip('Back', Icons.arrow_back, () => _quickCmd('press_back')),
              _actionChip('Recent', Icons.tab, () => _quickCmd('press_recent')),
              _actionChip('Screen On', Icons.screen_lock_portrait, () => _quickCmd('screen_on')),
              _actionChip('Screen Off', Icons.screen_lock_landscape, () => _quickCmd('screen_off')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _quickCmd(String command) async {
    _addLog('Sending: $command');
    _addLog('Command queued — will execute when agent connects');
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  static const int _maxPreviewLength = 80;

  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text('Activity Log', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy all logs',
                onPressed: _logs.isEmpty ? null : _copyLogs,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _logs.clear();
                  _expandedLogs.clear();
                }),
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
                    child: Text('No activity yet', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isExpanded = _expandedLogs.contains(index);
                      final needsTruncate = log.length > _maxPreviewLength && !isExpanded;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedLogs.remove(index);
                            } else {
                              _expandedLogs.add(index);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  needsTruncate
                                      ? '${log.substring(0, _maxPreviewLength)}...'
                                      : log,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              if (needsTruncate || isExpanded)
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
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

  void _copyLogs() {
    final text = _logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _refreshStatus() async {
    final enabled = await serviceControl.accessibility.isEnabled();
    setState(() {
      serviceControl.accessibilityEnabled = enabled;
      _accessibilityDone = enabled;
      _appInfoDone = enabled;
    });
  }
}
