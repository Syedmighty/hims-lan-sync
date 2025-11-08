# HIMS LAN Sync - Flutter Client

Flutter services for HIMS LAN Sync system with offline-first architecture using Drift and Riverpod.

## Overview

This Flutter implementation provides:
- UDP-based LAN server discovery
- Bidirectional synchronization (push/pull)
- Conflict resolution UI
- Offline-first data management with Drift
- Reactive state management with Riverpod

## Architecture

```
lib/services/
├── discovery_service.dart          # UDP discovery client
├── sync_service.dart               # Sync operations manager
├── sync_provider.dart              # Riverpod providers
└── conflict_resolver_screen.dart   # Conflict resolution UI
```

## Dependencies

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.4.0

  # Networking
  http: ^1.1.0

  # UUID Generation
  uuid: ^4.0.0

  # Local Storage
  shared_preferences: ^2.2.0

  # Database
  drift: ^2.13.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  path: ^1.8.3

dev_dependencies:
  drift_dev: ^2.13.0
  build_runner: ^2.4.0
```

## Installation

1. Copy service files to your project:
```bash
cp -r lib/services your_flutter_project/lib/
```

2. Install dependencies:
```bash
flutter pub get
```

3. Initialize providers in your app:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/sync_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

## Usage

### Basic Setup

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/sync_provider.dart';
import 'services/conflict_resolver_screen.dart';

class MyHomePage extends ConsumerWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAvailable = ref.watch(serverAvailableProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final hasConflicts = ref.watch(hasConflictsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HIMS Inventory'),
        actions: [
          // Sync button with conflict badge
          ConflictBadge(
            child: IconButton(
              icon: const Icon(Icons.sync),
              onPressed: serverAvailable
                  ? () => ref.read(syncActionsProvider.notifier).performFullSync()
                  : null,
            ),
          ),
          // Conflicts button
          if (hasConflicts)
            IconButton(
              icon: const Icon(Icons.warning, color: Colors.orange),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConflictResolverScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Sync status indicator
          const SyncStatusIndicator(),

          // Your app content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Your inventory list or other content
    return const Center(child: Text('Inventory Content'));
  }
}
```

### Server Discovery

Discovery happens automatically when the app starts:

```dart
// Manual discovery control
final discoveryService = ref.watch(discoveryServiceProvider);

// Start discovery
discoveryService.startDiscovery();

// Stop discovery
discoveryService.stopDiscovery();

// Manual server configuration
discoveryService.setServerInfo('192.168.1.100', 5000);

// Check server status
final serverInfo = ref.watch(serverInfoProvider);
if (serverInfo != null) {
  print('Connected to: ${serverInfo.name} at ${serverInfo.ip}');
}
```

### Synchronization

```dart
// Auto-sync is enabled by default (every 5 minutes)
// Manual sync trigger:

final syncActions = ref.read(syncActionsProvider.notifier);

// Full bidirectional sync
await syncActions.performFullSync();

// Push only
await syncActions.pushChanges();

// Pull only
await syncActions.pullChanges();

// Watch sync status
final syncStatus = ref.watch(syncStatusProvider);
switch (syncStatus) {
  case SyncStatus.idle:
    print('Ready to sync');
    break;
  case SyncStatus.syncing:
    print('Syncing in progress...');
    break;
  case SyncStatus.completed:
    print('Sync completed successfully');
    break;
  case SyncStatus.error:
    final error = ref.watch(syncErrorProvider);
    print('Sync error: $error');
    break;
}
```

### Conflict Resolution

```dart
// Navigate to conflict resolver screen
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const ConflictResolverScreen(),
  ),
);

// Watch for conflicts
final conflicts = ref.watch(conflictsProvider);
print('Unresolved conflicts: ${conflicts.length}');

// Programmatic conflict resolution
final syncActions = ref.read(syncActionsProvider.notifier);
await syncActions.resolveConflict(
  'conflict-id-123',
  ConflictResolution.server, // or .client or .custom
  null, // customData for .custom resolution
);
```

## Integration with Drift

You need to integrate these services with your Drift database. Here's how:

### 1. Define Your Drift Tables

