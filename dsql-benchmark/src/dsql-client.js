/**
 * Aurora DSQL connection helper
 * Handles IAM token generation and pg client setup
 */

'use strict';

const { DsqlSigner } = require('@aws-sdk/dsql-signer');
const { Pool } = require('pg');

/**
 * Generate an IAM auth token for DSQL
 * @param {string} hostname - DSQL cluster endpoint
 * @param {string} region - AWS region
 * @param {boolean} isAdmin - Whether to generate admin token
 */
async function generateAuthToken(hostname, region, isAdmin = false) {
  const signer = new DsqlSigner({ hostname, region });
  if (isAdmin) {
    return signer.getDbConnectAdminAuthToken();
  }
  return signer.getDbConnectAuthToken();
}

/**
 * Create a pg connection pool for a DSQL cluster
 * @param {string} endpoint - DSQL cluster endpoint
 * @param {string} region - AWS region
 * @param {object} opts - additional pool options
 */
async function createDsqlPool(endpoint, region, opts = {}) {
  const token = await generateAuthToken(endpoint, region, true);

  const pool = new Pool({
    host: endpoint,
    port: 5432,
    database: 'postgres',
    user: 'admin',
    password: token,
    ssl: { rejectUnauthorized: false },
    max: opts.maxConnections || 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
  });

  // Refresh token before it expires (tokens last ~15 min)
  // Re-create pool on each benchmark run to get fresh tokens
  return pool;
}

/**
 * Execute a query with retry on token expiry
 */
async function queryWithRetry(pool, endpoint, region, sql, params = [], maxRetries = 3) {
  let lastErr;
  for (let i = 0; i < maxRetries; i++) {
    const client = await pool.connect();
    try {
      const result = await client.query(sql, params);
      return result;
    } catch (err) {
      lastErr = err;
      // Token expired or connection issues — retry
      if (err.message && (err.message.includes('token') || err.message.includes('SSL') || err.message.includes('connect'))) {
        await new Promise(r => setTimeout(r, 200 * (i + 1)));
        continue;
      }
      throw err;
    } finally {
      client.release();
    }
  }
  throw lastErr;
}

module.exports = { generateAuthToken, createDsqlPool, queryWithRetry };
