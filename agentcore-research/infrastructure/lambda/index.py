import json
import os
import uuid
import re
import boto3

RUNTIME_ID = os.environ['AGENTCORE_RUNTIME_ID']
REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')
RUNTIME_ARN = f'arn:aws:bedrock-agentcore:us-east-1:033216807884:runtime/{RUNTIME_ID}'


def handler(event, context):
    """Invoke AgentCore research agent via runtime API for full observability."""
    try:
        body = json.loads(event.get('body', '{}'))
        prompt = body.get('prompt', '')

        if not prompt:
            return {
                'statusCode': 400,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'prompt is required'}),
            }

        client = boto3.client('bedrock-agentcore', region_name=REGION)
        trace_id = str(uuid.uuid4())

        response = client.invoke_agent_runtime(
            agentRuntimeArn=RUNTIME_ARN,
            contentType='application/json',
            accept='application/json',
            traceId=trace_id,
            payload=json.dumps({'prompt': prompt}).encode('utf-8'),
        )

        # Parse SSE stream: "data: \"text\"\n\n"
        raw = response['response'].read().decode('utf-8')
        result_text = ''
        for line in raw.split('\n'):
            line = line.strip()
            if line.startswith('data: '):
                data_value = line[6:]  # Remove "data: " prefix
                try:
                    # Each chunk is a JSON string
                    chunk = json.loads(data_value)
                    if isinstance(chunk, str):
                        result_text += chunk
                except json.JSONDecodeError:
                    result_text += data_value

        # Unescape newlines
        result_text = result_text.replace('\\n', '\n')

        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'response': result_text or 'No response generated.',
                'traceId': trace_id,
            }),
        }

    except Exception as e:
        error_msg = str(e)
        print(f'AgentCore error: {error_msg}')

        # Fallback to inline agent if runtime unavailable
        if any(x in error_msg for x in ['ResourceNotFound', 'not found', 'timeout', 'Timeout']):
            return fallback_inline_agent(prompt, context)

        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': error_msg}),
        }


def fallback_inline_agent(prompt, context):
    """Fallback to inline agent if AgentCore runtime is unavailable."""
    try:
        client = boto3.client('bedrock-agent-runtime', region_name=REGION)
        response = client.invoke_inline_agent(
            inputText=prompt,
            endSession=False,
            enableTrace=True,
            sessionId=context.aws_request_id,
            foundationModel='us.anthropic.claude-sonnet-4-6',
            instruction=(
                'You are a helpful research assistant. '
                'Answer questions thoroughly using your knowledge.'
            ),
        )

        result_text = ''
        if 'completion' in response:
            for event_chunk in response['completion']:
                if 'chunk' in event_chunk:
                    chunk_data = event_chunk['chunk']
                    if 'bytes' in chunk_data:
                        result_text += chunk_data['bytes'].decode('utf-8')

        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({'response': result_text or 'No response generated.', 'mode': 'inline-fallback'}),
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': str(e)}),
        }


def cors_headers():
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
    }
