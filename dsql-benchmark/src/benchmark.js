/**
 * TPC-C Benchmark Runner for Aurora DSQL
 * Measures latency for SELECT, INSERT, UPDATE across single and multi-region clusters
 */

'use strict';

const { createDsqlPool, generateAuthToken } = require('./dsql-client');
const { Pool } = require('pg');
const { Command } = require('commander');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, '..', 'config.json');
const RESULTS_DIR = path.join(__dirname, '..', 'results');

// ─── Statistics ─────────────────────────────────────────────────────────────

function calcStats(latencies) {
  if (!latencies.length) return null;
  const sorted = [...latencies].sort((a, b) => a - b);
  const sum = sorted.reduce((a, b) => a + b, 0);
  const n = sorted.length;
  return {
    count: n,
    min: sorted[0],
    max: sorted[n - 1],
    avg: sum / n,
    p50: sorted[Math.floor(n * 0.50)],
    p95: sorted[Math.floor(n * 0.95)],
    p99: sorted[Math.floor(n * 0.99)],
  };
}

function round2(x) { return Math.round(x * 100) / 100; }

function formatStats(stats) {
  if (!stats) return 'no data';
  return `avg=${round2(stats.avg)}ms p50=${round2(stats.p50)}ms p95=${round2(stats.p95)}ms p99=${round2(stats.p99)}ms min=${round2(stats.min)}ms max=${round2(stats.max)}ms`;
}

// ─── Data Generators ─────────────────────────────────────────────────────────

function randomStr(len) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return Array.from({ length: len }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }

// ─── Workload Implementations ─────────────────────────────────────────────────

async function runSelectWorkload(pool, count) {
  const latencies = [];
  for (let i = 0; i < count; i++) {
    const wId = randomInt(1, 10);
    const t0 = Date.now();
    await pool.query(
      'SELECT w_id, w_name, w_tax FROM warehouse WHERE w_id = $1',
      [wId]
    );
    latencies.push(Date.now() - t0);
  }
  return latencies;
}

async function runInsertWorkload(pool, count) {
  const latencies = [];
  for (let i = 0; i < count; i++) {
    const iId = randomInt(100000, 999999);
    const t0 = Date.now();
    try {
      await pool.query(
        `INSERT INTO item (i_id, i_im_id, i_name, i_price, i_data)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (i_id) DO NOTHING`,
        [iId, randomInt(1, 10000), randomStr(24), (randomInt(100, 9999) / 100), randomStr(26)]
      );
    } catch (err) {
      // Conflict is fine — still measure latency
    }
    latencies.push(Date.now() - t0);
  }
  return latencies;
}

async function runUpdateWorkload(pool, count) {
  const latencies = [];
  
  // Ensure we have some warehouse rows to update
  try {
    for (let wId = 1; wId <= 10; wId++) {
      await pool.query(
        `INSERT INTO warehouse (w_id, w_name, w_street_1, w_street_2, w_city, w_state, w_zip, w_tax, w_ytd)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (w_id) DO NOTHING`,
        [wId, randomStr(10), randomStr(20), randomStr(20), randomStr(20), 'NY', '123456789', 0.1000, 300000.00]
      );
    }
  } catch (err) { /* ignore */ }
  
  for (let i = 0; i < count; i++) {
    const itemId = randomInt(1, 100);
    const newPrice = (randomInt(100, 9999) / 100);
    const t0 = Date.now();
    await pool.query(
      'UPDATE item SET i_price = $1 WHERE i_id = $2',
      [newPrice, itemId]
    );
    latencies.push(Date.now() - t0);
  }
  return latencies;
}

