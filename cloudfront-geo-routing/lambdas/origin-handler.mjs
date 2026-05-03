import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const ssm = new SSMClient({ region: process.env.AWS_REGION || 'us-east-1' });
const originId = process.env.ORIGIN_ID || '0';

export const handler = async (event) => {
  const path = event.rawPath || event.path || '/';
  const headers = event.headers || {};

  // Health check endpoint
  if (path === '/health') {
    try {
      const param = await ssm.send(new GetParameterCommand({
        Name: `/geo-routing/origin-${originId}-healthy`
      }));
      const healthy = param.Parameter.Value !== 'false';
      return {
        statusCode: healthy ? 200 : 503,
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify({ originId, healthy, timestamp: new Date().toISOString() })
      };
    } catch (e) {
      // Parameter doesn't exist = healthy by default
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
        body: JSON.stringify({ originId, healthy: true, timestamp: new Date().toISOString() })
      };
    }
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
