import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import 'sync_service.dart';

/// Riverpod providers for HIMS LAN Sync system
/// These providers manage the lifecycle and state of discovery and sync services

// Discovery Service Provider
final discoveryServiceProvider = ChangeNotifierProvider<DiscoveryService>((ref) {
  final service = DiscoveryService();

  // Initialize discovery service
  service.initialize().then((_) {
    // Auto-start discovery
    service.startDiscovery();
  }).catchError((error) {
    print('Failed to initialize discovery service: $error');
  });

  // Cleanup on dispose
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

// Device ID Provider - Persistent across app restarts
final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  String? deviceId = prefs.getString('device_id');

  if (deviceId == null) {
    // Generate new device ID if not exists
    deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    await prefs.setString('device_id', deviceId);
  }

  return deviceId;
});

// Sync Service Provider
final syncServiceProvider = Provider<SyncService>((ref) {
  final discoveryService = ref.watch(discoveryServiceProvider);
  final deviceIdAsync = ref.watch(deviceIdProvider);

  // Wait for device ID to be available
  final deviceId = deviceIdAsync.whenOrNull(data: (id) => id);

  final service = SyncService(
    discoveryService: discoveryService,
    deviceId: deviceId,
  );

  // Start auto-sync
  service.startAutoSync();

  // Cleanup on dispose
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

// Server Info Provider - Current server information
final serverInfoProvider = Provider<ServerInfo?>((ref) {
  final discoveryService = ref.watch(discoveryServiceProvider);
  return discoveryService.serverInfo;
});

// Server Availability Provider
final serverAvailableProvider = Provider<bool>((ref) {
  final discoveryService = ref.watch(discoveryServiceProvider);
  return discoveryService.isServerAvailable;
});

// Sync Status Provider
final syncStatusProvider = Provider<SyncStatus>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.syncStatus;
});

// Last Sync Time Provider
final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.lastSyncTime;
});

// Pending Changes Count Provider
final pendingChangesProvider = Provider<int>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.pendingChanges;
});

// Conflicts Provider
final conflictsProvider = Provider<List<SyncConflict>>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.conflicts;
});

// Has Conflicts Provider
final hasConflictsProvider = Provider<bool>((ref) {
  final conflicts = ref.watch(conflictsProvider);
  return conflicts.isNotEmpty;
});

// Sync Error Provider
final syncErrorProvider = Provider<String?>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.lastError;
});

/// Provider for manual sync trigger
/// Use this to trigger a full sync from UI
final manualSyncProvider = FutureProvider.autoDispose<SyncResult>((ref) async {
  final syncService = ref.watch(syncServiceProvider);
  return await syncService.performFullSync();
});

/// Provider for fetching conflicts from server
final fetchConflictsProvider = FutureProvider.autoDispose<List<SyncConflict>>((ref) async {
  final syncService = ref.watch(syncServiceProvider);
  return await syncService.fetchConflicts();
});

/// Provider for sync statistics from server
final syncStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final serverInfo = ref.watch(serverInfoProvider);
  if (serverInfo == null) return null;

  // Fetch stats from server
  // TODO: Implement HTTP request to /stats endpoint
  return null;
});

/// Provider for conflict resolution
/// This is a state provider that can be used to manage conflict resolution flow
final conflictResolutionProvider = StateProvider<ConflictResolutionState?>((ref) {
  return null;
});

/// State class for conflict resolution
class ConflictResolutionState {
  final SyncConflict conflict;
  final ConflictResolution? selectedResolution;
  final Map<String, dynamic>? customData;

  ConflictResolutionState({
    required this.conflict,
    this.selectedResolution,
    this.customData,
  });

  ConflictResolutionState copyWith({
    SyncConflict? conflict,
    ConflictResolution? selectedResolution,
    Map<String, dynamic>? customData,
  }) {
    return ConflictResolutionState(
      conflict: conflict ?? this.conflict,
      selectedResolution: selectedResolution ?? this.selectedResolution,
      customData: customData ?? this.customData,
    );
  }
}

/// Helper extension for SyncStatus
extension SyncStatusX on SyncStatus {
  String get displayName {
    switch (this) {
      case SyncStatus.idle:
        return 'Idle';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.completed:
        return 'Completed';
      case SyncStatus.error:
        return 'Error';
    }
  }

  bool get isInProgress => this == SyncStatus.syncing;
  bool get isError => this == SyncStatus.error;
  bool get isCompleted => this == SyncStatus.completed;
}

/// Helper notifier for triggering sync actions
class SyncActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final SyncService _syncService;

  SyncActionsNotifier(this._syncService) : super(const AsyncValue.data(null));

  /// Trigger full sync
  Future<void> performFullSync() async {
    state = const AsyncValue.loading();
    try {
      await _syncService.performFullSync();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Push changes only
  Future<void> pushChanges() async {
    state = const AsyncValue.loading();
    try {
      await _syncService.pushChanges();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Pull changes only
  Future<void> pullChanges() async {
    state = const AsyncValue.loading();
    try {
      await _syncService.pullChanges();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Fetch conflicts
  Future<void> fetchConflicts() async {
    state = const AsyncValue.loading();
    try {
      await _syncService.fetchConflicts();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Resolve conflict
  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
    Map<String, dynamic>? customData,
  ) async {
    state = const AsyncValue.loading();
    try {
      final success = await _syncService.resolveConflict(
        conflictId,
        resolution,
        customData,
      );

      if (!success) {
        throw Exception('Failed to resolve conflict');
      }

      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// Provider for sync actions
final syncActionsProvider = StateNotifierProvider<SyncActionsNotifier, AsyncValue<void>>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return SyncActionsNotifier(syncService);
});

/// Provider for discovery actions
class DiscoveryActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final DiscoveryService _discoveryService;

  DiscoveryActionsNotifier(this._discoveryService) : super(const AsyncValue.data(null));

  /// Start discovery
  Future<void> startDiscovery() async {
    state = const AsyncValue.loading();
    try {
      await _discoveryService.startDiscovery();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Stop discovery
  void stopDiscovery() {
    _discoveryService.stopDiscovery();
    state = const AsyncValue.data(null);
  }

  /// Manually set server info
  void setServerInfo(String ip, int port) {
    _discoveryService.setServerInfo(ip, port);
    state = const AsyncValue.data(null);
  }
}

final discoveryActionsProvider = StateNotifierProvider<DiscoveryActionsNotifier, AsyncValue<void>>((ref) {
  final discoveryService = ref.watch(discoveryServiceProvider);
  return DiscoveryActionsNotifier(discoveryService);
});