async function runNewOrderWorkload(pool, count) {
  const latencies = [];
  
  // Seed some required data
  try {
    for (let wId = 1; wId <= 3; wId++) {
      await pool.query(
        `INSERT INTO warehouse (w_id, w_name, w_street_1, w_street_2, w_city, w_state, w_zip, w_tax, w_ytd)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT (w_id) DO NOTHING`,
        [wId, randomStr(10), randomStr(20), randomStr(20), randomStr(20), 'CA', '900010000', 0.0800, 300000.00]
      );
      for (let dId = 1; dId <= 10; dId++) {
        await pool.query(
          `INSERT INTO district (d_id, d_w_id, d_name, d_street_1, d_street_2, d_city, d_state, d_zip, d_tax, d_ytd, d_next_o_id)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (d_w_id, d_id) DO NOTHING`,
          [dId, wId, randomStr(10), randomStr(20), randomStr(20), randomStr(20), 'CA', '900010000', 0.1000, 30000.00, 3001]
        );
      }
    }
  } catch (err) { /* ignore seeding errors */ }
  
  for (let i = 0; i < count; i++) {
    const wId = randomInt(1, 3);
    const dId = randomInt(1, 10);
    const oId = randomInt(3001, 99999);
    const cId = randomInt(1, 3000);
    const t0 = Date.now();
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO orders (o_id, o_d_id, o_w_id, o_c_id, o_entry_d, o_carrier_id, o_ol_cnt, o_all_local)
         VALUES ($1,$2,$3,$4,NOW(),$5,$6,$7) ON CONFLICT DO NOTHING`,
        [oId, dId, wId, cId, null, randomInt(5, 15), 1]
      );
      await client.query(
        `INSERT INTO new_order (no_o_id, no_d_id, no_w_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`,
        [oId, dId, wId]
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
    } finally {
      client.release();
    }
    latencies.push(Date.now() - t0);
  }
  return latencies;
}

// ─── Pool creation with fresh token ──────────────────────────────────────────

async function freshPool(endpoint, region) {
  return createDsqlPool(endpoint, region, { maxConnections: 5 });
}

// ─── Main Benchmark ───────────────────────────────────────────────────────────

async function runBenchmark(options) {
  const { workloads, counts, outputFile } = options;
  
  if (!fs.existsSync(CONFIG_FILE)) {
    console.error('config.json not found. Run scripts/setup-clusters.sh first.');
    process.exit(1);
  }
  
  const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  const results = {
    timestamp: new Date().toISOString(),
    config: { workloads, counts },
    singleRegion: {},
    multiRegion: {},
  };
  
  const workloadFns = {
    select: runSelectWorkload,
    insert: runInsertWorkload,
    update: runUpdateWorkload,
    neworder: runNewOrderWorkload,
  };
  
  // ── Single-region ──
  if (config.singleRegion && config.singleRegion.endpoint) {
    const { endpoint, region } = config.singleRegion;
    console.log(`\n═══ Single-Region Benchmark (${region}) ═══`);
    console.log(`    Endpoint: ${endpoint}`);
    
    for (const wl of workloads) {
      if (!workloadFns[wl]) { console.warn(`Unknown workload: ${wl}`); continue; }
      results.singleRegion[wl] = {};
      
      for (const count of counts) {
        console.log(`\n  [${wl.toUpperCase()}] ${count} operations...`);
        const pool = await freshPool(endpoint, region);
        try {
          const latencies = await workloadFns[wl](pool, count);
          const stats = calcStats(latencies);
          results.singleRegion[wl][count] = stats;
          console.log(`    ${formatStats(stats)}`);
        } catch (err) {
          console.error(`    ERROR: ${err.message}`);
          results.singleRegion[wl][count] = { error: err.message };
        } finally {
          await pool.end().catch(() => {});
        }
      }
    }
  } else {
    console.warn('Single-region cluster not configured.');
  }
  
  // ── Multi-region ──
  if (config.multiRegion && config.multiRegion.primaryEndpoint) {
    const { primaryEndpoint, primaryRegion } = config.multiRegion;
    console.log(`\n═══ Multi-Region Benchmark (${primaryRegion}) ═══`);
    console.log(`    Endpoint: ${primaryEndpoint}`);
    
    for (const wl of workloads) {
      if (!workloadFns[wl]) continue;
      results.multiRegion[wl] = {};
      
      for (const count of counts) {
        console.log(`\n  [${wl.toUpperCase()}] ${count} operations...`);
        const pool = await freshPool(primaryEndpoint, primaryRegion);
        try {
          const latencies = await workloadFns[wl](pool, count);
          const stats = calcStats(latencies);
          results.multiRegion[wl][count] = stats;
          console.log(`    ${formatStats(stats)}`);
        } catch (err) {
          console.error(`    ERROR: ${err.message}`);
          results.multiRegion[wl][count] = { error: err.message };
        } finally {
          await pool.end().catch(() => {});
        }
      }
    }
  } else {
    console.warn('Multi-region cluster not configured.');
  }
  
  // ── Save results ──
  if (!fs.existsSync(RESULTS_DIR)) fs.mkdirSync(RESULTS_DIR, { recursive: true });
  const filename = outputFile || `benchmark-${Date.now()}.json`;
  const filePath = path.join(RESULTS_DIR, filename);
  fs.writeFileSync(filePath, JSON.stringify(results, null, 2));
  console.log(`\n✓ Results saved to ${filePath}`);
  
  return { results, filePath };
}

// ─── CLI ─────────────────────────────────────────────────────────────────────

const program = new Command();
program
  .name('dsql-benchmark')
  .description('TPC-C based benchmark for Aurora DSQL')
  .option('-w, --workloads <list>', 'Comma-separated workloads: select,insert,update,neworder', 'select,insert,update')
  .option('-c, --counts <list>', 'Comma-separated record counts', '1,100,1000')
  .option('-o, --output <file>', 'Output JSON filename (saved in results/)')
  .option('--visualize', 'Generate HTML visualization after benchmark')
  .parse(process.argv);

const opts = program.opts();
const workloads = opts.workloads.split(',').map(s => s.trim());
const counts = opts.counts.split(',').map(s => parseInt(s.trim(), 10));

runBenchmark({ workloads, counts, outputFile: opts.output })
  .then(({ results, filePath }) => {
    if (opts.visualize) {
      const { generateHtml } = require('./visualize');
      const htmlPath = filePath.replace('.json', '.html');
      generateHtml(results, htmlPath);
      console.log(`✓ Visualization saved to ${htmlPath}`);
    }
    console.log('\n✓ Benchmark complete!');
  })
  .catch(err => {
    console.error('Benchmark failed:', err);
    process.exit(1);
  });
