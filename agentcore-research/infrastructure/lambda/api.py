import json
import os
import uuid
import time
import boto3

WORKER_FN = os.environ['WORKER_FUNCTION_NAME']
TASK_TABLE = os.environ['TASK_TABLE']
REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(TASK_TABLE)
lambda_client = boto3.client('lambda', region_name=REGION)


def handler(event, context):
    """API handler: POST /api/invoke (kickoff) and GET /api/status/{taskId} (poll)."""
    method = event.get('requestContext', {}).get('http', {}).get('method', 'POST')
    path = event.get('rawPath', '')

    if method == 'GET' and '/api/status/' in path:
        return handle_status(event)
    elif method == 'POST':
        return handle_invoke(event)
    else:
        return response(400, {'error': 'Invalid request'})


def handle_invoke(event):
    """Kick off an agent task and return taskId immediately."""
    try:
        body = json.loads(event.get('body', '{}'))
        prompt = body.get('prompt', '')
        agent_id = body.get('agent', 'research')
        prd_content = body.get('prd_content', '')

        if not prompt and not prd_content:
            return response(400, {'error': 'prompt or prd_content is required'})

        task_id = str(uuid.uuid4())
        now = int(time.time())
        ttl = now + 3600  # 1 hour TTL

        # Store task as PENDING
        table.put_item(Item={
            'taskId': task_id,
            'status': 'PENDING',
            'agent': agent_id,
            'prompt': prompt,
            'prd_content': prd_content[:50000],  # Limit stored PRD size
            'createdAt': now,
            'ttl': ttl,
        })

        # Invoke worker Lambda asynchronously
        lambda_client.invoke(
            FunctionName=WORKER_FN,
            InvocationType='Event',  # Async!
            Payload=json.dumps({
                'taskId': task_id,
                'prompt': prompt,
                'agent': agent_id,
                'prd_content': prd_content,
            }).encode('utf-8'),
        )

        return response(202, {
            'taskId': task_id,
            'status': 'PENDING',
            'message': 'Task submitted. Poll /api/status/{taskId} for results.',
        })

    except Exception as e:
        print(f'Error: {e}')
        return response(500, {'error': str(e)})


def handle_status(event):
    """Check task status and return result if complete."""
    try:
        # Extract taskId from path
        path = event.get('rawPath', '')
        task_id = path.split('/api/status/')[-1].strip('/')

        if not task_id:
            return response(400, {'error': 'taskId is required'})

        result = table.get_item(Key={'taskId': task_id})
        item = result.get('Item')

        if not item:
            return response(404, {'error': 'Task not found'})

        status = item.get('status', 'UNKNOWN')
        resp = {
            'taskId': task_id,
            'status': status,
            'agent': item.get('agent', ''),
        }

        if status == 'COMPLETE':
            resp['response'] = item.get('response', '')
            resp['traceId'] = item.get('traceId', '')
        elif status == 'FAILED':
            resp['error'] = item.get('error', 'Unknown error')

        return response(200, resp)

    except Exception as e:
        print(f'Error: {e}')
        return response(500, {'error': str(e)})


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        },
        'body': json.dumps(body),
    }
