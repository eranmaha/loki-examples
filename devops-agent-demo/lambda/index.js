const { DsqlSigner } = require("@aws-sdk/dsql-signer");
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const { Client } = require("pg");

const ssm = new SSMClient({});
const DSQL_ENDPOINT = process.env.DSQL_ENDPOINT;
const DSQL_REGION = process.env.DSQL_REGION;
const SSM_SLEEP_PARAM = process.env.SSM_SLEEP_PARAM;

async function getToken() {
  const signer = new DsqlSigner({ hostname: DSQL_ENDPOINT, region: DSQL_REGION });
  return await signer.getDbConnectAdminAuthToken();
}

async function getSleepSeconds() {
  try {
    const result = await ssm.send(new GetParameterCommand({ Name: SSM_SLEEP_PARAM }));
    return parseInt(result.Parameter.Value) || 0;
  } catch (e) {
    return 0;
  }
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function queryDb() {
  const token = await getToken();
  const client = new Client({
    host: DSQL_ENDPOINT,
    port: 5432,
    user: "admin",
    password: token,
    database: "postgres",
    ssl: { rejectUnauthorized: false }
  });
  await client.connect();
  
  // Ensure table exists
  await client.query(`
    CREATE TABLE IF NOT EXISTS app_events (
      id SERIAL PRIMARY KEY,
      event_type VARCHAR(50),
      message TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    )
  `);
  
  // Insert a sample event
  await client.query(
    `INSERT INTO app_events (event_type, message) VALUES ($1, $2)`,
    ['page_view', `View at ${new Date().toISOString()}`]
  );
  
  // Get latest 10 events
  const result = await client.query(
    `SELECT * FROM app_events ORDER BY created_at DESC LIMIT 10`
  );
  
  await client.end();
  return result.rows;
}

exports.handler = async (event) => {
  const path = event.rawPath || '/';
  const method = event.requestContext?.http?.method || 'GET';

  // Serve test page
  if (path === '/test' || path === '/') {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'text/html', 'Cache-Control': 'no-cache' },
      body: getTestPageHtml()
    };
  }

  // Health check
  if (path === '/health') {
    return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status: 'ok' }) };
  }

  // Data endpoint
  if (path === '/data') {
    try {
      // Check for injected sleep
      const sleepSec = await getSleepSeconds();
      if (sleepSec > 0) {
        console.log(`[INJECTED DELAY] Sleeping ${sleepSec}s...`);
        await sleep(sleepSec * 1000);
      }

      const rows = await queryDb();
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify({ success: true, data: rows, sleepInjected: sleepSec })
      };
    } catch (err) {
      console.error('[ERROR]', err.message, err.stack);
      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify({ success: false, error: err.message })
      };
    }
  }

  return { statusCode: 404, body: 'Not Found' };
};

