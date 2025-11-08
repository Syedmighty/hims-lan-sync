const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');
const { logger, getCurrentTimestamp } = require('./utils');

let db = null;

/**
 * Initialize the SQLite database with all required tables
 */
function initializeDatabase() {
  try {
    const dbPath = process.env.DB_PATH || './hims_master.db';
    const dbDir = path.dirname(dbPath);

    // Ensure directory exists
    if (!fs.existsSync(dbDir) && dbDir !== '.') {
      fs.mkdirSync(dbDir, { recursive: true });
    }

    db = new Database(dbPath, { verbose: logger.debug });
    logger.info(`Database connected at: ${dbPath}`);

    // Enable WAL mode for better concurrent access
    db.pragma('journal_mode = WAL');

    // Create tables
    createTables();

    logger.info('Database initialized successfully');
    return db;
  } catch (error) {
    logger.error('Database initialization failed:', error);
    throw error;
  }
}

/**
 * Create all required tables for HIMS
 */
function createTables() {
  // Inventory Items table
  db.exec(`
    CREATE TABLE IF NOT EXISTS inventory_items (
      uuid TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT,
      quantity INTEGER DEFAULT 0,
      unit TEXT,
      min_stock_level INTEGER DEFAULT 0,
      location TEXT,
      last_modified TEXT NOT NULL,
      is_synced INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  // Transactions table (stock in/out)
  db.exec(`
    CREATE TABLE IF NOT EXISTS transactions (
      uuid TEXT PRIMARY KEY,
      item_uuid TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('in', 'out')),
      quantity INTEGER NOT NULL,
      notes TEXT,
      performed_by TEXT,
      last_modified TEXT NOT NULL,
      is_synced INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY (item_uuid) REFERENCES inventory_items(uuid)
    )
  `);

  // Suppliers table
  db.exec(`
    CREATE TABLE IF NOT EXISTS suppliers (
      uuid TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      contact_person TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      last_modified TEXT NOT NULL,
      is_synced INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )
  `);

  // Sync Queue table - tracks changes waiting to be synced
  db.exec(`
    CREATE TABLE IF NOT EXISTS sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN ('create', 'update', 'delete')),
      payload TEXT NOT NULL,
      device_id TEXT,
      created_at TEXT NOT NULL,
      synced_at TEXT,
      UNIQUE(entity_type, entity_uuid, operation)
    )
  `);

  // Conflict Log table - stores sync conflicts for resolution
  db.exec(`
    CREATE TABLE IF NOT EXISTS conflict_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      conflict_id TEXT UNIQUE NOT NULL,
      entity_type TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      server_data TEXT NOT NULL,
      client_data TEXT NOT NULL,
      server_timestamp TEXT NOT NULL,
      client_timestamp TEXT NOT NULL,
      resolution TEXT,
      resolved_at TEXT,
      resolved_by TEXT,
      created_at TEXT NOT NULL
    )
  `);

  // Sync History table - audit trail
  db.exec(`
    CREATE TABLE IF NOT EXISTS sync_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      sync_type TEXT NOT NULL CHECK(sync_type IN ('push', 'pull')),
      records_count INTEGER DEFAULT 0,
      conflicts_count INTEGER DEFAULT 0,
      success INTEGER DEFAULT 1,
      error_message TEXT,
      started_at TEXT NOT NULL,
      completed_at TEXT
    )
  `);

  // Create indices for better query performance
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_inventory_last_modified ON inventory_items(last_modified);
    CREATE INDEX IF NOT EXISTS idx_inventory_is_synced ON inventory_items(is_synced);
    CREATE INDEX IF NOT EXISTS idx_transactions_item ON transactions(item_uuid);
    CREATE INDEX IF NOT EXISTS idx_sync_queue_entity ON sync_queue(entity_type, entity_uuid);
    CREATE INDEX IF NOT EXISTS idx_conflict_entity ON conflict_log(entity_type, entity_uuid);
  `);

  logger.info('Database tables created successfully');
}

/**
 * Get database instance
 * @returns {Database} SQLite database instance
 */
function getDatabase() {
  if (!db) {
    throw new Error('Database not initialized. Call initializeDatabase() first.');
  }
  return db;
}

/**
 * Execute a transaction with automatic rollback on error
 * @param {Function} callback - Function to execute within transaction
 * @returns {any} Result of the callback
 */
