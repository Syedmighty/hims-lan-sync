const dgram = require('dgram');
const { logger, getLocalIpAddress } = require('./utils');

let discoveryServer = null;
let broadcastInterval = null;

/**
 * Initialize UDP discovery service
 * Broadcasts server presence on LAN for client discovery
 */
function initializeDiscovery() {
  const UDP_PORT = parseInt(process.env.UDP_PORT) || 9999;
  const SERVER_PORT = parseInt(process.env.PORT) || 5000;
  const DISCOVERY_INTERVAL = parseInt(process.env.DISCOVERY_INTERVAL) || 5000;

  // Create UDP socket for broadcasting
  discoveryServer = dgram.createSocket('udp4');

  discoveryServer.on('error', (err) => {
    logger.error('Discovery server error:', err);
    discoveryServer.close();
  });

  discoveryServer.on('message', (msg, rinfo) => {
    try {
      const message = JSON.parse(msg.toString());

      // Handle discovery request from client
      if (message.type === 'HIMS_DISCOVERY_REQUEST') {
        logger.info(`Discovery request from ${rinfo.address}:${rinfo.port}`);

        // Respond with server information
        const response = {
          type: 'HIMS_DISCOVERY_RESPONSE',
          serverIp: getLocalIpAddress(),
          serverPort: SERVER_PORT,
          timestamp: new Date().toISOString(),
          serverName: 'HIMS-LAN-Server',
          version: '1.0.0'
        };

        const responseBuffer = Buffer.from(JSON.stringify(response));

        discoveryServer.send(
          responseBuffer,
          0,
          responseBuffer.length,
          rinfo.port,
          rinfo.address,
          (err) => {
            if (err) {
              logger.error('Failed to send discovery response:', err);
            } else {
              logger.info(`Discovery response sent to ${rinfo.address}:${rinfo.port}`);
            }
          }
        );
      }
    } catch (error) {
      logger.error('Error processing discovery message:', error);
    }
  });

  discoveryServer.on('listening', () => {
    const address = discoveryServer.address();
    logger.info(`UDP Discovery server listening on ${address.address}:${address.port}`);

    // Enable broadcast
    discoveryServer.setBroadcast(true);

    // Start periodic broadcast
    startPeriodicBroadcast(UDP_PORT, SERVER_PORT, DISCOVERY_INTERVAL);
  });

  // Bind to UDP port
  discoveryServer.bind(UDP_PORT);
}

/**
 * Start periodic broadcast of server presence
 * @param {number} udpPort - UDP port for broadcasting
 * @param {number} serverPort - HTTP server port
 * @param {number} interval - Broadcast interval in milliseconds
 */
function startPeriodicBroadcast(udpPort, serverPort, interval) {
  if (broadcastInterval) {
    clearInterval(broadcastInterval);
  }

  broadcastInterval = setInterval(() => {
    broadcastServerPresence(udpPort, serverPort);
  }, interval);

  // Send initial broadcast immediately
  broadcastServerPresence(udpPort, serverPort);
}

/**
 * Broadcast server presence to LAN
 * @param {number} udpPort - UDP port for broadcasting
 * @param {number} serverPort - HTTP server port
 */
function broadcastServerPresence(udpPort, serverPort) {
  const announcement = {
    type: 'HIMS_SERVER_ANNOUNCEMENT',
    serverIp: getLocalIpAddress(),
    serverPort: serverPort,
    timestamp: new Date().toISOString(),
    serverName: 'HIMS-LAN-Server',
    version: '1.0.0',
    capabilities: [
      'sync',
      'inventory',
      'transactions',
      'suppliers'
    ]
  };

  const message = Buffer.from(JSON.stringify(announcement));

  if (!discoveryServer) {
    logger.warn('Discovery server not initialized, skipping broadcast');
    return;
  }

  // Broadcast to subnet
  discoveryServer.send(
    message,
    0,
    message.length,
    udpPort,
    '255.255.255.255',
    (err) => {
      if (err) {
        logger.error('Broadcast error:', err);
      } else {
        logger.debug(`Server presence broadcast sent on port ${udpPort}`);
      }
    }
  );
}

/**
 * Send unicast message to specific client
 * @param {string} clientIp - Client IP address
 * @param {number} clientPort - Client port
 * @param {Object} message - Message object to send
 */
function sendToClient(clientIp, clientPort, message) {
  if (!discoveryServer) {
    logger.warn('Discovery server not initialized');
    return;
  }

  const buffer = Buffer.from(JSON.stringify(message));

  discoveryServer.send(
    buffer,
    0,
    buffer.length,
    clientPort,
    clientIp,
    (err) => {
      if (err) {
        logger.error(`Failed to send message to ${clientIp}:${clientPort}:`, err);
      } else {
        logger.debug(`Message sent to ${clientIp}:${clientPort}`);
      }
    }
  );
}

/**
 * Request client status update
 * Used to ping clients and check their availability
 * @param {string} clientIp - Client IP address
 * @param {number} clientPort - Client UDP port
 */
function requestClientStatus(clientIp, clientPort) {
  const statusRequest = {
    type: 'HIMS_STATUS_REQUEST',
    timestamp: new Date().toISOString()
  };

  sendToClient(clientIp, clientPort, statusRequest);
}

/**
 * Notify clients of data changes
 * @param {string} changeType - Type of change (inventory_update, transaction, etc.)
 * @param {Object} changeData - Change details
 */
function notifyClientsOfChange(changeType, changeData) {
  const notification = {
    type: 'HIMS_DATA_CHANGE',
    changeType: changeType,
    changeData: changeData,
    timestamp: new Date().toISOString()
  };

  // Broadcast notification to all clients
  const message = Buffer.from(JSON.stringify(notification));
  const UDP_PORT = parseInt(process.env.UDP_PORT) || 9999;

  if (!discoveryServer) {
    logger.warn('Discovery server not initialized, cannot notify clients');
    return;
  }

  discoveryServer.send(
    message,
    0,
    message.length,
    UDP_PORT,
    '255.255.255.255',
    (err) => {
      if (err) {
        logger.error('Failed to notify clients:', err);
      } else {
        logger.info(`Clients notified of ${changeType}`);
      }
    }
  );
}

/**
 * Stop discovery service
 */
function stopDiscovery() {
  if (broadcastInterval) {
    clearInterval(broadcastInterval);
    broadcastInterval = null;
  }

  if (discoveryServer) {
    discoveryServer.close(() => {
      logger.info('Discovery server closed');
    });
    discoveryServer = null;
  }
}

/**
 * Get discovery server status
 * @returns {Object} Status information
 */
function getDiscoveryStatus() {
  return {
    isRunning: discoveryServer !== null,
    localIp: getLocalIpAddress(),
    udpPort: parseInt(process.env.UDP_PORT) || 9999,
    serverPort: parseInt(process.env.PORT) || 5000,
    broadcastInterval: parseInt(process.env.DISCOVERY_INTERVAL) || 5000
  };
}

module.exports = {
  initializeDiscovery,
  stopDiscovery,
  broadcastServerPresence,
  sendToClient,
  requestClientStatus,
  notifyClientsOfChange,
  getDiscoveryStatus
};
