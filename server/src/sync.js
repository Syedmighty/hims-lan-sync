const {
  dbOperations,
  syncQueueOps,
  conflictLogOps,
  syncHistoryOps,
  runTransaction,
  getDatabase
} = require('./db');
const {
  logger,
  getCurrentTimestamp,
  compareTimestamps,
  validateSyncPayload,
  createResponse,
  generateConflictId
} = require('./utils');
const { notifyClientsOfChange } = require('./discovery');

/**
 * Handle push sync from client to server
 * Client sends local changes to be merged with server
 * @param {Object} payload - Sync payload from client
 * @param {string} deviceId - Device identifier
 * @returns {Object} Sync result with conflicts
 */
async function handlePushSync(payload, deviceId) {
  const historyId = syncHistoryOps.startSession(deviceId, 'push');
  let recordsProcessed = 0;
  let conflictsDetected = 0;
  const conflicts = [];
  const processedRecords = [];

  try {
    // Validate payload
    const validation = validateSyncPayload(payload);
    if (!validation.isValid) {
      logger.warn('Invalid push payload:', validation.errors);
      syncHistoryOps.completeSession(historyId, 0, 0, false, validation.errors.join('; '));
      return createResponse(false, null, 'Invalid payload', validation.errors);
    }

    logger.info(`Processing push sync from device ${deviceId} with ${payload.changes.length} changes`);

    // Process changes in a transaction
    const result = runTransaction(() => {
      for (const change of payload.changes) {
        try {
          const processResult = processClientChange(change, deviceId);

          if (processResult.conflict) {
            conflicts.push(processResult.conflict);
            conflictsDetected++;
          }

          processedRecords.push({
            uuid: change.uuid,
            status: processResult.status,
            conflict: processResult.conflict ? true : false
          });

          recordsProcessed++;
        } catch (error) {
          logger.error(`Error processing change ${change.uuid}:`, error);
          processedRecords.push({
            uuid: change.uuid,
            status: 'error',
            error: error.message
          });
        }
      }

      return { processedRecords, conflicts };
    });

    // Complete sync history
    syncHistoryOps.completeSession(historyId, recordsProcessed, conflictsDetected, true);

    // Notify other clients if changes were applied
    if (recordsProcessed > 0) {
      notifyClientsOfChange('sync_push', {
        deviceId,
        recordsCount: recordsProcessed,
        conflictsCount: conflictsDetected
      });
    }

    logger.info(`Push sync completed: ${recordsProcessed} records, ${conflictsDetected} conflicts`);

    return createResponse(
      true,
      {
        recordsProcessed,
        conflictsDetected,
        processedRecords: result.processedRecords,
        conflicts: result.conflicts
      },
      'Push sync completed successfully'
    );
  } catch (error) {
    logger.error('Push sync failed:', error);
    syncHistoryOps.completeSession(historyId, recordsProcessed, conflictsDetected, false, error.message);
    return createResponse(false, null, 'Push sync failed', [error.message]);
  }
}

/**
 * Process a single client change
 * @param {Object} change - Client change data
 * @param {string} deviceId - Device identifier
 * @returns {Object} Process result with conflict info if any
 */
