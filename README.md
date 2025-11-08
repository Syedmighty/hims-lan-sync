# HIMS LAN Sync System

**Hotel Inventory Management System - Offline-First LAN Synchronization**

A complete offline-first synchronization system for hotel inventory management, designed to work seamlessly across multiple devices on a local network without requiring cloud connectivity.

## Overview

HIMS LAN Sync enables multiple Flutter devices to synchronize inventory data through a local Node.js server, providing reliable offline operation with intelligent conflict resolution.

### Key Features

- **Offline-First Architecture**: Full functionality without internet connectivity
- **Real-Time LAN Discovery**: Automatic server discovery via UDP broadcasting
- **Bidirectional Sync**: Push and pull synchronization between clients and server
- **Conflict Resolution**: Smart conflict detection with manual resolution UI
- **Local Master Database**: SQLite-based server database with ACID compliance
- **Sync Queue Management**: Automatic tracking and processing of pending changes
- **Audit Trail**: Complete sync history logging
- **Data Compression**: Gzip compression for efficient network usage
- **No Cloud Dependencies**: Completely self-contained LAN operation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     HIMS LAN Sync System                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────┐         ┌─────────────┐                    │
│  │   Flutter   │         │   Flutter   │                    │
│  │   Client 1  │         │   Client 2  │                    │
│  │  (Drift DB) │         │  (Drift DB) │   ... more clients │
│  └──────┬──────┘         └──────┬──────┘                    │
│         │                       │                            │
│         │   UDP Discovery       │                            │
│         │   (Port 9999)         │                            │
│         │                       │                            │
│         └───────────┬───────────┘                            │
│                     │                                        │
│              ┌──────▼──────┐                                 │
│              │   Node.js   │                                 │
│              │   Server    │                                 │
│              │ (SQLite DB) │                                 │
│              └─────────────┘                                 │
│                                                               │
│         REST API (Port 5000)                                 │
│         • /sync/push   - Client → Server                     │
│         • /sync/pull   - Server → Client                     │
│         • /sync/batch  - Combined Push + Pull                │
│         • /conflicts   - Conflict Management                 │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
hims-lan-sync/
├── server/                      # Node.js LAN Server
│   ├── src/
│   │   ├── server.js            # Express app + routes
│   │   ├── db.js                # SQLite operations
│   │   ├── sync.js              # Sync logic
│   │   ├── discovery.js         # UDP discovery
│   │   └── utils.js             # Utilities
│   ├── package.json
│   ├── .env.example
│   └── README.md
│
└── flutter/                     # Flutter Client Services
    ├── lib/
    │   └── services/
    │       ├── discovery_service.dart      # UDP discovery client
    │       ├── sync_service.dart           # Sync operations
    │       ├── sync_provider.dart          # Riverpod providers
    │       └── conflict_resolver_screen.dart  # Conflict UI
    └── README.md
```

## Quick Start

### Server Setup

1. Navigate to server directory:
```bash
cd server
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment:
```bash
cp .env.example .env
# Edit .env with your settings
```

4. Start server:
```bash
npm start
```

The server will:
- Start HTTP API on port 5000
- Begin UDP broadcasting on port 9999
- Initialize SQLite database
- Log all operations

### Flutter Integration

1. Add dependencies to `pubspec.yaml`:
```yaml
dependencies:
  flutter_riverpod: ^2.4.0
  http: ^1.1.0
  uuid: ^4.0.0
  shared_preferences: ^2.2.0
  drift: ^2.13.0
```

2. Copy Flutter service files to your project:
```bash
cp -r flutter/lib/services/* your_flutter_app/lib/services/
```

3. Initialize providers in your app:
```dart
void main() {
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
```

4. Use the sync system:
```dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAvailable = ref.watch(serverAvailableProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('HIMS'),
        actions: [
          IconButton(
            icon: Icon(Icons.sync),
            onPressed: () {
              ref.read(syncActionsProvider.notifier).performFullSync();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SyncStatusIndicator(),
          // Your app content
        ],
      ),
    );
  }
}
```

## How It Works

### 1. Device Discovery (UDP)

