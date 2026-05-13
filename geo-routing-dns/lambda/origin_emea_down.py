import json
import os

REGION = os.environ.get('AWS_REGION', 'eu-west-1')
LABEL = os.environ.get('ORIGIN_LABEL', 'EMEA (eu-west-1)')

def handler(event, context):
    path = event.get('rawPath', '/')
    
    if path == '/health':
        return {
            'statusCode': 503,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'status': 'unhealthy', 'region': REGION})
        }

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,OPTIONS'},
        'body': json.dumps({'message': f'Hello from {LABEL}', 'region': REGION, 'label': LABEL, 'healthy': False})
    }
