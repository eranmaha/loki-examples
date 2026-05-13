import json
import boto3

HEALTH_CHECKS = {
    'americas': '591d4d0d-044d-45d9-acd1-9ea6f73b0bad',
    'emea': '240f864c-4c0e-4386-b245-f47dbb4ff5e4',
    'apac': 'ab055823-7ae9-4c5b-950f-1264914cbc4e',
}

route53 = boto3.client('route53', region_name='us-east-1')


def handler(event, context):
    path = event.get('rawPath', '/')

    if path == '/status':
        results = {}
        for name, hc_id in HEALTH_CHECKS.items():
            try:
                resp = route53.get_health_check_status(HealthCheckId=hc_id)
                observations = resp.get('HealthCheckObservations', [])
                # Healthy if majority of checkers report success
                healthy_count = sum(1 for o in observations if 'Success' in o.get('StatusReport', {}).get('Status', ''))
                total = len(observations)
                results[name] = {
                    'healthy': healthy_count > total / 2,
                    'healthyCheckers': healthy_count,
                    'totalCheckers': total,
                    'sample': observations[0]['StatusReport']['Status'] if observations else 'unknown',
                }
            except Exception as e:
                results[name] = {'healthy': None, 'error': str(e)}

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
            },
            'body': json.dumps(results),
        }

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({'service': 'geo-routing-dns-status', 'endpoints': ['/status']}),
    }
