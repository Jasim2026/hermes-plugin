import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_plugin/models/command.dart';

void main() {
  group('Command', () {
    test('parses from JSON', () {
      final json = {
        'id': 'test-123',
        'command': 'tap',
        'params': {'x': 100.0, 'y': 200.0},
      };

      final command = Command.fromJson(json);

      expect(command.id, 'test-123');
      expect(command.command, 'tap');
      expect(command.params['x'], 100.0);
      expect(command.params['y'], 200.0);
    });

    test('serializes to JSON', () {
      final command = Command(
        id: 'test-456',
        command: 'scroll',
        params: {'direction': 'down', 'distance': 500.0},
      );

      final json = command.toJson();

      expect(json['id'], 'test-456');
      expect(json['command'], 'scroll');
      expect(json['params']['direction'], 'down');
    });

    test('handles empty params', () {
      final command = Command(id: 'test', command: 'ping');
      expect(command.params, isEmpty);
    });
  });

  group('CommandResponse', () {
    test('serializes success response', () {
      final response = CommandResponse(
        id: 'test-123',
        success: true,
        data: {'tapped': true},
      );

      final json = response.toJson();

      expect(json['id'], 'test-123');
      expect(json['success'], true);
      expect(json['data']['tapped'], true);
      expect(json.containsKey('error'), false);
    });

    test('serializes error response', () {
      final response = CommandResponse(
        id: 'test-456',
        success: false,
        error: 'Something went wrong',
      );

      final json = response.toJson();

      expect(json['id'], 'test-456');
      expect(json['success'], false);
      expect(json['error'], 'Something went wrong');
      expect(json.containsKey('data'), false);
    });
  });

  group('Commands constants', () {
    test('all commands are defined', () {
      expect(Commands.screenshot, 'screenshot');
      expect(Commands.tap, 'tap');
      expect(Commands.longPress, 'long_press');
      expect(Commands.swipe, 'swipe');
      expect(Commands.scroll, 'scroll');
      expect(Commands.typeText, 'type_text');
      expect(Commands.pressBack, 'press_back');
      expect(Commands.pressHome, 'press_home');
      expect(Commands.pressRecent, 'press_recent');
      expect(Commands.volumeUp, 'volume_up');
      expect(Commands.volumeDown, 'volume_down');
      expect(Commands.setVolume, 'set_volume');
      expect(Commands.setMode, 'set_mode');
      expect(Commands.screenOn, 'screen_on');
      expect(Commands.screenOff, 'screen_off');
      expect(Commands.openApp, 'open_app');
      expect(Commands.getScreenContent, 'get_screen_content');
      expect(Commands.findElement, 'find_element');
      expect(Commands.clickElement, 'click_element');
      expect(Commands.getDeviceInfo, 'get_device_info');
      expect(Commands.getInstalledApps, 'get_installed_apps');
      expect(Commands.ping, 'ping');
    });
  });
}
