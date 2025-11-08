import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// UDP Discovery Service for finding HIMS LAN server
/// Listens for server announcements and handles discovery requests
class DiscoveryService extends ChangeNotifier {
  RawDatagramSocket? _socket;
  Timer? _discoveryTimer;
  ServerInfo? _serverInfo;
  bool _isDiscovering = false;

  static const int UDP_PORT = 9999;
  static const Duration DISCOVERY_INTERVAL = Duration(seconds: 5);
  static const Duration DISCOVERY_TIMEOUT = Duration(seconds: 30);

  ServerInfo? get serverInfo => _serverInfo;
  bool get isDiscovering => _isDiscovering;
  bool get isServerAvailable => _serverInfo != null;

  /// Initialize discovery service
  Future<void> initialize() async {
    try {
      // Bind to UDP port for receiving broadcasts
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, UDP_PORT);
      _socket!.broadcastEnabled = true;

      debugPrint('Discovery service initialized on port $UDP_PORT');

      // Listen for incoming messages
      _socket!.listen(_handleMessage, onError: _handleError);
    } catch (e) {
      debugPrint('Failed to initialize discovery service: $e');
      rethrow;
    }
  }

  /// Start discovering servers
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      debugPrint('Discovery already in progress');
      return;
    }

    _isDiscovering = true;
    notifyListeners();

    debugPrint('Starting server discovery...');

    // Send discovery request immediately
    await sendDiscoveryRequest();

    // Set up periodic discovery requests
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(DISCOVERY_INTERVAL, (_) {
      sendDiscoveryRequest();
    });

    // Set timeout
    Future.delayed(DISCOVERY_TIMEOUT, () {
      if (_isDiscovering && _serverInfo == null) {
        debugPrint('Discovery timeout - no server found');
        stopDiscovery();
      }
    });
  }

  /// Stop discovering servers
  void stopDiscovery() {
    _isDiscovering = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    notifyListeners();
    debugPrint('Discovery stopped');
  }

  /// Send discovery request broadcast
  Future<void> sendDiscoveryRequest() async {
    if (_socket == null) {
      debugPrint('Socket not initialized');
      return;
    }

    try {
      final message = {
        'type': 'HIMS_DISCOVERY_REQUEST',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final data = utf8.encode(json.encode(message));
      final broadcast = InternetAddress('255.255.255.255');

      _socket!.send(data, broadcast, UDP_PORT);
      debugPrint('Discovery request sent');
    } catch (e) {
      debugPrint('Failed to send discovery request: $e');
    }
  }

  /// Handle incoming UDP messages
  void _handleMessage(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _socket!.receive();
      if (datagram == null) return;

      try {
        final message = json.decode(utf8.decode(datagram.data));
        final messageType = message['type'] as String?;

        switch (messageType) {
          case 'HIMS_SERVER_ANNOUNCEMENT':
            _handleServerAnnouncement(message, datagram.address);
            break;

          case 'HIMS_DISCOVERY_RESPONSE':
            _handleDiscoveryResponse(message, datagram.address);
            break;

          case 'HIMS_DATA_CHANGE':
            _handleDataChangeNotification(message);
            break;

          case 'HIMS_STATUS_REQUEST':
            _handleStatusRequest(datagram.address);
            break;

          default:
            debugPrint('Unknown message type: $messageType');
        }
      } catch (e) {
        debugPrint('Failed to parse UDP message: $e');
      }
    }
  }

  /// Handle server announcement
  void _handleServerAnnouncement(Map<String, dynamic> message, InternetAddress address) {
    final serverIp = message['serverIp'] as String? ?? address.address;
    final serverPort = message['serverPort'] as int? ?? 5000;
    final serverName = message['serverName'] as String? ?? 'HIMS-LAN-Server';
    final version = message['version'] as String? ?? '1.0.0';
    final timestamp = message['timestamp'] as String?;
    final capabilities = List<String>.from(message['capabilities'] ?? []);

    _updateServerInfo(ServerInfo(
      ip: serverIp,
      port: serverPort,
      name: serverName,
      version: version,
      lastSeen: DateTime.now(),
      capabilities: capabilities,
    ));

    debugPrint('Server announcement received from $serverIp:$serverPort');
  }

  /// Handle discovery response
  void _handleDiscoveryResponse(Map<String, dynamic> message, InternetAddress address) {
    final serverIp = message['serverIp'] as String? ?? address.address;
    final serverPort = message['serverPort'] as int? ?? 5000;
    final serverName = message['serverName'] as String? ?? 'HIMS-LAN-Server';
    final version = message['version'] as String? ?? '1.0.0';

    _updateServerInfo(ServerInfo(
      ip: serverIp,
      port: serverPort,
      name: serverName,
      version: version,
      lastSeen: DateTime.now(),
      capabilities: ['sync', 'inventory', 'transactions', 'suppliers'],
    ));

    debugPrint('Discovery response received from $serverIp:$serverPort');

    // Stop active discovery when server is found
    if (_isDiscovering) {
      stopDiscovery();
    }
  }

  /// Handle data change notification from server
  void _handleDataChangeNotification(Map<String, dynamic> message) {
    final changeType = message['changeType'] as String?;
    final changeData = message['changeData'];

    debugPrint('Data change notification: $changeType');

    // Trigger sync when notified of changes
    // This will be handled by SyncService listening to this event
    notifyListeners();
  }

  /// Handle status request from server
  void _handleStatusRequest(InternetAddress serverAddress) {
    try {
      final response = {
        'type': 'HIMS_STATUS_RESPONSE',
        'status': 'online',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final data = utf8.encode(json.encode(response));
      _socket!.send(data, serverAddress, UDP_PORT);

      debugPrint('Status response sent to server');
    } catch (e) {
      debugPrint('Failed to send status response: $e');
    }
  }

  /// Update server info and notify listeners
  void _updateServerInfo(ServerInfo info) {
    _serverInfo = info;
    notifyListeners();
  }

  /// Handle socket errors
  void _handleError(dynamic error) {
    debugPrint('Discovery service error: $error');
  }

  /// Get base URL for HTTP requests
  String? getServerBaseUrl() {
    if (_serverInfo == null) return null;
    return 'http://${_serverInfo!.ip}:${_serverInfo!.port}';
  }

  /// Check if server is still alive
  bool isServerAlive({Duration timeout = const Duration(seconds: 30)}) {
    if (_serverInfo == null) return false;
    final timeSinceLastSeen = DateTime.now().difference(_serverInfo!.lastSeen);
    return timeSinceLastSeen < timeout;
  }

  /// Manually set server info (for testing or manual configuration)
  void setServerInfo(String ip, int port) {
    _updateServerInfo(ServerInfo(
      ip: ip,
      port: port,
      name: 'HIMS-LAN-Server',
      version: '1.0.0',
      lastSeen: DateTime.now(),
      capabilities: ['sync', 'inventory', 'transactions', 'suppliers'],
    ));

    debugPrint('Server info manually set: $ip:$port');
  }

  /// Dispose resources
  @override
  void dispose() {
    stopDiscovery();
    _socket?.close();
    _socket = null;
    super.dispose();
  }
}

/// Server information model
class ServerInfo {
  final String ip;
  final int port;
  final String name;
  final String version;
  final DateTime lastSeen;
  final List<String> capabilities;

  ServerInfo({
    required this.ip,
    required this.port,
    required this.name,
    required this.version,
    required this.lastSeen,
    required this.capabilities,
  });

  String get baseUrl => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'name': name,
        'version': version,
        'lastSeen': lastSeen.toIso8601String(),
        'capabilities': capabilities,
      };

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      ip: json['ip'] as String,
      port: json['port'] as int,
      name: json['name'] as String,
      version: json['version'] as String,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      capabilities: List<String>.from(json['capabilities'] ?? []),
    );
  }

  @override
  String toString() => 'ServerInfo($name @ $ip:$port, v$version)';
}