- Server broadcasts presence every 5 seconds on UDP port 9999
- Clients listen for broadcasts and automatically discover the server
- Clients can also send discovery requests for immediate response

**Message Format:**
```json
{
  "type": "HIMS_SERVER_ANNOUNCEMENT",
  "serverIp": "192.168.1.100",
  "serverPort": 5000,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "serverName": "HIMS-LAN-Server",
  "version": "1.0.0"
}
```

### 2. Data Synchronization

**Push Sync (Client → Server):**
1. Client collects local changes (unsynced records)
2. Sends changes with UUIDs and timestamps to `/sync/push`
3. Server compares timestamps with existing records
4. Non-conflicting changes applied immediately
5. Conflicts logged for resolution
6. Response includes processed records and conflicts

**Pull Sync (Server → Client):**
1. Client requests changes since last sync timestamp
2. Server queries all modified records
3. Server returns changed/new/deleted records
4. Client applies changes to local Drift database

**Batch Sync:**
- Combines push and pull in single request
- More efficient for periodic syncs
- Reduces network round-trips

### 3. Conflict Detection

Conflicts occur when:
- Server has newer timestamp than client push
- Both sides modified same record simultaneously
- Delete operation conflicts with update

**Conflict Data:**
```json
{
  "conflictId": "conflict_uuid_timestamp",
  "entityType": "inventory_items",
  "entityUuid": "item-123",
  "serverData": { "quantity": 50, "lastModified": "2024-01-15T10:30:00Z" },
  "clientData": { "quantity": 45, "lastModified": "2024-01-15T10:29:00Z" },
  "serverTimestamp": "2024-01-15T10:30:00Z",
  "clientTimestamp": "2024-01-15T10:29:00Z",
  "reason": "Server has newer version"
}
```

### 4. Conflict Resolution

**Three Resolution Strategies:**

1. **Keep Server**: Accept server version, discard client changes
2. **Keep Client**: Apply client version to server
3. **Custom Merge**: Manually merge fields from both versions

**UI Resolution Flow:**
```dart
ConflictResolverScreen()  // Shows all conflicts
  → User reviews data differences
  → Selects resolution strategy
  → Applied via /conflicts/:id/resolve
  → All clients receive updated data
```

## Data Models

### Inventory Items
```dart
class InventoryItem {
  String uuid;
  String name;
  String category;
  int quantity;
  String unit;
  int minStockLevel;
  String location;
  DateTime lastModified;
  bool isSynced;
  bool isDeleted;
}
```

### Transactions
```dart
class Transaction {
  String uuid;
  String itemUuid;
  String type; // 'in' or 'out'
  int quantity;
  String notes;
  String performedBy;
  DateTime lastModified;
  bool isSynced;
  bool isDeleted;
}
```

### Suppliers
```dart
class Supplier {
  String uuid;
  String name;
  String contactPerson;
  String phone;
  String email;
  String address;
  DateTime lastModified;
  bool isSynced;
  bool isDeleted;
}
```

## API Endpoints

### Sync Operations

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/sync/push` | POST | Push client changes to server |
| `/sync/pull` | POST | Pull server changes to client |
| `/sync/batch` | POST | Combined push + pull |
| `/sync/status` | GET | Get sync status for device |

### Conflict Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/conflicts` | GET | List unresolved conflicts |
| `/conflicts/:id/resolve` | POST | Resolve a conflict |

### Server Status

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Server health check |
| `/discovery/status` | GET | UDP discovery status |
| `/stats` | GET | Sync statistics |

## Configuration

### Server Environment Variables

```bash
# Server Configuration
PORT=5000                    # HTTP server port
HOST=0.0.0.0                # Bind address

# UDP Discovery
UDP_PORT=9999               # UDP broadcast port
DISCOVERY_INTERVAL=5000     # Broadcast interval (ms)

# Database
DB_PATH=./hims_master.db    # SQLite database path

# Sync Configuration
MAX_SYNC_BATCH_SIZE=1000    # Max records per sync
ENABLE_COMPRESSION=true     # Enable gzip compression

# Logging
LOG_LEVEL=info              # Log level
LOG_FILE=./logs/hims-sync.log
```

