import json
import os
import uuid
import boto3

RUNTIME_ID = os.environ['AGENTCORE_RUNTIME_ID']
REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')


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

        # Generate trace ID for observability
        trace_id = str(uuid.uuid4())

        # Invoke the AgentCore runtime for full end-to-end tracing
        response = client.invoke_agent_runtime(
            agentRuntimeArn=f'arn:aws:bedrock-agentcore:us-east-1:033216807884:runtime/{RUNTIME_ID}',
            contentType='application/json',
            accept='application/json',
            traceId=trace_id,
            payload=json.dumps({
                'prompt': prompt,
            }).encode('utf-8'),
        )

        # Read streaming response
        result_text = ''
        if 'body' in response:
            response_body = response['body'].read().decode('utf-8')
            # AgentCore streams events, collect text
            for line in response_body.split('\n'):
                line = line.strip()
                if not line:
                    continue
                try:
                    event_data = json.loads(line)
                    if isinstance(event_data, dict):
                        # Handle different response formats
                        if 'data' in event_data:
                            result_text += event_data['data']
                        elif 'text' in event_data:
                            result_text += event_data['text']
                        elif 'content' in event_data:
                            result_text += event_data['content']
                except json.JSONDecodeError:
                    result_text += line

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
        print(f'Error: {error_msg}')

        # Fallback to inline agent if runtime is cold/unavailable
        if 'ResourceNotFound' in error_msg or 'not found' in error_msg.lower():
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
                'Answer questions thoroughly using your knowledge. '
                'If asked to browse websites or look up current information, '
                'do your best to provide accurate and helpful responses.'
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