```dart
// lib/database/tables.dart
import 'package:drift/drift.dart';

class InventoryItems extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get quantity => integer()();
  TextColumn get unit => text()();
  IntColumn get minStockLevel => integer()();
  TextColumn get location => text()();
  DateTimeColumn get lastModified => dateTime()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {uuid};
}
```

### 2. Implement Sync Methods in SyncService

Update `sync_service.dart` to query your Drift database:

```dart
// In _getLocalChanges method:
Future<List<Map<String, dynamic>>> _getLocalChanges() async {
  final db = await database; // Your Drift database instance

  final unsyncedItems = await (db.select(db.inventoryItems)
    ..where((tbl) => tbl.isSynced.equals(false)))
    .get();

  return unsyncedItems.map((item) => {
    'uuid': item.uuid,
    'entityType': 'inventory_items',
    'data': {
      'name': item.name,
      'category': item.category,
      'quantity': item.quantity,
      'unit': item.unit,
      'min_stock_level': item.minStockLevel,
      'location': item.location,
      'last_modified': item.lastModified.toIso8601String(),
      'is_synced': item.isSynced,
      'is_deleted': item.isDeleted,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
    },
    'lastModified': item.lastModified.toIso8601String(),
    'operation': item.isDeleted ? 'delete' : 'upsert',
    'isSynced': item.isSynced,
  }).toList();
}

// In _applyServerChange method:
Future<void> _applyServerChange(Map<String, dynamic> change) async {
  final db = await database;
  final uuid = change['uuid'] as String;
  final entityType = change['entityType'] as String;
  final operation = change['operation'] as String;
  final data = change['data'] as Map<String, dynamic>;

  if (entityType == 'inventory_items') {
    if (operation == 'delete') {
      await (db.update(db.inventoryItems)
        ..where((tbl) => tbl.uuid.equals(uuid)))
        .write(InventoryItemsCompanion(
          isDeleted: const Value(true),
          lastModified: Value(DateTime.now()),
        ));
    } else {
      await db.into(db.inventoryItems).insertOnConflictUpdate(
        InventoryItem(
          uuid: uuid,
          name: data['name'],
          category: data['category'],
          quantity: data['quantity'],
          unit: data['unit'],
          minStockLevel: data['min_stock_level'],
          location: data['location'],
          lastModified: DateTime.parse(data['last_modified']),
          isSynced: true,
          isDeleted: data['is_deleted'],
          createdAt: DateTime.parse(data['created_at']),
          updatedAt: DateTime.parse(data['updated_at']),
        ),
      );
    }
  }
}

// In _markRecordAsSynced method:
Future<void> _markRecordAsSynced(String uuid) async {
  final db = await database;
  await (db.update(db.inventoryItems)
    ..where((tbl) => tbl.uuid.equals(uuid)))
    .write(const InventoryItemsCompanion(
      isSynced: Value(true),
    ));
}
```

### 3. Update Records with Sync Flags

When creating/updating records locally:

```dart
Future<void> createInventoryItem(String name, int quantity) async {
  final db = await database;

  await db.into(db.inventoryItems).insert(
    InventoryItemsCompanion(
      uuid: Value(const Uuid().v4()),
      name: Value(name),
      quantity: Value(quantity),
      lastModified: Value(DateTime.now()),
      isSynced: const Value(false), // Mark as unsynced
      isDeleted: const Value(false),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ),
  );

  // Trigger sync if server available
  ref.read(syncActionsProvider.notifier).performFullSync();
}
```

## Widgets

### SyncStatusIndicator

Displays current sync status:

```dart
const SyncStatusIndicator()
```

### ConflictBadge

Wraps a widget with conflict count badge:

```dart
ConflictBadge(
  child: IconButton(
    icon: const Icon(Icons.sync),
    onPressed: () => performSync(),
  ),
)
```

### ConflictResolverScreen