function processClientChange(change, deviceId) {
  const { uuid, entityType, data, lastModified, operation } = change;

  // Get current server version
  const serverRecord = dbOperations.getByUuid(entityType, uuid);

  // No conflict if record doesn't exist on server
  if (!serverRecord) {
    if (operation === 'delete') {
      return { status: 'ignored', message: 'Delete operation for non-existent record' };
    }

    // Insert new record
    const recordData = {
      ...data,
      uuid,
      last_modified: lastModified,
      is_synced: 1,
      created_at: data.created_at || getCurrentTimestamp(),
      updated_at: getCurrentTimestamp()
    };

    dbOperations.upsert(entityType, recordData);
    syncQueueOps.enqueue(entityType, uuid, 'create', recordData, deviceId);

    logger.debug(`Created new record: ${entityType}/${uuid}`);
    return { status: 'created' };
  }

  // Handle delete operation
  if (operation === 'delete') {
    // Check if server version is newer
    if (compareTimestamps(serverRecord.last_modified, lastModified) > 0) {
      const conflictId = generateConflictId(uuid, getCurrentTimestamp());
      const conflict = {
        conflictId,
        entityType,
        entityUuid: uuid,
        serverData: serverRecord,
        clientData: { operation: 'delete', lastModified },
        serverTimestamp: serverRecord.last_modified,
        clientTimestamp: lastModified,
        reason: 'Server has newer version, client attempted delete'
      };

      conflictLogOps.logConflict(conflict);
      logger.warn(`Conflict detected for delete: ${entityType}/${uuid}`);
      return { status: 'conflict', conflict };
    }

    // Apply delete
    dbOperations.softDelete(entityType, uuid);
    syncQueueOps.enqueue(entityType, uuid, 'delete', { uuid }, deviceId);
    logger.debug(`Deleted record: ${entityType}/${uuid}`);
    return { status: 'deleted' };
  }

  // Handle update/create with conflict detection
  const comparison = compareTimestamps(serverRecord.last_modified, lastModified);

  if (comparison > 0) {
    // Server version is newer - conflict
    const conflictId = generateConflictId(uuid, getCurrentTimestamp());
    const conflict = {
      conflictId,
      entityType,
      entityUuid: uuid,
      serverData: serverRecord,
      clientData: data,
      serverTimestamp: serverRecord.last_modified,
      clientTimestamp: lastModified,
      reason: 'Server has newer version'
    };

    conflictLogOps.logConflict(conflict);
    logger.warn(`Conflict detected: ${entityType}/${uuid}`);
    return { status: 'conflict', conflict };
  } else if (comparison === 0) {
    // Same timestamp - no change needed
    logger.debug(`No change needed: ${entityType}/${uuid}`);
    return { status: 'unchanged' };
  } else {
    // Client version is newer - update server
    const recordData = {
      ...data,
      uuid,
      last_modified: lastModified,
      is_synced: 1,
      updated_at: getCurrentTimestamp()
    };

    dbOperations.upsert(entityType, recordData);
    syncQueueOps.enqueue(entityType, uuid, 'update', recordData, deviceId);

    logger.debug(`Updated record: ${entityType}/${uuid}`);
    return { status: 'updated' };
  }
}

/**
 * Handle pull sync from server to client
 * Client requests changes from server since last sync
 * @param {Object} query - Pull query parameters
 * @param {string} deviceId - Device identifier
 * @returns {Object} Server changes to sync to client
 */
async function handlePullSync(query, deviceId) {
  const historyId = syncHistoryOps.startSession(deviceId, 'pull');

  try {
    const { lastSyncTimestamp, entityTypes } = query;
    const changes = [];

    // Default to all entity types if not specified
    const entities = entityTypes || ['inventory_items', 'transactions', 'suppliers'];

    logger.info(`Processing pull sync for device ${deviceId} since ${lastSyncTimestamp}`);

    // Get changes for each entity type
    for (const entityType of entities) {
      let records;

      if (lastSyncTimestamp && lastSyncTimestamp !== '0') {
        // Get records modified since last sync
        records = dbOperations.getModifiedSince(entityType, lastSyncTimestamp);
      } else {
        // First sync - get all records
        records = dbOperations.getAll(entityType);
      }

      // Transform records for client
      records.forEach(record => {
        changes.push({
          uuid: record.uuid,
          entityType: entityType,
          data: record,
          lastModified: record.last_modified,
          operation: record.is_deleted ? 'delete' : 'upsert',
          isSynced: true
        });
      });
    }

    syncHistoryOps.completeSession(historyId, changes.length, 0, true);

    logger.info(`Pull sync completed: ${changes.length} changes sent to device ${deviceId}`);

    return createResponse(
      true,
      {
        changes,
        syncTimestamp: getCurrentTimestamp(),
        totalRecords: changes.length
      },
      'Pull sync completed successfully'
    );
  } catch (error) {
    logger.error('Pull sync failed:', error);
    syncHistoryOps.completeSession(historyId, 0, 0, false, error.message);
    return createResponse(false, null, 'Pull sync failed', [error.message]);
  }
}

/**
 * Get sync status for a device
 * @param {string} deviceId - Device identifier
 * @returns {Object} Sync status information
 */
function getSyncStatus(deviceId) {
  try {
    const recentSyncs = syncHistoryOps.getRecent(10);
    const deviceSyncs = recentSyncs.filter(sync => sync.device_id === deviceId);
    const unresolvedConflicts = conflictLogOps.getUnresolved();
    const pendingQueue = syncQueueOps.getPending();

    return createResponse(
      true,
      {
        deviceId,
        lastSync: deviceSyncs[0] || null,
        recentSyncs: deviceSyncs.slice(0, 5),
        unresolvedConflicts: unresolvedConflicts.length,
        pendingQueueSize: pendingQueue.length,
        serverTimestamp: getCurrentTimestamp()
      },
      'Status retrieved successfully'
    );
  } catch (error) {
    logger.error('Failed to get sync status:', error);
    return createResponse(false, null, 'Failed to get status', [error.message]);
  }
}

/**
 * Get unresolved conflicts
 * @param {Object} filters - Optional filters (entityType, entityUuid)
 * @returns {Object} List of unresolved conflicts
 */
