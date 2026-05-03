/**
 * HTML Visualization Generator
 * Creates a presentable Chart.js-based comparison report
 */

'use strict';

const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');

function generateHtml(results, outputPath) {
  const workloads = Object.keys(results.singleRegion || results.multiRegion || {});
  const counts = [];
  
  // Collect all counts
  for (const wl of workloads) {
    const wlData = results.singleRegion[wl] || results.multiRegion[wl] || {};
    for (const c of Object.keys(wlData)) {
      if (!counts.includes(Number(c))) counts.push(Number(c));
    }
  }
  counts.sort((a, b) => a - b);
  
  // Build chart datasets for each workload
  const chartConfigs = workloads.map(wl => {
    const metrics = ['p50', 'p95', 'p99', 'avg'];
    return metrics.map(metric => {
      const singleData = counts.map(c => {
        const d = (results.singleRegion[wl] || {})[c];
        return d && !d.error ? Math.round(d[metric] * 100) / 100 : null;
      });
      const multiData = counts.map(c => {
        const d = (results.multiRegion[wl] || {})[c];
        return d && !d.error ? Math.round(d[metric] * 100) / 100 : null;
      });
      return { wl, metric, singleData, multiData };
    });
  }).flat();
  
  const chartsJson = JSON.stringify(chartConfigs);
  const countsJson = JSON.stringify(counts);
  const timestampStr = results.timestamp ? new Date(results.timestamp).toLocaleString() : 'N/A';
  
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Aurora DSQL Benchmark Report</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
      background: #0f1117;
      color: #e2e8f0;
      min-height: 100vh;
    }
    header {
      background: linear-gradient(135deg, #1a1f2e 0%, #16213e 100%);
      border-bottom: 1px solid #2d3748;
      padding: 2rem 3rem;
      display: flex;
      align-items: center;
      gap: 1.5rem;
    }
    .aws-logo {
      width: 48px; height: 48px;
      background: #FF9900;
      border-radius: 10px;
      display: flex; align-items: center; justify-content: center;
      font-size: 1.5rem; font-weight: 900; color: #0f1117;
    }
    .header-text h1 { font-size: 1.6rem; font-weight: 700; color: #fff; }
    .header-text p { color: #718096; font-size: 0.9rem; margin-top: 0.25rem; }
    .badge {
      margin-left: auto;
      background: #2d3748;
      border: 1px solid #4a5568;
      border-radius: 8px;
      padding: 0.5rem 1rem;
      font-size: 0.8rem;
      color: #a0aec0;
    }
    .badge strong { color: #63b3ed; }
    
    main { padding: 2rem 3rem; max-width: 1400px; margin: 0 auto; }
    
    .summary-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem;
      margin-bottom: 2.5rem;
    }
    .summary-card {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 12px;
      padding: 1.25rem 1.5rem;
    }
    .summary-card .label { font-size: 0.75rem; color: #718096; text-transform: uppercase; letter-spacing: 0.05em; }
    .summary-card .value { font-size: 1.5rem; font-weight: 700; color: #fff; margin-top: 0.25rem; }
    .summary-card .sub { font-size: 0.8rem; color: #4a5568; margin-top: 0.25rem; }
    .summary-card.single .value { color: #63b3ed; }
    .summary-card.multi .value { color: #68d391; }
    
    .section-title {
      font-size: 1.1rem;
      font-weight: 600;
      color: #e2e8f0;
      margin-bottom: 1.25rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    .section-title::before {
      content: '';
      display: block;
      width: 4px; height: 1.2em;
      background: #FF9900;
      border-radius: 2px;
    }
    
    .workload-section {
      margin-bottom: 3rem;
    }
    
    .charts-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
      gap: 1.5rem;
    }
    
    .chart-card {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 12px;
      padding: 1.5rem;
    }
    .chart-card h3 {
      font-size: 0.9rem;
      font-weight: 600;
      color: #a0aec0;
      margin-bottom: 1rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .chart-container { position: relative; height: 220px; }
    
    .legend {
      display: flex;
      gap: 1.5rem;
      margin-top: 0.75rem;
      font-size: 0.8rem;
      color: #718096;
    }
    .legend-item { display: flex; align-items: center; gap: 0.4rem; }
    .legend-dot { width: 10px; height: 10px; border-radius: 50%; }
    .legend-dot.single { background: #63b3ed; }
    .legend-dot.multi { background: #68d391; }
    
    .tabs {
      display: flex;
      gap: 0.5rem;
      margin-bottom: 1.5rem;
      border-bottom: 1px solid #2d3748;
      padding-bottom: 0;
    }
    .tab {
      padding: 0.6rem 1.2rem;
      border-radius: 8px 8px 0 0;
      font-size: 0.85rem;
      font-weight: 500;
      cursor: pointer;
      border: 1px solid transparent;
      border-bottom: none;
      color: #718096;
      background: transparent;
      transition: all 0.15s;
    }
    .tab:hover { color: #e2e8f0; background: #1a1f2e; }
    .tab.active {
      color: #fff;
      background: #1a1f2e;
      border-color: #2d3748;
      border-bottom-color: #1a1f2e;
      margin-bottom: -1px;
    }
    .tab-content { display: none; }
    .tab-content.active { display: block; }
    
    footer {
      text-align: center;
      padding: 2rem;
      color: #4a5568;
      font-size: 0.8rem;
      border-top: 1px solid #2d3748;
      margin-top: 2rem;
    }
  </style>
</head>
<body>
  <header>
    <div class="aws-logo">⚡</div>
    <div class="header-text">
      <h1>Aurora DSQL Benchmark Report</h1>
      <p>TPC-C workload — Single-Region vs Multi-Region latency comparison</p>
    </div>
    <div class="badge">Generated: <strong>${timestampStr}</strong></div>
  </header>
  
  <main>
    <div id="summary-section">
      <div class="summary-grid" id="summary-cards"></div>
    </div>
    
    <div class="tabs" id="workload-tabs"></div>
    <div id="workload-panels"></div>
  </main>
  
  <footer>Aurora DSQL Benchmark — All latencies in milliseconds</footer>
  
  <script>
    const CHARTS = ${chartsJson};
    const COUNTS = ${countsJson};
    const RESULTS = ${JSON.stringify(results)};
    
    const WORKLOADS = [...new Set(CHARTS.map(c => c.wl))];
    const METRICS = ['avg', 'p50', 'p95', 'p99'];
    const METRIC_LABELS = { avg: 'Average', p50: 'P50 Median', p95: 'P95', p99: 'P99' };
    
    Chart.defaults.color = '#718096';
    Chart.defaults.borderColor = '#2d3748';
    
    // Summary cards
    const summaryEl = document.getElementById('summary-cards');
    function getAvgLatency(clusterResults, wl, metric) {
      if (!clusterResults[wl]) return null;
      const vals = Object.values(clusterResults[wl]).filter(d => d && !d.error && d[metric] != null);
      if (!vals.length) return null;
      return vals.reduce((a, b) => a + b[metric], 0) / vals.length;
    }
    
    const summaryData = [];
    for (const wl of WORKLOADS) {
      const sAvg = getAvgLatency(RESULTS.singleRegion || {}, wl, 'avg');
      const mAvg = getAvgLatency(RESULTS.multiRegion || {}, wl, 'avg');
      summaryData.push({ wl, sAvg, mAvg });
    }
    
    summaryData.forEach(({ wl, sAvg, mAvg }) => {
      const diff = (sAvg && mAvg) ? ((mAvg - sAvg) / sAvg * 100).toFixed(1) : null;
      summaryEl.innerHTML += \`
        <div class="summary-card single">
          <div class="label">\${wl.toUpperCase()} · Single-Region</div>
          <div class="value">\${sAvg ? sAvg.toFixed(1) + ' ms' : 'N/A'}</div>
          <div class="sub">avg latency (all counts)</div>
        </div>
        <div class="summary-card multi">
          <div class="label">\${wl.toUpperCase()} · Multi-Region</div>
          <div class="value">\${mAvg ? mAvg.toFixed(1) + ' ms' : 'N/A'}</div>
          <div class="sub">\${diff ? (diff > 0 ? '+' + diff + '% vs single' : diff + '% vs single') : 'avg latency'}</div>
        </div>
      \`;
    });
    
    // Tabs
    const tabsEl = document.getElementById('workload-tabs');
    const panelsEl = document.getElementById('workload-panels');
    
    WORKLOADS.forEach((wl, idx) => {
      tabsEl.innerHTML += \`<button class="tab \${idx===0?'active':''}" onclick="switchTab('\${wl}')" id="tab-\${wl}">\${wl.toUpperCase()}</button>\`;
      
      const panel = document.createElement('div');
      panel.className = 'tab-content' + (idx === 0 ? ' active' : '');
      panel.id = 'panel-' + wl;
      
      panel.innerHTML = \`
        <div class="workload-section">
          <div class="section-title">\${wl.toUpperCase()} Latency by Record Count</div>
          <div class="charts-grid" id="charts-\${wl}"></div>
        </div>
      \`;
      panelsEl.appendChild(panel);
      
      // Create one chart per metric
      METRICS.forEach(metric => {
        const chartData = CHARTS.find(c => c.wl === wl && c.metric === metric);
        if (!chartData) return;
        
        const card = document.createElement('div');
        card.className = 'chart-card';
        const canvasId = \`chart-\${wl}-\${metric}\`;
        card.innerHTML = \`
          <h3>\${METRIC_LABELS[metric]} Latency (ms)</h3>
          <div class="chart-container"><canvas id="\${canvasId}"></canvas></div>
          <div class="legend">
            <div class="legend-item"><div class="legend-dot single"></div> Single-Region (us-east-1)</div>
            <div class="legend-item"><div class="legend-dot multi"></div> Multi-Region (us-east-1 + us-west-2)</div>
          </div>
        \`;
        document.getElementById('charts-' + wl).appendChild(card);
        
        new Chart(document.getElementById(canvasId), {
          type: 'bar',
          data: {
            labels: COUNTS.map(c => c + ' ops'),
            datasets: [
              {
                label: 'Single-Region',
                data: chartData.singleData,
                backgroundColor: 'rgba(99, 179, 237, 0.7)',
                borderColor: '#63b3ed',
                borderWidth: 1,
                borderRadius: 4,
              },
              {
                label: 'Multi-Region',
                data: chartData.multiData,
                backgroundColor: 'rgba(104, 211, 145, 0.7)',
                borderColor: '#68d391',
                borderWidth: 1,
                borderRadius: 4,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { display: false },
              tooltip: {
                callbacks: {
                  label: ctx => \` \${ctx.dataset.label}: \${ctx.parsed.y?.toFixed(2)} ms\`,
                },
              },
            },
            scales: {
              x: { grid: { color: '#2d3748' } },
              y: {
                grid: { color: '#2d3748' },
                ticks: { callback: v => v + ' ms' },
                beginAtZero: true,
              },
            },
          },
        });
      });
    });
    
    function switchTab(wl) {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(p => p.classList.remove('active'));
      document.getElementById('tab-' + wl).classList.add('active');
      document.getElementById('panel-' + wl).classList.add('active');
    }
  </script>
</body>
</html>`;
  
  fs.writeFileSync(outputPath, html, 'utf8');
  return outputPath;
}

// CLI mode
if (require.main === module) {
  const args = process.argv.slice(2);
  const resultsDir = RESULTS_DIR;
  
  if (!args[0]) {
    // Find latest JSON result
    const files = fs.readdirSync(resultsDir)
      .filter(f => f.endsWith('.json'))
      .sort()
      .reverse();
    
    if (!files.length) {
      console.error('No result JSON files found in results/. Run the benchmark first.');
      process.exit(1);
    }
    
    const latest = path.join(resultsDir, files[0]);
    console.log(`Using latest result: ${files[0]}`);
    const results = JSON.parse(fs.readFileSync(latest, 'utf8'));
    const outPath = latest.replace('.json', '.html');
    generateHtml(results, outPath);
    console.log(`✓ HTML report saved to ${outPath}`);
  } else {
    const inputPath = path.resolve(args[0]);
    const results = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    const outPath = args[1] || inputPath.replace('.json', '.html');
    generateHtml(results, outPath);
    console.log(`✓ HTML report saved to ${outPath}`);
  }
}

module.exports = { generateHtml };