function runTransaction(callback) {
  const transaction = db.transaction(callback);
  return transaction();
}

/**
 * Generic CRUD operations for any entity
 */
const dbOperations = {
  /**
   * Insert or update an entity
   * @param {string} tableName - Table name
   * @param {Object} data - Entity data with uuid
   * @returns {Object} Inserted/updated entity
   */
  upsert(tableName, data) {
    const columns = Object.keys(data);
    const values = Object.values(data);
    const placeholders = columns.map(() => '?').join(', ');
    const updates = columns.map(col => `${col} = excluded.${col}`).join(', ');

    const stmt = db.prepare(`
      INSERT INTO ${tableName} (${columns.join(', ')})
      VALUES (${placeholders})
      ON CONFLICT(uuid) DO UPDATE SET ${updates}
    `);

    const result = stmt.run(...values);
    logger.debug(`Upserted ${tableName}:`, data.uuid);
    return { ...data, changes: result.changes };
  },

  /**
   * Get entity by UUID
   * @param {string} tableName - Table name
   * @param {string} uuid - Entity UUID
   * @returns {Object|null} Entity or null
   */
  getByUuid(tableName, uuid) {
    const stmt = db.prepare(`SELECT * FROM ${tableName} WHERE uuid = ?`);
    return stmt.get(uuid);
  },

  /**
   * Get all entities modified after a timestamp
   * @param {string} tableName - Table name
   * @param {string} since - ISO timestamp
   * @returns {Array} Array of entities
   */
  getModifiedSince(tableName, since) {
    const stmt = db.prepare(`
      SELECT * FROM ${tableName}
      WHERE last_modified > ?
      ORDER BY last_modified ASC
    `);
    return stmt.all(since);
  },

  /**
   * Get all non-synced entities
   * @param {string} tableName - Table name
   * @returns {Array} Array of entities
   */
  getNonSynced(tableName) {
    const stmt = db.prepare(`
      SELECT * FROM ${tableName}
      WHERE is_synced = 0
      ORDER BY last_modified ASC
    `);
    return stmt.all();
  },

  /**
   * Mark entity as synced
   * @param {string} tableName - Table name
   * @param {string} uuid - Entity UUID
   */
  markAsSynced(tableName, uuid) {
    const stmt = db.prepare(`
      UPDATE ${tableName}
      SET is_synced = 1
      WHERE uuid = ?
    `);
    stmt.run(uuid);
  },

  /**
   * Soft delete an entity
   * @param {string} tableName - Table name
   * @param {string} uuid - Entity UUID
   */
  softDelete(tableName, uuid) {
    const stmt = db.prepare(`
      UPDATE ${tableName}
      SET is_deleted = 1, last_modified = ?
      WHERE uuid = ?
    `);
    stmt.run(getCurrentTimestamp(), uuid);
  },

  /**
   * Get all entities (excluding deleted)
   * @param {string} tableName - Table name
   * @returns {Array} Array of entities
   */
  getAll(tableName) {
    const stmt = db.prepare(`
      SELECT * FROM ${tableName}
      WHERE is_deleted = 0
      ORDER BY last_modified DESC
    `);
    return stmt.all();
  }
};

/**
 * Sync Queue operations
 */