Full screen for resolving conflicts:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const ConflictResolverScreen(),
  ),
);
```

## Providers Reference

| Provider | Type | Description |
|----------|------|-------------|
| `discoveryServiceProvider` | ChangeNotifier | Discovery service instance |
| `syncServiceProvider` | Provider | Sync service instance |
| `deviceIdProvider` | FutureProvider | Persistent device ID |
| `serverInfoProvider` | Provider | Current server info |
| `serverAvailableProvider` | Provider | Server availability status |
| `syncStatusProvider` | Provider | Current sync status |
| `lastSyncTimeProvider` | Provider | Last successful sync time |
| `pendingChangesProvider` | Provider | Count of unsynced changes |
| `conflictsProvider` | Provider | List of unresolved conflicts |
| `hasConflictsProvider` | Provider | Boolean for conflict presence |
| `syncErrorProvider` | Provider | Last sync error message |
| `syncActionsProvider` | StateNotifier | Actions for triggering sync |
| `discoveryActionsProvider` | StateNotifier | Actions for discovery control |

## Configuration

### Auto-Sync Interval

```dart
// In sync_service.dart
static const Duration AUTO_SYNC_INTERVAL = Duration(minutes: 5);
```

### Discovery Settings

```dart
// In discovery_service.dart
static const int UDP_PORT = 9999;
static const Duration DISCOVERY_INTERVAL = Duration(seconds: 5);
static const Duration DISCOVERY_TIMEOUT = Duration(seconds: 30);
```

## Best Practices

### 1. Always Use UUIDs

```dart
import 'package:uuid/uuid.dart';

final uuid = const Uuid().v4();
```

### 2. Update Timestamps

```dart
lastModified: DateTime.now(),
updatedAt: DateTime.now(),
```

### 3. Mark Changes as Unsynced

```dart
isSynced: false, // When creating/updating locally
```

### 4. Implement Soft Deletes

```dart
// Don't actually delete from database
isDeleted: true,
lastModified: DateTime.now(),
isSynced: false,
```

### 5. Handle Offline Scenarios

```dart
final serverAvailable = ref.watch(serverAvailableProvider);
if (serverAvailable) {
  await sync();
} else {
  // Queue changes locally, will sync when server available
  showSnackBar('Offline - changes will sync when server is available');
}
```

### 6. Provide User Feedback

```dart
ref.listen(syncStatusProvider, (previous, next) {
  if (next == SyncStatus.completed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync completed')),
    );
  } else if (next == SyncStatus.error) {
    final error = ref.read(syncErrorProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync error: $error')),
    );
  }
});
```

## Troubleshooting

### Discovery Not Working

```dart
// Check if discovery service initialized
final discoveryService = ref.read(discoveryServiceProvider);

// Manually trigger discovery
await discoveryService.startDiscovery();

// Or set server manually
discoveryService.setServerInfo('192.168.1.100', 5000);
```

### Sync Failures

```dart
// Check error message
final error = ref.watch(syncErrorProvider);
print('Sync error: $error');

// Check server availability
final available = ref.watch(serverAvailableProvider);
print('Server available: $available');

// Check pending changes
final pending = ref.watch(pendingChangesProvider);
print('Pending changes: $pending');
```

### Conflicts Not Resolving

```dart
// Fetch latest conflicts from server
await ref.read(syncActionsProvider.notifier).fetchConflicts();

// Check conflict details
final conflicts = ref.watch(conflictsProvider);
for (final conflict in conflicts) {
  print('Conflict: ${conflict.entityType}/${conflict.entityUuid}');
  print('Reason: ${conflict.reason}');
}
```

## Testing

```dart
// Mock discovery service for testing
class MockDiscoveryService extends DiscoveryService {
  @override
  Future<void> initialize() async {
    // Mock implementation
  }

  @override
  bool get isServerAvailable => true;

  @override
  String? getServerBaseUrl() => 'http://localhost:5000';
}

// Use in tests
testWidgets('Sync test', (tester) async {
  final container = ProviderContainer(
    overrides: [
      discoveryServiceProvider.overrideWith((_) => MockDiscoveryService()),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );

  // Test sync functionality
});
```

## Performance Tips

1. **Batch Database Operations**: Use Drift transactions for multiple updates
2. **Limit Sync Frequency**: Don't sync too often (5 min default is good)
3. **Incremental Sync**: Only sync changed records using timestamps
4. **Background Sync**: Use WorkManager for periodic background sync
5. **Compress Large Payloads**: Server handles gzip automatically

## License

MIT License
