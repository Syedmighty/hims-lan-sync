const winston = require('winston');
const zlib = require('zlib');
const { promisify } = require('util');

const gzip = promisify(zlib.gzip);
const gunzip = promisify(zlib.gunzip);

/**
 * Logger configuration using Winston
 */
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
  ),
  defaultMeta: { service: 'hims-lan-sync' },
  transports: [
    new winston.transports.File({
      filename: process.env.LOG_FILE || './logs/error.log',
      level: 'error'
    }),
    new winston.transports.File({
      filename: process.env.LOG_FILE || './logs/combined.log'
    }),
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

/**
 * Get current ISO timestamp
 * @returns {string} ISO 8601 timestamp
 */
function getCurrentTimestamp() {
  return new Date().toISOString();
}

/**
 * Get Unix timestamp in milliseconds
 * @returns {number} Unix timestamp
 */
function getUnixTimestamp() {
  return Date.now();
}

/**
 * Compare timestamps to determine which is more recent
 * @param {string} timestamp1 - First ISO timestamp
 * @param {string} timestamp2 - Second ISO timestamp
 * @returns {number} -1 if timestamp1 is older, 1 if newer, 0 if equal
 */
function compareTimestamps(timestamp1, timestamp2) {
  const date1 = new Date(timestamp1);
  const date2 = new Date(timestamp2);

  if (date1 < date2) return -1;
  if (date1 > date2) return 1;
  return 0;
}

/**
 * Compress data using gzip
 * @param {Object} data - Data to compress
 * @returns {Promise<Buffer>} Compressed data
 */
async function compressData(data) {
  try {
    const jsonString = JSON.stringify(data);
    const compressed = await gzip(jsonString);
    logger.debug(`Compressed data from ${jsonString.length} to ${compressed.length} bytes`);
    return compressed;
  } catch (error) {
    logger.error('Compression failed:', error);
    throw error;
  }
}

/**
 * Decompress gzipped data
 * @param {Buffer} compressedData - Compressed data buffer
 * @returns {Promise<Object>} Decompressed data object
 */
async function decompressData(compressedData) {
  try {
    const decompressed = await gunzip(compressedData);
    const jsonString = decompressed.toString('utf8');
    return JSON.parse(jsonString);
  } catch (error) {
    logger.error('Decompression failed:', error);
    throw error;
  }
}

/**
 * Sanitize input to prevent SQL injection
 * @param {string} input - Input string to sanitize
 * @returns {string} Sanitized string
 */
function sanitizeInput(input) {
  if (typeof input !== 'string') return input;
  return input.replace(/['";\\]/g, '');
}

/**
 * Generate a conflict ID for logging
 * @param {string} entityId - Entity UUID
 * @param {string} timestamp - Conflict timestamp
 * @returns {string} Conflict ID
 */
function generateConflictId(entityId, timestamp) {
  return `conflict_${entityId}_${timestamp.replace(/[:.]/g, '-')}`;
}

/**
 * Parse and validate sync payload
 * @param {Object} payload - Sync payload from client
 * @returns {Object} Validation result with isValid flag and errors
 */
function validateSyncPayload(payload) {
  const errors = [];

  if (!payload) {
    errors.push('Payload is required');
    return { isValid: false, errors };
  }

  if (!Array.isArray(payload.changes)) {
    errors.push('changes must be an array');
  }

  if (payload.changes) {
    payload.changes.forEach((change, index) => {
      if (!change.uuid) {
        errors.push(`Change at index ${index} missing uuid`);
      }
      if (!change.lastModified) {
        errors.push(`Change at index ${index} missing lastModified`);
      }
      if (change.isSynced === undefined) {
        errors.push(`Change at index ${index} missing isSynced flag`);
      }
    });
  }

  return {
    isValid: errors.length === 0,
    errors
  };
}

/**
 * Create a standardized API response
 * @param {boolean} success - Success status
 * @param {Object} data - Response data
 * @param {string} message - Response message
 * @param {Array} errors - Error array
 * @returns {Object} Standardized response object
 */
function createResponse(success, data = null, message = '', errors = []) {
  return {
    success,
    timestamp: getCurrentTimestamp(),
    data,
    message,
    errors
  };
}

/**
 * Calculate checksum for data integrity
 * @param {Object} data - Data to checksum
 * @returns {string} Simple hash checksum
 */
function calculateChecksum(data) {
  const crypto = require('crypto');
  const jsonString = JSON.stringify(data);
  return crypto.createHash('sha256').update(jsonString).digest('hex');
}

/**
 * Retry a function with exponential backoff
 * @param {Function} fn - Async function to retry
 * @param {number} maxRetries - Maximum number of retries
 * @param {number} baseDelay - Base delay in milliseconds
 * @returns {Promise<any>} Result of the function
 */
async function retryWithBackoff(fn, maxRetries = 3, baseDelay = 1000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;

      const delay = baseDelay * Math.pow(2, i);
      logger.warn(`Retry ${i + 1}/${maxRetries} after ${delay}ms:`, error.message);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

/**
 * Get local network IP address
 * @returns {string} Local IP address
 */
function getLocalIpAddress() {
  const { networkInterfaces } = require('os');
  const nets = networkInterfaces();

  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      // Skip internal and non-IPv4 addresses
      const familyV4Value = typeof net.family === 'string' ? 'IPv4' : 4;
      if (net.family === familyV4Value && !net.internal) {
        return net.address;
      }
    }
  }

  return '127.0.0.1';
}

module.exports = {
  logger,
  getCurrentTimestamp,
  getUnixTimestamp,
  compareTimestamps,
  compressData,
  decompressData,
  sanitizeInput,
  generateConflictId,
  validateSyncPayload,
  createResponse,
  calculateChecksum,
  retryWithBackoff,
  getLocalIpAddress
};
