const originId = process.env.ORIGIN_ID || '0';

export const handler = async (event) => {
  const path = event.rawPath || event.path || '/';
  const headers = event.headers || {};

  // Health check endpoint
  if (path === '/health') {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ originId, healthy: true, timestamp: new Date().toISOString() })
    };
  }

  // Normal request
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'X-Origin-ID': originId,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Expose-Headers': 'X-Origin-ID',
    },
    body: JSON.stringify({
      originId,
      region: headers['x-routed-region'] || 'unknown',
      country: headers['x-viewer-country-resolved'] || 'unknown',
      routedTo: headers['x-routed-origin'] || 'unknown',
      timestamp: new Date().toISOString(),
    }),
  };
};
