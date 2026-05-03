/**
 * TPC-C Schema Setup for Aurora DSQL
 * Creates all standard TPC-C tables
 * Note: DSQL doesn't support SERIAL, regular CREATE INDEX, or some PG types
 */

'use strict';

const { createDsqlPool } = require('./dsql-client');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, '..', 'config.json');

// TPC-C table definitions (DSQL-compatible)
const TABLES = [
  `CREATE TABLE IF NOT EXISTS item (i_id INTEGER NOT NULL, i_im_id INTEGER, i_name VARCHAR(24), i_price NUMERIC(5,2), i_data VARCHAR(50), PRIMARY KEY (i_id))`,
  `CREATE TABLE IF NOT EXISTS warehouse (w_id INTEGER NOT NULL, w_name VARCHAR(10), w_street_1 VARCHAR(20), w_street_2 VARCHAR(20), w_city VARCHAR(20), w_state CHAR(2), w_zip CHAR(9), w_tax NUMERIC(4,4), w_ytd NUMERIC(12,2), PRIMARY KEY (w_id))`,
  `CREATE TABLE IF NOT EXISTS district (d_id INTEGER NOT NULL, d_w_id INTEGER NOT NULL, d_name VARCHAR(10), d_street_1 VARCHAR(20), d_street_2 VARCHAR(20), d_city VARCHAR(20), d_state CHAR(2), d_zip CHAR(9), d_tax NUMERIC(4,4), d_ytd NUMERIC(12,2), d_next_o_id INTEGER, PRIMARY KEY (d_w_id, d_id))`,
  `CREATE TABLE IF NOT EXISTS customer (c_id INTEGER NOT NULL, c_d_id INTEGER NOT NULL, c_w_id INTEGER NOT NULL, c_first VARCHAR(16), c_middle CHAR(2), c_last VARCHAR(16), c_street_1 VARCHAR(20), c_street_2 VARCHAR(20), c_city VARCHAR(20), c_state CHAR(2), c_zip CHAR(9), c_phone CHAR(16), c_since TIMESTAMP, c_credit CHAR(2), c_credit_lim NUMERIC(12,2), c_discount NUMERIC(4,4), c_balance NUMERIC(12,2), c_ytd_payment NUMERIC(12,2), c_payment_cnt INTEGER, c_delivery_cnt INTEGER, c_data VARCHAR(500), PRIMARY KEY (c_w_id, c_d_id, c_id))`,
  `CREATE TABLE IF NOT EXISTS history (h_id INTEGER NOT NULL DEFAULT 0, h_c_id INTEGER, h_c_d_id INTEGER, h_c_w_id INTEGER, h_d_id INTEGER, h_w_id INTEGER, h_date TIMESTAMP, h_amount NUMERIC(6,2), h_data VARCHAR(24), PRIMARY KEY (h_id))`,
  `CREATE TABLE IF NOT EXISTS orders (o_id INTEGER NOT NULL, o_d_id INTEGER NOT NULL, o_w_id INTEGER NOT NULL, o_c_id INTEGER, o_entry_d TIMESTAMP, o_carrier_id INTEGER, o_ol_cnt INTEGER, o_all_local INTEGER, PRIMARY KEY (o_w_id, o_d_id, o_id))`,
  `CREATE TABLE IF NOT EXISTS new_order (no_o_id INTEGER NOT NULL, no_d_id INTEGER NOT NULL, no_w_id INTEGER NOT NULL, PRIMARY KEY (no_w_id, no_d_id, no_o_id))`,
  `CREATE TABLE IF NOT EXISTS order_line (ol_o_id INTEGER NOT NULL, ol_d_id INTEGER NOT NULL, ol_w_id INTEGER NOT NULL, ol_number INTEGER NOT NULL, ol_i_id INTEGER, ol_supply_w_id INTEGER, ol_delivery_d TIMESTAMP, ol_quantity INTEGER, ol_amount NUMERIC(6,2), ol_dist_info CHAR(24), PRIMARY KEY (ol_w_id, ol_d_id, ol_o_id, ol_number))`,
  `CREATE TABLE IF NOT EXISTS stock (s_i_id INTEGER NOT NULL, s_w_id INTEGER NOT NULL, s_quantity INTEGER, s_dist_01 CHAR(24), s_dist_02 CHAR(24), s_dist_03 CHAR(24), s_dist_04 CHAR(24), s_dist_05 CHAR(24), s_dist_06 CHAR(24), s_dist_07 CHAR(24), s_dist_08 CHAR(24), s_dist_09 CHAR(24), s_dist_10 CHAR(24), s_ytd INTEGER, s_order_cnt INTEGER, s_remote_cnt INTEGER, s_data VARCHAR(50), PRIMARY KEY (s_w_id, s_i_id))`
];

async function setupSchema(endpoint, region, label) {
  console.log(`\n[${label}] Setting up TPC-C schema on ${endpoint} (${region})...`);

  let pool;
  try {
    pool = await createDsqlPool(endpoint, region);
    const client = await pool.connect();

    try {
      for (const sql of TABLES) {
        try {
          await client.query(sql);
          const name = sql.match(/CREATE TABLE IF NOT EXISTS (\w+)/)[1];
          console.log(`  ✓ ${name}`);
        } catch (err) {
          console.error(`  ✗ Error: ${err.message}`);
        }
      }

      // Verify
      const res = await client.query("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename");
      console.log(`[${label}] Tables created: ${res.rows.map(r => r.tablename).join(', ')}`);
    } finally {
      client.release();
    }
  } catch (err) {
    console.error(`[${label}] Connection failed: ${err.message}`);
    console.error(`  Cluster may still be provisioning. Try again later.`);
    return false;
  } finally {
    if (pool) await pool.end();
  }
  return true;
}

async function main() {
  if (!fs.existsSync(CONFIG_FILE)) {
    console.error('config.json not found. Run scripts/setup-clusters.sh first.');
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  let allOk = true;

  if (config.singleRegion && config.singleRegion.endpoint) {
    const ok = await setupSchema(config.singleRegion.endpoint, config.singleRegion.region, 'single-region');
    if (!ok) allOk = false;
  }

  if (config.multiRegion && config.multiRegion.primaryEndpoint) {
    const ok = await setupSchema(config.multiRegion.primaryEndpoint, config.multiRegion.primaryRegion, 'multi-region');
    if (!ok) allOk = false;
  }

  if (!allOk) {
    console.log('\n⚠️  Some clusters were not reachable. Re-run this script once they are ACTIVE.');
    process.exit(1);
  }

  console.log('\n✅ Schema setup complete on all clusters.');
}

main().catch(err => {
  console.error('Schema setup failed:', err.message);
  process.exit(1);
});
