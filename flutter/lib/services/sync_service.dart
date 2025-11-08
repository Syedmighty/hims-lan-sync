import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'discovery_service.dart';

/// Sync Service for bidirectional synchronization with HIMS LAN server
/// Handles push/pull operations, conflict detection, and sync queue management
class SyncService extends ChangeNotifier {
  final DiscoveryService _discoveryService;
  final String _deviceId;

  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  List<SyncConflict> _conflicts = [];
  int _pendingChanges = 0;
  String? _lastError;

  Timer? _autoSyncTimer;
  static const Duration AUTO_SYNC_INTERVAL = Duration(minutes: 5);

  SyncService({
    required DiscoveryService discoveryService,
    String? deviceId,
  })  : _discoveryService = discoveryService,
        _deviceId = deviceId ?? const Uuid().v4() {
    // Listen to discovery service for server changes
    _discoveryService.addListener(_onDiscoveryChanged);
  }

  // Getters
  SyncStatus get syncStatus => _syncStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  List<SyncConflict> get conflicts => _conflicts;
  int get pendingChanges => _pendingChanges;
  String? get lastError => _lastError;
  String get deviceId => _deviceId;

  /// Start automatic sync
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(AUTO_SYNC_INTERVAL, (_) {
      if (_discoveryService.isServerAvailable) {
        performFullSync();
      }
    });
    debugPrint('Auto-sync started with ${AUTO_SYNC_INTERVAL.inMinutes}min interval');
  }

  /// Stop automatic sync
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    debugPrint('Auto-sync stopped');
  }

  /// Handle discovery service changes
  void _onDiscoveryChanged() {
    if (_discoveryService.isServerAvailable && _pendingChanges > 0) {
      // Server became available and we have pending changes
      debugPrint('Server available, triggering sync');
      performFullSync();
    }
  }

  /// Perform full bidirectional sync (push + pull)
  Future<SyncResult> performFullSync() async {
    if (_syncStatus == SyncStatus.syncing) {
      debugPrint('Sync already in progress');
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    _setSyncStatus(SyncStatus.syncing);
    _lastError = null;

    try {
      // Check server availability
      if (!_discoveryService.isServerAvailable) {
        throw Exception('Server not available');
      }

      final baseUrl = _discoveryService.getServerBaseUrl();
      if (baseUrl == null) {
        throw Exception('Server URL not available');
      }

      // Perform batch sync (combined push and pull)
      final result = await _performBatchSync(baseUrl);

      _lastSyncTime = DateTime.now();
      _setSyncStatus(SyncStatus.completed);

      debugPrint('Full sync completed successfully');
      return result;
    } catch (e) {
      debugPrint('Full sync failed: $e');
      _lastError = e.toString();
      _setSyncStatus(SyncStatus.error);
      return SyncResult(success: false, message: e.toString());
    }
  }

  /// Perform batch sync (push + pull in one request)
  Future<SyncResult> _performBatchSync(String baseUrl) async {
    try {
      // Get local changes for push
      final localChanges = await _getLocalChanges();

      // Prepare pull query
      final pullQuery = {
        'lastSyncTimestamp': _lastSyncTime?.toIso8601String() ?? '0',
        'entityTypes': ['inventory_items', 'transactions', 'suppliers'],
      };

      // Build batch request
      final requestBody = {
        'pushPayload': {
          'changes': localChanges,
        },
        'pullQuery': pullQuery,
      };

      // Send batch request
      final response = await http
          .post(
            Uri.parse('$baseUrl/sync/batch'),
            headers: {
              'Content-Type': 'application/json',
              'deviceId': _deviceId,
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        // Process push result
        if (result['data']['push'] != null) {
          await _processPushResult(result['data']['push']);
        }

        // Process pull result
        if (result['data']['pull'] != null) {
          await _processPullResult(result['data']['pull']);
        }

        return SyncResult(
          success: true,
          message: 'Batch sync completed',
          data: result['data'],
        );
      } else {
        throw Exception('Batch sync failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Batch sync error: $e');
      rethrow;
    }
  }

  /// Push local changes to server
  Future<SyncResult> pushChanges() async {
    if (!_discoveryService.isServerAvailable) {
      throw Exception('Server not available');
    }

    final baseUrl = _discoveryService.getServerBaseUrl()!;

    try {
      final localChanges = await _getLocalChanges();

      if (localChanges.isEmpty) {
        debugPrint('No local changes to push');
        return SyncResult(success: true, message: 'No changes to push');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/sync/push'),
            headers: {
              'Content-Type': 'application/json',
              'deviceId': _deviceId,
            },
            body: json.encode({
              'changes': localChanges,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        await _processPushResult(result);

        return SyncResult(
          success: true,
          message: 'Push completed',
          data: result['data'],
        );
      } else {
        throw Exception('Push failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Push error: $e');
      rethrow;
    }
  }

  /// Pull changes from server
  Future<SyncResult> pullChanges() async {
    if (!_discoveryService.isServerAvailable) {
      throw Exception('Server not available');
    }

    final baseUrl = _discoveryService.getServerBaseUrl()!;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/sync/pull'),
            headers: {
              'Content-Type': 'application/json',
              'deviceId': _deviceId,
            },
            body: json.encode({
              'lastSyncTimestamp': _lastSyncTime?.toIso8601String() ?? '0',
              'entityTypes': ['inventory_items', 'transactions', 'suppliers'],
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        await _processPullResult(result);

        return SyncResult(
          success: true,
          message: 'Pull completed',
          data: result['data'],
        );
      } else {
        throw Exception('Pull failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Pull error: $e');
      rethrow;
    }
  }

  /// Process push result from server
  Future<void> _processPushResult(Map<String, dynamic> result) async {
    final recordsProcessed = result['recordsProcessed'] as int? ?? 0;
    final conflictsDetected = result['conflictsDetected'] as int? ?? 0;
    final conflicts = result['conflicts'] as List? ?? [];

    debugPrint('Push result: $recordsProcessed records, $conflictsDetected conflicts');

    // Update conflicts list
    if (conflicts.isNotEmpty) {
      _conflicts.addAll(
        conflicts.map((c) => SyncConflict.fromJson(c as Map<String, dynamic>)),
      );
      notifyListeners();
    }

    // Mark pushed records as synced in local DB
    final processedRecords = result['processedRecords'] as List? ?? [];
    for (final record in processedRecords) {
      if (record['status'] == 'created' ||
          record['status'] == 'updated' ||
          record['status'] == 'deleted') {
        await _markRecordAsSynced(record['uuid'] as String);
      }
    }

    // Update pending changes count
    await _updatePendingChangesCount();
  }

  /// Process pull result from server
  Future<void> _processPullResult(Map<String, dynamic> result) async {
    final changes = result['changes'] as List? ?? [];
    debugPrint('Pull result: ${changes.length} changes received');

    // Apply changes to local database
    for (final change in changes) {
      await _applyServerChange(change as Map<String, dynamic>);
    }

    // Update sync timestamp from server
    final syncTimestamp = result['syncTimestamp'] as String?;
    if (syncTimestamp != null) {
      _lastSyncTime = DateTime.parse(syncTimestamp);
    }

    notifyListeners();
  }

  /// Get local changes that need to be synced
  /// This should query your local Drift database for unsynced records
  Future<List<Map<String, dynamic>>> _getLocalChanges() async {
    // TODO: Implement actual Drift database query
    // This is a placeholder - replace with actual Drift DB query
    // Example:
    // final db = await database;
    // final items = await db.inventoryItems.where((tbl) => tbl.isSynced.equals(false)).get();
    // return items.map((item) => _itemToSyncChange(item)).toList();

    debugPrint('Getting local changes (placeholder implementation)');
    return [];
  }

  /// Apply server change to local database
  /// This should update your local Drift database
  Future<void> _applyServerChange(Map<String, dynamic> change) async {
    // TODO: Implement actual Drift database update
    // This is a placeholder - replace with actual Drift DB operations
    // Example:
    // final uuid = change['uuid'] as String;
    // final entityType = change['entityType'] as String;
    // final operation = change['operation'] as String;
    // final data = change['data'];
    //
    // if (operation == 'delete') {
    //   await _deleteLocalRecord(entityType, uuid);
    // } else {
    //   await _upsertLocalRecord(entityType, data);
    // }

    debugPrint('Applying server change: ${change['operation']} ${change['entityType']}/${change['uuid']}');
  }

  /// Mark record as synced in local database
  Future<void> _markRecordAsSynced(String uuid) async {
    // TODO: Implement actual Drift database update
    debugPrint('Marking record as synced: $uuid');
  }

  /// Update pending changes count from local database
  Future<void> _updatePendingChangesCount() async {
    // TODO: Query Drift database for count of unsynced records
    _pendingChanges = 0; // Placeholder
    notifyListeners();
  }

  /// Get sync status from server
  Future<Map<String, dynamic>?> getSyncStatus() async {
    if (!_discoveryService.isServerAvailable) {
      return null;
    }

    final baseUrl = _discoveryService.getServerBaseUrl()!;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sync/status'),
        headers: {'deviceId': _deviceId},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['data'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Failed to get sync status: $e');
    }

    return null;
  }

  /// Get conflicts from server
  Future<List<SyncConflict>> fetchConflicts() async {
    if (!_discoveryService.isServerAvailable) {
      return [];
    }

    final baseUrl = _discoveryService.getServerBaseUrl()!;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conflicts'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final conflicts = result['data']['conflicts'] as List? ?? [];

        _conflicts = conflicts
            .map((c) => SyncConflict.fromJson(c as Map<String, dynamic>))
            .toList();

        notifyListeners();
        return _conflicts;
      }
    } catch (e) {
      debugPrint('Failed to fetch conflicts: $e');
    }

    return [];
  }

  /// Resolve a conflict
  Future<bool> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
    Map<String, dynamic>? customData,
  ) async {
    if (!_discoveryService.isServerAvailable) {
      return false;
    }

    final baseUrl = _discoveryService.getServerBaseUrl()!;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/conflicts/$conflictId/resolve'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'choice': resolution.name,
          'resolvedBy': _deviceId,
          if (customData != null) 'customData': customData,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Remove resolved conflict from local list
        _conflicts.removeWhere((c) => c.conflictId == conflictId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Failed to resolve conflict: $e');
    }

    return false;
  }

  /// Set sync status
  void _setSyncStatus(SyncStatus status) {
    _syncStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    stopAutoSync();
    _discoveryService.removeListener(_onDiscoveryChanged);
    super.dispose();
  }
}

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  completed,
  error,
}

/// Conflict resolution options
enum ConflictResolution {
  server, // Keep server version
  client, // Keep client version
  custom, // Use custom merged data
}

/// Sync result model
class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  SyncResult({
    required this.success,
    required this.message,
    this.data,
  });
}

/// Sync conflict model
class SyncConflict {
  final String conflictId;
  final String entityType;
  final String entityUuid;
  final Map<String, dynamic> serverData;
  final Map<String, dynamic> clientData;
  final String serverTimestamp;
  final String clientTimestamp;
  final String? reason;

  SyncConflict({
    required this.conflictId,
    required this.entityType,
    required this.entityUuid,
    required this.serverData,
    required this.clientData,
    required this.serverTimestamp,
    required this.clientTimestamp,
    this.reason,
  });

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      conflictId: json['conflictId'] as String,
      entityType: json['entityType'] as String,
      entityUuid: json['entityUuid'] as String,
      serverData: json['serverData'] as Map<String, dynamic>,
      clientData: json['clientData'] as Map<String, dynamic>,
      serverTimestamp: json['serverTimestamp'] as String,
      clientTimestamp: json['clientTimestamp'] as String,
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'conflictId': conflictId,
        'entityType': entityType,
        'entityUuid': entityUuid,
        'serverData': serverData,
        'clientData': clientData,
        'serverTimestamp': serverTimestamp,
        'clientTimestamp': clientTimestamp,
        'reason': reason,
      };
}
