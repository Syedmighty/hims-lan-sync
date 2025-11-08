# HIMS LAN Sync Server

Offline-first Hotel Inventory Management System (HIMS) - Local Node.js server with SQLite master database.

## Features

- **Offline-First Architecture**: SQLite-based master database for reliable local data storage
- **LAN Discovery**: UDP broadcasting for automatic device discovery on the local network
- **Bidirectional Sync**: Push and pull sync endpoints for client-server synchronization
- **Conflict Resolution**: Automatic conflict detection with manual resolution support
- **Sync Queue**: Tracks all changes waiting to be synchronized
- **Audit Trail**: Complete sync history logging
- **Compression**: Gzip compression for efficient data transfer
- **Transaction Support**: ACID-compliant database transactions

## Architecture

```
server/
├── src/
│   ├── server.js         # Express app and route definitions
│   ├── db.js            # SQLite database operations and schema
│   ├── sync.js          # Push/Pull sync logic and conflict resolution
│   ├── discovery.js     # UDP LAN device discovery
│   └── utils.js         # Helper functions (compression, logging, etc.)
├── package.json
├── .env.example
└── README.md
```

## Installation

1. Install dependencies:
```bash
npm install
```

2. Create environment configuration:
```bash
cp .env.example .env
```

3. Configure `.env` file:
```env
PORT=5000
HOST=0.0.0.0
UDP_PORT=9999
DISCOVERY_INTERVAL=5000
DB_PATH=./hims_master.db
```

## Usage

### Development Mode
```bash
npm run dev
```

### Production Mode
```bash
npm start
```

## API Endpoints

### Health & Status

#### GET /health
Health check endpoint
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "uptime": 1234.56,
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

#### GET /discovery/status
Get UDP discovery service status

#### GET /sync/status
Get sync status for a device
- Headers: `deviceId: <device-uuid>`

#### GET /stats
Get server statistics including sync counts and entity counts

### Sync Operations

#### POST /sync/push
Push client changes to server
- Headers: `deviceId: <device-uuid>`
- Body:
```json
{
  "changes": [
    {
      "uuid": "item-uuid-123",
      "entityType": "inventory_items",
      "data": {
        "name": "Towels",
        "quantity": 50,
        "category": "Linens"
      },
      "lastModified": "2024-01-15T10:30:00.000Z",
      "operation": "upsert",
      "isSynced": true
    }
  ]
}
```

#### POST /sync/pull
Pull server changes to client
- Headers: `deviceId: <device-uuid>`
- Body:
```json
{
  "lastSyncTimestamp": "2024-01-15T09:00:00.000Z",
  "entityTypes": ["inventory_items", "transactions", "suppliers"]
}
```

#### POST /sync/batch
Combined push and pull in single request
- Headers: `deviceId: <device-uuid>`
- Body:
```json
{
  "pushPayload": { ... },
  "pullQuery": { ... }
}
```

### Conflict Management

#### GET /conflicts
Get unresolved conflicts
- Query params: `entityType`, `entityUuid` (optional filters)

#### POST /conflicts/:conflictId/resolve
Resolve a conflict
- Body:
```json
{
  "choice": "server|client|custom",
  "resolvedBy": "user-123",
  "customData": { ... }
}
```

## Database Schema

### inventory_items
- uuid (TEXT, PRIMARY KEY)
- name, category, quantity, unit
- min_stock_level, location
- last_modified, is_synced, is_deleted
- created_at, updated_at

### transactions
- uuid (TEXT, PRIMARY KEY)
- item_uuid (FOREIGN KEY)
- type (in/out), quantity, notes
- performed_by
- last_modified, is_synced, is_deleted

### suppliers
- uuid (TEXT, PRIMARY KEY)
- name, contact_person, phone, email, address
- last_modified, is_synced, is_deleted

### sync_queue
- Tracks pending changes

### conflict_log
- Records sync conflicts for resolution

### sync_history
- Audit trail of all sync operations

## UDP Discovery Protocol

The server broadcasts its presence every 5 seconds (configurable) on UDP port 9999.

### Message Types

**Server Announcement**
```json
{
  "type": "HIMS_SERVER_ANNOUNCEMENT",
  "serverIp": "192.168.1.100",
  "serverPort": 5000,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "serverName": "HIMS-LAN-Server",
  "version": "1.0.0",
  "capabilities": ["sync", "inventory", "transactions", "suppliers"]
}
```

**Client Discovery Request**
```json
{
  "type": "HIMS_DISCOVERY_REQUEST"
}
```

**Server Discovery Response**
```json
{
  "type": "HIMS_DISCOVERY_RESPONSE",
  "serverIp": "192.168.1.100",
  "serverPort": 5000,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

## Sync Flow

### Push Sync (Client → Server)
1. Client sends changes with timestamps
2. Server compares timestamps with existing records
3. Conflicts detected if server has newer version
4. Non-conflicting changes applied immediately
5. Conflicts logged for manual resolution
6. Response includes processed records and conflicts

### Pull Sync (Server → Client)
1. Client sends last sync timestamp
2. Server queries all changes since timestamp
3. Server returns modified/new/deleted records
4. Client applies changes locally

### Conflict Resolution
1. Conflicts detected during push sync
2. Logged in conflict_log table
3. Admin/user reviews conflicts via GET /conflicts
4. Resolution applied via POST /conflicts/:id/resolve
5. Resolved data synced to all clients

## Logging

Logs are written to:
- Console (colorized)
- `./logs/error.log` (errors only)
- `./logs/combined.log` (all logs)

Log levels: error, warn, info, debug

## Error Handling

All API responses follow this format:
```json
{
  "success": true|false,
  "timestamp": "2024-01-15T10:30:00.000Z",
  "data": { ... },
  "message": "Descriptive message",
  "errors": []
}
```

## Security Considerations

- Server runs on local network only (LAN)
- No authentication (trusted LAN environment)
- SQL injection prevented via parameterized queries
- Input validation on all endpoints
- CORS enabled for cross-origin requests

## Performance

- WAL mode enabled for concurrent access
- Indexed columns for fast queries
- Gzip compression for network efficiency
- Batch operations supported
- Transaction-based consistency

## Troubleshooting

**Server won't start**
- Check if port 5000 is already in use
- Verify database path is writable
- Check logs for specific errors

**Clients can't discover server**
- Ensure UDP port 9999 is not blocked by firewall
- Verify devices are on same subnet
- Check DISCOVERY_INTERVAL in .env

**Sync conflicts**
- Review conflicts via GET /conflicts
- Resolve using POST /conflicts/:id/resolve
- Check sync_history for patterns

## License

MIT
