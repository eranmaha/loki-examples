import json
import os

REGION = os.environ.get('AWS_REGION', 'unknown')
LABEL = os.environ.get('ORIGIN_LABEL', f'Origin ({REGION})')
HEALTHY = True  # Toggle for demo


def handler(event, context):
    path = event.get('rawPath', '/')
    
    if path == '/health':
        if HEALTHY:
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'status': 'healthy', 'region': REGION})
            }
        else:
            return {
                'statusCode': 503,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'status': 'unhealthy', 'region': REGION})
            }

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,OPTIONS',
        },
        'body': json.dumps({
            'message': f'Hello from {LABEL}',
            'region': REGION,
            'label': LABEL,
            'healthy': HEALTHY,
        })
    }
