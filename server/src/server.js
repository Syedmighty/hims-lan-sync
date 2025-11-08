require('dotenv').config();
const express = require('express');
const cors = require('cors');
const compression = require('compression');
const { initializeDatabase, closeDatabase } = require('./db');
const { initializeDiscovery, stopDiscovery, getDiscoveryStatus } = require('./discovery');
const {
  handlePushSync,
  handlePullSync,
  getSyncStatus,
  getConflicts,
  resolveConflict,
  getSyncStatistics
} = require('./sync');
const { logger, createResponse, getCurrentTimestamp } = require('./utils');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';

// Middleware
app.use(cors());
app.use(compression()); // Enable gzip compression
app.use(express.json({ limit: '10mb' })); // Parse JSON with increased limit for batch operations
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info(`${req.method} ${req.path} ${res.statusCode} - ${duration}ms`);
  });
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json(createResponse(
    true,
    {
      status: 'healthy',
      uptime: process.uptime(),
      timestamp: getCurrentTimestamp()
    },
    'Server is running'
  ));
});

// Discovery status endpoint
app.get('/discovery/status', (req, res) => {
  try {
    const status = getDiscoveryStatus();
    res.json(createResponse(true, status, 'Discovery status retrieved'));
  } catch (error) {
    logger.error('Failed to get discovery status:', error);
    res.status(500).json(createResponse(false, null, 'Failed to get discovery status', [error.message]));
  }
});

// Push sync endpoint - Client pushes changes to server
app.post('/sync/push', async (req, res) => {
  try {
    const { deviceId } = req.headers;

    if (!deviceId) {
      return res.status(400).json(createResponse(false, null, 'Device ID required', ['Missing deviceId header']));
    }

    logger.info(`Received push sync request from device: ${deviceId}`);

    const result = await handlePushSync(req.body, deviceId);

    if (!result.success) {
      return res.status(400).json(result);
    }

    res.json(result);
  } catch (error) {
    logger.error('Push sync endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Pull sync endpoint - Client pulls changes from server
app.post('/sync/pull', async (req, res) => {
  try {
    const { deviceId } = req.headers;

    if (!deviceId) {
      return res.status(400).json(createResponse(false, null, 'Device ID required', ['Missing deviceId header']));
    }

    logger.info(`Received pull sync request from device: ${deviceId}`);

    const result = await handlePullSync(req.body, deviceId);

    if (!result.success) {
      return res.status(400).json(result);
    }

    res.json(result);
  } catch (error) {
    logger.error('Pull sync endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Get sync status for a device
app.get('/sync/status', (req, res) => {
  try {
    const { deviceId } = req.headers;

    if (!deviceId) {
      return res.status(400).json(createResponse(false, null, 'Device ID required', ['Missing deviceId header']));
    }

    const result = getSyncStatus(deviceId);
    res.json(result);
  } catch (error) {
    logger.error('Sync status endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Get conflicts
app.get('/conflicts', (req, res) => {
  try {
    const filters = {
      entityType: req.query.entityType,
      entityUuid: req.query.entityUuid
    };

    const result = getConflicts(filters);
    res.json(result);
  } catch (error) {
    logger.error('Get conflicts endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Resolve conflict
app.post('/conflicts/:conflictId/resolve', (req, res) => {
  try {
    const { conflictId } = req.params;
    const resolution = req.body;

    if (!resolution.choice || !['server', 'client', 'custom'].includes(resolution.choice)) {
      return res.status(400).json(createResponse(
        false,
        null,
        'Invalid resolution choice',
        ['Choice must be: server, client, or custom']
      ));
    }

    const result = resolveConflict(conflictId, resolution);

    if (!result.success) {
      return res.status(400).json(result);
    }

    res.json(result);
  } catch (error) {
    logger.error('Resolve conflict endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Get sync statistics
app.get('/stats', (req, res) => {
  try {
    const result = getSyncStatistics();
    res.json(result);
  } catch (error) {
    logger.error('Statistics endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// Batch sync endpoint - Combined push and pull
app.post('/sync/batch', async (req, res) => {
  try {
    const { deviceId } = req.headers;
    const { pushPayload, pullQuery } = req.body;

    if (!deviceId) {
      return res.status(400).json(createResponse(false, null, 'Device ID required', ['Missing deviceId header']));
    }

    logger.info(`Received batch sync request from device: ${deviceId}`);

    const results = {
      push: null,
      pull: null
    };

    // Handle push if provided
    if (pushPayload && pushPayload.changes && pushPayload.changes.length > 0) {
      results.push = await handlePushSync(pushPayload, deviceId);
    }

    // Handle pull if requested
    if (pullQuery) {
      results.pull = await handlePullSync(pullQuery, deviceId);
    }

    const success = (!results.push || results.push.success) && (!results.pull || results.pull.success);

    res.json(createResponse(
      success,
      results,
      'Batch sync completed'
    ));
  } catch (error) {
    logger.error('Batch sync endpoint error:', error);
    res.status(500).json(createResponse(false, null, 'Internal server error', [error.message]));
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json(createResponse(false, null, 'Endpoint not found', [`${req.method} ${req.path} not found`]));
});

// Error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json(createResponse(false, null, 'Internal server error', [err.message]));
});

// Graceful shutdown
function gracefulShutdown(signal) {
  logger.info(`${signal} received, shutting down gracefully...`);

  server.close(() => {
    logger.info('HTTP server closed');

    // Stop discovery service
    stopDiscovery();

    // Close database
    closeDatabase();

    logger.info('Shutdown complete');
    process.exit(0);
  });

  // Force shutdown after 10 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
}

// Initialize and start server
let server;

function startServer() {
  try {
    // Initialize database
    logger.info('Initializing database...');
    initializeDatabase();

    // Initialize UDP discovery
    logger.info('Initializing discovery service...');
    initializeDiscovery();

    // Start HTTP server
    server = app.listen(PORT, HOST, () => {
      logger.info('='.repeat(60));
      logger.info('HIMS LAN Sync Server Started');
      logger.info('='.repeat(60));
      logger.info(`HTTP Server: http://${HOST}:${PORT}`);
      logger.info(`UDP Discovery: Port ${process.env.UDP_PORT || 9999}`);
      logger.info(`Database: ${process.env.DB_PATH || './hims_master.db'}`);
      logger.info('='.repeat(60));
    });

    // Setup shutdown handlers
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));

  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

module.exports = app;
