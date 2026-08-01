import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/command.dart';

/// Callback type for command handling
typedef CommandCallback = Future<CommandResponse> Function(Command command);

/// Local WebSocket server that Hermes connects to
class WebSocketServer {
  static const int defaultPort = 8765;
  static const String host = '127.0.0.1';

  HttpServer? _server;
  final Map<String, WebSocket> _clients = {};
  CommandCallback? _handler;
  int _port = defaultPort;
  bool _running = false;

  bool get isRunning => _running;
  int get port => _port;
  int get clientCount => _clients.length;

  final StreamController<ServerEvent> _eventController =
      StreamController<ServerEvent>.broadcast();
  Stream<ServerEvent> get events => _eventController.stream;

  /// Start the WebSocket server
  Future<void> start({int port = defaultPort, CommandCallback? handler}) async {
    _port = port;
    _handler = handler;

    try {
      _server = await HttpServer.bind(host, port);
      _running = true;
      _eventController.add(ServerEvent(type: 'started', port: port));

      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            _handleConnection(socket, request);
          });
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.text;
          request.response.write('Hermes Plugin WebSocket Server');
          request.response.close();
        }
      });
    } catch (e) {
      _running = false;
      _eventController.add(ServerEvent(type: 'error', error: e.toString()));
      rethrow;
    }
  }

  void _handleConnection(WebSocket socket, HttpRequest request) {
    final clientId = request.uri.queryParameters['client'] ??
        'client_${DateTime.now().millisecondsSinceEpoch}';

    _clients[clientId] = socket;
    _eventController.add(ServerEvent(
      type: 'client_connected',
      clientId: clientId,
    ));

    socket.listen(
      (data) async {
        try {
          final json = jsonDecode(data.toString()) as Map<String, dynamic>;
          final command = Command.fromJson(json);
          final response = await _handleCommand(command);
          socket.add(jsonEncode(response.toJson()));
        } catch (e) {
          final errorResponse = CommandResponse(
            id: '',
            success: false,
            error: 'Invalid command: $e',
          );
          socket.add(jsonEncode(errorResponse.toJson()));
        }
      },
      onDone: () {
        _clients.remove(clientId);
        _eventController.add(ServerEvent(
          type: 'client_disconnected',
          clientId: clientId,
        ));
      },
      onError: (error) {
        _clients.remove(clientId);
        _eventController.add(ServerEvent(
          type: 'client_error',
          clientId: clientId,
          error: error.toString(),
        ));
      },
    );
  }

  Future<CommandResponse> _handleCommand(Command command) async {
    if (_handler != null) {
      return await _handler!(command);
    }
    return CommandResponse(
      id: command.id,
      success: false,
      error: 'No command handler registered',
    );
  }

  /// Broadcast a message to all connected clients
  void broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final client in _clients.values) {
      client.add(encoded);
    }
  }

  /// Broadcast raw string to all clients (for streaming events, batch progress)
  void broadcastString(String json) {
    for (final client in _clients.values) {
      client.add(json);
    }
  }

  /// Stop the server
  Future<void> stop() async {
    _running = false;
    for (final client in _clients.values) {
      await client.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    _eventController.add(ServerEvent(type: 'stopped'));
  }
}

class ServerEvent {
  final String type;
  final int? port;
  final String? clientId;
  final String? error;

  ServerEvent({
    required this.type,
    this.port,
    this.clientId,
    this.error,
  });
}