function getConflicts(filters = {}) {
  try {
    let conflicts = conflictLogOps.getUnresolved();

    // Apply filters
    if (filters.entityType) {
      conflicts = conflicts.filter(c => c.entity_type === filters.entityType);
    }
    if (filters.entityUuid) {
      conflicts = conflicts.filter(c => c.entity_uuid === filters.entityUuid);
    }

    return createResponse(
      true,
      {
        conflicts,
        totalCount: conflicts.length
      },
      'Conflicts retrieved successfully'
    );
  } catch (error) {
    logger.error('Failed to get conflicts:', error);
    return createResponse(false, null, 'Failed to get conflicts', [error.message]);
  }
}

/**
 * Resolve a conflict
 * @param {string} conflictId - Conflict ID
 * @param {Object} resolution - Resolution details
 * @returns {Object} Resolution result
 */
function resolveConflict(conflictId, resolution) {
  try {
    const { choice, resolvedBy, customData } = resolution;

    runTransaction(() => {
      // Get the conflict
      const db = getDatabase();
      const conflict = db.prepare('SELECT * FROM conflict_log WHERE conflict_id = ?').get(conflictId);

      if (!conflict) {
        throw new Error('Conflict not found');
      }

      let dataToApply;
      let resolutionDesc;

      switch (choice) {
        case 'server':
          // Keep server data
          resolutionDesc = 'Kept server version';
          break;

        case 'client':
          // Apply client data
          const clientData = JSON.parse(conflict.client_data);
          dataToApply = {
            ...clientData,
            uuid: conflict.entity_uuid,
            last_modified: getCurrentTimestamp(),
            is_synced: 1,
            updated_at: getCurrentTimestamp()
          };
          dbOperations.upsert(conflict.entity_type, dataToApply);
          resolutionDesc = 'Applied client version';
          break;

        case 'custom':
          // Apply custom merged data
          if (!customData) {
            throw new Error('Custom data required for custom resolution');
          }
          dataToApply = {
            ...customData,
            uuid: conflict.entity_uuid,
            last_modified: getCurrentTimestamp(),
            is_synced: 1,
            updated_at: getCurrentTimestamp()
          };
          dbOperations.upsert(conflict.entity_type, dataToApply);
          resolutionDesc = 'Applied custom merged version';
          break;

        default:
          throw new Error('Invalid resolution choice');
      }

      // Mark conflict as resolved
      conflictLogOps.resolveConflict(conflictId, resolutionDesc, resolvedBy);
    });

    logger.info(`Conflict ${conflictId} resolved: ${resolution.choice}`);

    return createResponse(
      true,
      { conflictId, resolution: resolution.choice },
      'Conflict resolved successfully'
    );
  } catch (error) {
    logger.error('Failed to resolve conflict:', error);
    return createResponse(false, null, 'Failed to resolve conflict', [error.message]);
  }
}

/**
 * Get sync statistics
 * @returns {Object} Sync statistics
 */
function getSyncStatistics() {
  try {
    const db = getDatabase();

    const stats = {
      totalSyncs: db.prepare('SELECT COUNT(*) as count FROM sync_history').get().count,
      successfulSyncs: db.prepare('SELECT COUNT(*) as count FROM sync_history WHERE success = 1').get().count,
      failedSyncs: db.prepare('SELECT COUNT(*) as count FROM sync_history WHERE success = 0').get().count,
      totalConflicts: db.prepare('SELECT COUNT(*) as count FROM conflict_log').get().count,
      unresolvedConflicts: db.prepare('SELECT COUNT(*) as count FROM conflict_log WHERE resolved_at IS NULL').get().count,
      pendingQueue: db.prepare('SELECT COUNT(*) as count FROM sync_queue WHERE synced_at IS NULL').get().count,
      lastSyncTime: db.prepare('SELECT MAX(started_at) as last_sync FROM sync_history').get().last_sync
    };

    // Entity counts
    stats.entityCounts = {
      inventoryItems: db.prepare('SELECT COUNT(*) as count FROM inventory_items WHERE is_deleted = 0').get().count,
      transactions: db.prepare('SELECT COUNT(*) as count FROM transactions WHERE is_deleted = 0').get().count,
      suppliers: db.prepare('SELECT COUNT(*) as count FROM suppliers WHERE is_deleted = 0').get().count
    };

    return createResponse(
      true,
      stats,
      'Statistics retrieved successfully'
    );
  } catch (error) {
    logger.error('Failed to get statistics:', error);
    return createResponse(false, null, 'Failed to get statistics', [error.message]);
  }
}

module.exports = {
  handlePushSync,
  handlePullSync,
  getSyncStatus,
  getConflicts,
  resolveConflict,
  getSyncStatistics
};