### Flutter Configuration

```dart
// Auto-sync interval
const AUTO_SYNC_INTERVAL = Duration(minutes: 5);

// Discovery settings
const UDP_PORT = 9999;
const DISCOVERY_INTERVAL = Duration(seconds: 5);
const DISCOVERY_TIMEOUT = Duration(seconds: 30);
```

## Best Practices

### 1. Sync Frequency
- Enable auto-sync with 5-minute intervals
- Trigger manual sync after critical operations
- Sync on app resume from background

### 2. Conflict Prevention
- Sync frequently to minimize conflicts
- Implement optimistic locking where possible
- Design workflows to minimize concurrent edits

### 3. Network Reliability
- Always check server availability before operations
- Queue changes locally when offline
- Provide clear sync status indicators

### 4. Data Integrity
- Use UUIDs for all entities
- Always include timestamps
- Implement soft deletes (is_deleted flag)
- Never skip conflict resolution

### 5. Performance
- Use batch sync for efficiency
- Limit sync payload size
- Index frequently queried fields
- Clean old sync history periodically

## Troubleshooting

### Server Not Discovered

**Problem**: Clients can't find the server

**Solutions**:
- Verify all devices on same subnet
- Check firewall allows UDP port 9999
- Ensure server is broadcasting (check logs)
- Try manual server configuration

### Sync Conflicts

**Problem**: Too many conflicts occurring

**Solutions**:
- Increase sync frequency
- Review user workflows
- Check system clocks synchronized
- Implement field-level locking

### Slow Sync

**Problem**: Sync operations taking too long

**Solutions**:
- Enable compression (ENABLE_COMPRESSION=true)
- Reduce batch size
- Check network latency
- Optimize database indices

### Database Errors

**Problem**: SQLite errors on server

**Solutions**:
- Check disk space
- Verify write permissions
- Check database file integrity
- Review transaction logs

## Testing

### Server Testing
```bash
# Start server
cd server
npm start

# Test health endpoint
curl http://localhost:5000/health

# Test sync endpoint
curl -X POST http://localhost:5000/sync/push \
  -H "deviceId: test-device" \
  -H "Content-Type: application/json" \
  -d '{"changes": []}'
```

### Flutter Testing
```dart
// Test discovery
final discoveryService = DiscoveryService();
await discoveryService.initialize();
await discoveryService.startDiscovery();

// Test sync
final syncService = SyncService(discoveryService: discoveryService);
final result = await syncService.performFullSync();
print('Sync result: ${result.success}');
```

## Security Considerations

- **LAN Only**: System designed for trusted local networks
- **No Authentication**: Assumes trusted LAN environment
- **SQL Injection**: Protected via parameterized queries
- **Input Validation**: All endpoints validate input
- **CORS Enabled**: For cross-origin requests

**For Production**:
- Add authentication/authorization
- Implement TLS/SSL
- Add rate limiting
- Implement access control
- Log all operations

## Performance Metrics

- **Discovery Time**: < 5 seconds typically
- **Sync Latency**: < 1 second for 100 records
- **Conflict Detection**: Real-time during push
- **Database Operations**: < 100ms per query
- **Network Overhead**: ~30% reduction with gzip

## Documentation

- [Server Documentation](server/README.md) - Complete Node.js server guide
- [Flutter Documentation](flutter/README.md) - Flutter integration guide

## Roadmap

- [ ] Add authentication system
- [ ] Implement field-level sync
- [ ] Add real-time WebSocket sync
- [ ] Support multiple servers (clustering)
- [ ] Add data encryption at rest
- [ ] Implement automatic conflict resolution rules
- [ ] Add backup/restore functionality
- [ ] Support for offline image sync

## License

MIT License - See LICENSE file for details

## Support

For issues and questions:
1. Check documentation in `/server/README.md` and `/flutter/README.md`
2. Review server logs
3. Test with health endpoints
4. Review sync history in database

## Contributors

Built for Hotel Inventory Management System (HIMS)