function getTestPageHtml() {
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>DevOps Agent Demo - App</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:#0d1117;color:#c9d1d9;padding:20px;min-height:100vh}
.container{max-width:1000px;margin:0 auto}
h1{color:#58a6ff;margin-bottom:8px}
.sub{color:#8b949e;margin-bottom:24px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:16px}
@media(max-width:768px){.grid{grid-template-columns:1fr}}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px}
.card h3{color:#58a6ff;font-size:13px;text-transform:uppercase;margin-bottom:12px}
button{border:none;padding:10px 20px;border-radius:6px;cursor:pointer;font-size:13px;font-weight:500;margin:4px;transition:all 0.2s}
.btn-primary{background:#238636;color:#fff}
.btn-primary:hover{background:#2ea043}
.btn-danger{background:#da3633;color:#fff}
.btn-danger:hover{background:#f85149}
.btn-warning{background:#9e6a03;color:#fff}
.btn-warning:hover{background:#bb8009}
.btn-secondary{background:#30363d;color:#c9d1d9}
.btn-secondary:hover{background:#484f58}
#status{padding:12px;border-radius:8px;margin-bottom:16px;font-size:13px;display:none}
.status-ok{background:#0d2818;border:1px solid #3fb950;color:#3fb950;display:block}
.status-error{background:#2d1214;border:1px solid #da3633;color:#f85149;display:block}
.status-loading{background:#1c1c1c;border:1px solid #484f58;color:#8b949e;display:block}
table{width:100%;border-collapse:collapse;font-size:12px;margin-top:12px}
th,td{padding:8px;text-align:left;border-bottom:1px solid #30363d}
th{color:#58a6ff;font-weight:600}
#log{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:12px;font-family:monospace;font-size:11px;max-height:200px;overflow-y:auto;white-space:pre-wrap;margin-top:12px}
.inject-desc{color:#8b949e;font-size:11px;margin-top:4px}
</style></head><body>
<div class="container">
<h1>Serverless App Dashboard</h1>
<p class="sub">Connected to Aurora DSQL | DevOps Agent monitors this app</p>
<div id="status"></div>
<div class="grid">
<div class="card">
<h3>Application</h3>
<button class="btn-primary" onclick="fetchData()">Fetch Data</button>
<button class="btn-primary" onclick="autoFetch()">Auto-Fetch (every 3s)</button>
<button class="btn-secondary" onclick="stopAuto()">Stop</button>
<div id="data-table"></div>
</div>
<div class="card">
<h3>Error Injection</h3>
<button class="btn-danger" onclick="inject('remove_dsql_permission')">Remove DSQL Permission</button>
<p class="inject-desc">Removes Lambda IAM permission to connect to DSQL. Causes immediate 500 errors. Alarm triggers after 3 errors.</p>
<br>
<button class="btn-warning" onclick="inject('inject_timeout')">Inject Timeout (20s sleep)</button>
<p class="inject-desc">Sets SSM parameter to make Lambda sleep 20s before responding. Causes timeout errors (Lambda timeout = 15s).</p>
<br><br>
<button class="btn-secondary" onclick="inject('restore_dsql_permission')">Restore DSQL Permission</button>
<button class="btn-secondary" onclick="inject('restore_timeout')">Restore Timeout</button>
</div>
</div>
<div class="card">
<h3>Event Log</h3>
<div id="log"></div>
</div>
</div>
<script>
var autoInterval = null;
function setStatus(type, msg) {
  var el = document.getElementById('status');
  el.className = 'status-' + type;
  el.textContent = msg;
}
function log(msg) {
  var el = document.getElementById('log');
  var ts = new Date().toLocaleTimeString();
  el.textContent = '[' + ts + '] ' + msg + String.fromCharCode(10) + el.textContent;
}
async function fetchData() {
  setStatus('loading', 'Fetching data from DSQL...');
  try {
    var r = await fetch('/data?t=' + Date.now());
    if (!r.ok) {
      var err = await r.json().catch(function(){return {error:'HTTP '+r.status}});
      setStatus('error', 'ERROR: ' + (err.error || r.statusText));
      log('ERROR: ' + (err.error || r.statusText));
      return;
    }
    var d = await r.json();
    setStatus('ok', 'Success' + (d.sleepInjected > 0 ? ' (delayed ' + d.sleepInjected + 's)' : ''));
    log('Fetched ' + d.data.length + ' rows' + (d.sleepInjected > 0 ? ' [delayed '+d.sleepInjected+'s]' : ''));
    renderTable(d.data);
  } catch(e) {
    setStatus('error', 'TIMEOUT/NETWORK ERROR: ' + e.message);
    log('TIMEOUT: ' + e.message);
  }
}
function renderTable(rows) {
  if (!rows.length) { document.getElementById('data-table').innerHTML = '<p style="color:#8b949e;margin-top:12px">No data</p>'; return; }
  var html = '<table><tr><th>ID</th><th>Type</th><th>Message</th><th>Time</th></tr>';
  rows.forEach(function(r) {
    html += '<tr><td>'+r.id+'</td><td>'+r.event_type+'</td><td>'+r.message+'</td><td>'+new Date(r.created_at).toLocaleTimeString()+'</td></tr>';
  });
  html += '</table>';
  document.getElementById('data-table').innerHTML = html;
}
function autoFetch() { if(autoInterval) clearInterval(autoInterval); autoInterval = setInterval(fetchData, 3000); fetchData(); log('Auto-fetch started (3s interval)'); }
function stopAuto() { if(autoInterval){clearInterval(autoInterval);autoInterval=null;} log('Auto-fetch stopped'); }
async function inject(action) {
  log('Injecting: ' + action + '...');
  try {
    var r = await fetch('/inject', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({action: action}) });
    var d = await r.json();
    if (d.success) {
      log('Injection success: ' + d.message);
      setStatus(action.startsWith('restore') ? 'ok' : 'error', d.message);
    } else {
      log('Injection failed: ' + d.error);
    }
  } catch(e) { log('Injection error: ' + e.message); }
}
fetchData();
</script></body></html>`;
}