const syncQueueOps = {
  /**
   * Add item to sync queue
   * @param {string} entityType - Entity type (inventory_items, transactions, etc.)
   * @param {string} entityUuid - Entity UUID
   * @param {string} operation - Operation type (create, update, delete)
   * @param {Object} payload - Entity data
   * @param {string} deviceId - Device identifier
   */
  enqueue(entityType, entityUuid, operation, payload, deviceId = 'server') {
    const stmt = db.prepare(`
      INSERT OR REPLACE INTO sync_queue
      (entity_type, entity_uuid, operation, payload, device_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      entityType,
      entityUuid,
      operation,
      JSON.stringify(payload),
      deviceId,
      getCurrentTimestamp()
    );
  },

  /**
   * Get all pending items from queue
   * @returns {Array} Pending sync items
   */
  getPending() {
    const stmt = db.prepare(`
      SELECT * FROM sync_queue
      WHERE synced_at IS NULL
      ORDER BY created_at ASC
    `);
    return stmt.all();
  },

  /**
   * Mark queue item as synced
   * @param {number} id - Queue item ID
   */
  markSynced(id) {
    const stmt = db.prepare(`
      UPDATE sync_queue
      SET synced_at = ?
      WHERE id = ?
    `);
    stmt.run(getCurrentTimestamp(), id);
  },

  /**
   * Clear synced items older than specified days
   * @param {number} days - Days to keep
   */
  clearOldSynced(days = 7) {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    const stmt = db.prepare(`
      DELETE FROM sync_queue
      WHERE synced_at IS NOT NULL
      AND synced_at < ?
    `);
    const result = stmt.run(cutoffDate.toISOString());
    logger.info(`Cleared ${result.changes} old sync queue items`);
  }
};

/**
 * Conflict Log operations
 */
const conflictLogOps = {
  /**
   * Log a conflict
   * @param {Object} conflict - Conflict data
   */
  logConflict(conflict) {
    const stmt = db.prepare(`
      INSERT INTO conflict_log
      (conflict_id, entity_type, entity_uuid, server_data, client_data,
       server_timestamp, client_timestamp, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      conflict.conflictId,
      conflict.entityType,
      conflict.entityUuid,
      JSON.stringify(conflict.serverData),
      JSON.stringify(conflict.clientData),
      conflict.serverTimestamp,
      conflict.clientTimestamp,
      getCurrentTimestamp()
    );
  },

  /**
   * Get unresolved conflicts
   * @returns {Array} Unresolved conflicts
   */
  getUnresolved() {
    const stmt = db.prepare(`
      SELECT * FROM conflict_log
      WHERE resolved_at IS NULL
      ORDER BY created_at DESC
    `);
    return stmt.all().map(row => ({
      ...row,
      serverData: JSON.parse(row.server_data),
      clientData: JSON.parse(row.client_data)
    }));
  },

  /**
   * Resolve a conflict
   * @param {string} conflictId - Conflict ID
   * @param {string} resolution - Resolution description
   * @param {string} resolvedBy - User/device that resolved
   */
  resolveConflict(conflictId, resolution, resolvedBy = 'system') {
    const stmt = db.prepare(`
      UPDATE conflict_log
      SET resolution = ?, resolved_at = ?, resolved_by = ?
      WHERE conflict_id = ?
    `);
    stmt.run(resolution, getCurrentTimestamp(), resolvedBy, conflictId);
  }
};

/**
 * Sync History operations
 */
const syncHistoryOps = {
  /**
   * Start a sync session
   * @param {string} deviceId - Device identifier
   * @param {string} syncType - 'push' or 'pull'
   * @returns {number} History record ID
   */
  startSession(deviceId, syncType) {
    const stmt = db.prepare(`
      INSERT INTO sync_history (device_id, sync_type, started_at)
      VALUES (?, ?, ?)
    `);
    const result = stmt.run(deviceId, syncType, getCurrentTimestamp());
    return result.lastInsertRowid;
  },

  /**
   * Complete a sync session
   * @param {number} id - History record ID
   * @param {number} recordsCount - Number of records synced
   * @param {number} conflictsCount - Number of conflicts
   * @param {boolean} success - Success status
   * @param {string} errorMessage - Error message if failed
   */
  completeSession(id, recordsCount, conflictsCount, success = true, errorMessage = null) {
    const stmt = db.prepare(`
      UPDATE sync_history
      SET records_count = ?, conflicts_count = ?, success = ?,
          error_message = ?, completed_at = ?
      WHERE id = ?
    `);
    stmt.run(
      recordsCount,
      conflictsCount,
      success ? 1 : 0,
      errorMessage,
      getCurrentTimestamp(),
      id
    );
  },

  /**
   * Get recent sync history
   * @param {number} limit - Number of records to retrieve
   * @returns {Array} Recent sync sessions
   */
  getRecent(limit = 50) {
    const stmt = db.prepare(`
      SELECT * FROM sync_history
      ORDER BY started_at DESC
      LIMIT ?
    `);
    return stmt.all(limit);
  }
};

/**
 * Close database connection
 */
function closeDatabase() {
  if (db) {
    db.close();
    logger.info('Database connection closed');
    db = null;
  }
}

module.exports = {
  initializeDatabase,
  getDatabase,
  runTransaction,
  dbOperations,
  syncQueueOps,
  conflictLogOps,
  syncHistoryOps,
  closeDatabase
};
