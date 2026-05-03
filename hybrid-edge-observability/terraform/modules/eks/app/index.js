/**
 * Payment API — EKS Service with DSQL Backend
 * Propagates X-Transaction-ID for end-to-end correlation.
 */

const express = require('express');
const { DsqlSigner } = require('@aws-sdk/dsql-signer');
const { Pool } = require('pg');

const PORT = process.env.PORT || 8080;
const DSQL_ENDPOINT = process.env.DSQL_ENDPOINT;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';
const POD_NAME = process.env.HOSTNAME || 'unknown-pod';

const app = express();
app.use(express.json());

let pool;

async function getPool() {
  if (pool) return pool;
  const signer = new DsqlSigner({ hostname: DSQL_ENDPOINT, region: AWS_REGION });
  const token = await signer.getDbConnectAdminAuthToken();
  pool = new Pool({
    host: DSQL_ENDPOINT,
    port: 5432,
    user: 'admin',
    password: token,
    database: 'postgres',
    ssl: { rejectUnauthorized: false },
    max: 10,
    idleTimeoutMillis: 30000,
  });
  return pool;
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', pod: POD_NAME, timestamp: new Date().toISOString() });
});

app.post('/api/payment', async (req, res) => {
  const transactionId = req.headers['x-transaction-id'] || 'unknown';
  const edgeRegion = req.headers['x-edge-region'] || 'unknown';
  const edgeTimestamp = req.headers['x-edge-timestamp'] || '0';

  try {
    const { action, amount, currency, card_last4, merchant_id } = req.body;
    const db = await getPool();

    await db.query(
      `INSERT INTO payments (transaction_id, action, amount, currency, card_last4, merchant_id, edge_region, pod_name, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
      [transactionId, action, amount, currency, card_last4, merchant_id, edgeRegion, POD_NAME]
    );

    const response = {
      status: 'approved',
      transaction_id: transactionId,
      amount,
      currency,
      merchant_id,
      processed_by: POD_NAME,
      edge_region: edgeRegion,
      edge_to_pod_ms: edgeTimestamp !== '0' ?
        Math.round((Date.now() / 1000 - parseFloat(edgeTimestamp)) * 1000) : null,
      timestamp: new Date().toISOString(),
    };

    res.set('X-Transaction-ID', transactionId);
    res.set('X-Processed-By', POD_NAME);
    res.json(response);
  } catch (err) {
    console.error(`[${transactionId}] Error:`, err.message);
    res.status(500).json({ status: 'error', transaction_id: transactionId, error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`[PaymentAPI] Pod=${POD_NAME} Port=${PORT} DSQL=${DSQL_ENDPOINT}`);
});
