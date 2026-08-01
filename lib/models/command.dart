/// Command sent from Hermes to the plugin
class Command {
  final String id;
  final String command;
  final Map<String, dynamic> params;

  Command({
    required this.id,
    required this.command,
    this.params = const {},
  });

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      id: json['id'] as String? ?? '',
      command: json['command'] as String? ?? '',
      params: Map<String, dynamic>.from(json['params'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'command': command,
        'params': params,
      };
}

/// Response sent back to Hermes
class CommandResponse {
  final String id;
  final bool success;
  final dynamic data;
  final String? error;

  CommandResponse({
    required this.id,
    required this.success,
    this.data,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
      };
}

/// Supported command types
class Commands {
  // Existing
  static const String screenshot = 'screenshot';
  static const String tap = 'tap';
  static const String longPress = 'long_press';
  static const String swipe = 'swipe';
  static const String scroll = 'scroll';
  static const String typeText = 'type_text';
  static const String pressBack = 'press_back';
  static const String pressHome = 'press_home';
  static const String pressRecent = 'press_recent';
  static const String volumeUp = 'volume_up';
  static const String volumeDown = 'volume_down';
  static const String setVolume = 'set_volume';
  static const String setMode = 'set_mode';
  static const String screenOn = 'screen_on';
  static const String screenOff = 'screen_off';
  static const String openApp = 'open_app';
  static const String getScreenContent = 'get_screen_content';
  static const String findElement = 'find_element';
  static const String clickElement = 'click_element';
  static const String getDeviceInfo = 'get_device_info';
  static const String getInstalledApps = 'get_installed_apps';
  static const String ping = 'ping';

  // Tier 1
  static const String getAppState = 'get_app_state';
  static const String getDisplayInfo = 'get_display_info';
  static const String scaleCoords = 'scale_coords';

  // Tier 2
  static const String batch = 'batch';
  static const String setWebhook = 'set_webhook';
  static const String clearWebhook = 'clear_webhook';
  static const String uiAutomatorDump = 'ui_automator_dump';
  static const String getInputMethods = 'get_input_methods';
  static const String setInputMethod = 'set_input_method';
  static const String clearInputField = 'clear_input_field';

  // Tier 3
  static const String health = 'health';
  static const String getBatteryInfo = 'get_battery_info';
  static const String streamEvents = 'stream_events';
  static const String stopStreamEvents = 'stop_stream_events';
  static const String screenshotCached = 'screenshot_cached';
}
