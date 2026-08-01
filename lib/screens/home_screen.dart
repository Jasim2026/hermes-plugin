import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../models/command.dart';
import '../services/websocket_server.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _serverRunning = false;
  int _clientCount = 0;
  final List<String> _logs = [];
  final Set<int> _expandedLogs = {};
  StreamSubscription<ServerEvent>? _serverSub;

  // Permission tracking
  bool _appInfoDone = false;
  bool _accessibilityDone = false;
  bool _notificationDone = false;
  bool _shizukuDone = false;
  bool _permissionModalDismissed = false;

  // Colors
  static const _bg = Color(0xFF0A0A10);
  static const _cardBg = Color(0xFF16162A);
  static const _borderColor = Color(0xFF252540);
  static const _accent = Color(0xFF6C5CE7);
  static const _accentLight = Color(0xFFA29BFE);
  static const _green = Color(0xFF00E676);
  static const _orange = Color(0xFFFF9100);
  static const _red = Color(0xFFFF5252);
  static const _textPrimary = Color(0xFFF5F5F7);
  static const _textSecondary = Color(0xFF8E8EA0);
  static const _textTertiary = Color(0xFF555570);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToServer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _refreshStatus();
    }
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
    final accessibilityEnabled = await serviceControl.accessibility.isEnabled();
    final notificationEnabled = await serviceControl.isNotificationPermissionGranted();
    final shizukuAuthorized = await serviceControl.shizukuService.checkPermission();

    _accessibilityDone = accessibilityEnabled;
    _appInfoDone = accessibilityEnabled;
    _notificationDone = notificationEnabled;
    _shizukuDone = shizukuAuthorized;

    final allRequiredDone = _appInfoDone && _accessibilityDone && _notificationDone;

    if (allRequiredDone) {
      _permissionModalDismissed = false;
      setState(() {});
      return;
    }

    if (!mounted) return;
    if (_permissionModalDismissed) {
      setState(() {});
      return;
    }
    _showPermissionModal();
  }

  void _showPermissionModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: _accent, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Setup Required',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Grant the permissions below to continue.',
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 20),

                  // Permission items
                  _permItem(setDialogState, 'Accessibility', 'Required for gestures & UI control',
                      Icons.accessibility_new, _accessibilityDone,
                      onTap: () async {
                    await serviceControl.accessibility.openSettings();
                    setDialogState(() => _accessibilityDone = true);
                  }),
                  const SizedBox(height: 8),
                  _permItem(setDialogState, 'Notifications', 'Required for alerts',
                      Icons.notifications_outlined, _notificationDone,
                      onTap: () async {
                    final granted = await serviceControl.requestNotificationPermission();
                    setDialogState(() => _notificationDone = granted);
                  }),
                  const SizedBox(height: 8),
                  _permItem(setDialogState, 'Shizuku', 'Optional — root-level access',
                      Icons.security_outlined, _shizukuDone,
                      onTap: () async {
                    final granted = await serviceControl.requestShizukuPermission();
                    setDialogState(() => _shizukuDone = granted);
                  }),

                  const SizedBox(height: 24),

                  // Continue button
                  if (_appInfoDone && _accessibilityDone && _notificationDone)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          _permissionModalDismissed = true;
                          Navigator.of(ctx).pop();
                          _refreshStatus();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Accessibility & Notifications are required.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _permItem(StateSetter setDialogState, String title, String subtitle,
      IconData icon, bool done, {VoidCallback? onTap}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: done ? _green.withOpacity(0.08) : _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? _green.withOpacity(0.3) : _borderColor,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: done ? _green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: done ? _green : _textSecondary, size: 18),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: _textTertiary),
        ),
        trailing: done
            ? const Icon(Icons.check_circle, color: _green, size: 20)
            : TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  backgroundColor: _accent.withOpacity(0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Grant',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );
  }

  // ========================
  // SERVER TOGGLE
  // ========================

  Future<void> _toggleServer() async {
    if (_serverRunning) {
      await serviceControl.stopServer();
      setState(() {
        _serverRunning = false;
        _clientCount = 0;
      });
      _addLog('Server stopped');
    } else {
      _addLog('Starting WebSocket server...');
      await serviceControl.startServer();
    }
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
    _addLog(granted ? 'Shizuku permission granted' : 'Shizuku permission denied');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverSub?.cancel();
    super.dispose();
  }

  // ========================
  // BUILD
  // ========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accent, _accentLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Hermes',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          // Server toggle
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _toggleServer,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _serverRunning
                      ? _green.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _serverRunning
                        ? _green.withOpacity(0.4)
                        : _borderColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _serverRunning ? _green : _textTertiary,
                        shape: BoxShape.circle,
                        boxShadow: _serverRunning
                            ? [BoxShadow(color: _green.withOpacity(0.5), blurRadius: 6)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _serverRunning ? 'ON' : 'OFF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _serverRunning ? _green : _textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _textSecondary, size: 20),
            onPressed: _refreshStatus,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildStatusSection(),
          const SizedBox(height: 4),
          _buildQuickActions(),
          const SizedBox(height: 4),
          Expanded(child: _buildLogPanel()),
        ],
      ),
    );
  }

  // ========================
  // STATUS SECTION
  // ========================

  Widget _buildStatusSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          // Top row: WebSocket + Clients
          Row(
            children: [
              _statusPill(
                'WebSocket',
                _serverRunning ? ':8765' : 'Off',
                _serverRunning ? _green : _textTertiary,
                Icons.wifi_outlined,
              ),
              const SizedBox(width: 8),
              _statusPill(
                'Clients',
                '$_clientCount',
                _clientCount > 0 ? _accent : _textTertiary,
                Icons.devices_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bottom row: Accessibility + Shizuku
          Row(
            children: [
              _statusPill(
                'Accessibility',
                serviceControl.accessibilityEnabled ? 'Active' : 'Off',
                serviceControl.accessibilityEnabled ? _green : _orange,
                Icons.accessibility_new_outlined,
                onTap: () => serviceControl.accessibility.openSettings(),
              ),
              const SizedBox(width: 8),
              _statusPill(
                'Shizuku',
                serviceControl.shizukuAuthorized ? 'Granted' : 'Off',
                serviceControl.shizukuAuthorized ? _green : _red,
                Icons.security_outlined,
                onTap: _handleShizukuTap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, String value, Color color, IconData icon,
      {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor, width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _textTertiary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: _textTertiary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ========================
  // QUICK ACTIONS
  // ========================

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _actionBtn('Home', Icons.home_rounded, () => _quickCmd('press_home')),
                _actionBtn('Back', Icons.arrow_back_rounded, () => _quickCmd('press_back')),
                _actionBtn('Recent', Icons.tab_rounded, () => _quickCmd('press_recent')),
                _actionBtn('Vol +', Icons.volume_up_rounded, () => _quickCmd('volume_up')),
                _actionBtn('Vol -', Icons.volume_down_rounded, () => _quickCmd('volume_down')),
                _actionBtn('On', Icons.screen_lock_portrait_rounded, () => _quickCmd('screen_on')),
                _actionBtn('Off', Icons.screen_lock_landscape_rounded, () => _quickCmd('screen_off')),
                _actionBtn('Capture', Icons.camera_alt_rounded, () => _quickCmd('screenshot_cached')),
                _actionBtn('Scroll ↓', Icons.keyboard_arrow_down_rounded, () => _quickCmdWithParams('scroll', {'direction': 'down'})),
                _actionBtn('Scroll ↑', Icons.keyboard_arrow_up_rounded, () => _quickCmdWithParams('scroll', {'direction': 'up'})),
                _actionBtn('Clear', Icons.backspace_rounded, () => _quickCmd('clear_input_field')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _accentLight, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickCmd(String command) async {
    _addLog('Sending: $command');
    if (!_serverRunning) {
      _addLog('Server not running — start it first');
      return;
    }
    final h = serviceControl.handler;
    if (h == null) {
      _addLog('Handler not initialized');
      return;
    }
    try {
      final cmd = Command(id: 'quick_$command', command: command);
      final response = await h.handle(cmd);
      if (response.success) {
        _addLog('OK: $command');
      } else {
        _addLog('FAIL: ${response.error}');
      }
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  Future<void> _quickCmdWithParams(String command, Map<String, dynamic> params) async {
    _addLog('Sending: $command $params');
    if (!_serverRunning) {
      _addLog('Server not running — start it first');
      return;
    }
    final h = serviceControl.handler;
    if (h == null) {
      _addLog('Handler not initialized');
      return;
    }
    try {
      final cmd = Command(
        id: 'quick_${command}_${DateTime.now().millisecondsSinceEpoch}',
        command: command,
        params: params,
      );
      final response = await h.handle(cmd);
      if (response.success) {
        _addLog('OK: $command');
      } else {
        _addLog('FAIL: ${response.error}');
      }
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  // ========================
  // LOG PANEL
  // ========================

  static const int _maxPreviewLength = 72;

  Widget _buildLogPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Activity Log',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _logs.isEmpty ? null : _copyLogs,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.copy_rounded, color: _textTertiary, size: 14),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() {
                  _logs.clear();
                  _expandedLogs.clear();
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: _textTertiary, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10101C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.terminal_rounded, color: _textTertiary.withOpacity(0.3), size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'No activity yet',
                            style: TextStyle(
                              color: _textTertiary.withOpacity(0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isExpanded = _expandedLogs.contains(index);
                        final needsTruncate = log.length > _maxPreviewLength && !isExpanded;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedLogs.remove(index);
                              } else {
                                _expandedLogs.add(index);
                              }
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            decoration: BoxDecoration(
                              color: index == _logs.length - 1
                                  ? _accent.withOpacity(0.06)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              needsTruncate
                                  ? '${log.substring(0, _maxPreviewLength)}…'
                                  : log,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: index == _logs.length - 1
                                    ? _accentLight
                                    : _textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyLogs() {
    final text = _logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Logs copied to clipboard'),
        backgroundColor: _cardBg,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshStatus() async {
    final enabled = await serviceControl.accessibility.isEnabled();
    final shizukuAuth = await serviceControl.shizukuService.checkPermission();
    setState(() {
      serviceControl.accessibilityEnabled = enabled;
      _accessibilityDone = enabled;
      _appInfoDone = enabled;
      _shizukuDone = shizukuAuth;
    });
  }
}
