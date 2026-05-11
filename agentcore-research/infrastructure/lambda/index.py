import json
import os
import boto3

RUNTIME_ID = os.environ['AGENTCORE_RUNTIME_ID']
REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')


def handler(event, context):
    """Invoke AgentCore research agent and return response."""
    try:
        body = json.loads(event.get('body', '{}'))
        prompt = body.get('prompt', '')

        if not prompt:
            return {
                'statusCode': 400,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'prompt is required'}),
            }

        client = boto3.client('bedrock-agent-runtime', region_name=REGION)

        # Use invoke_inline_agent with browser tool for research
        response = client.invoke_inline_agent(
            inputText=prompt,
            endSession=False,
            enableTrace=False,
            sessionId=context.aws_request_id,
            foundationModel='us.anthropic.claude-sonnet-4-6-v1:0',
            instruction=(
                'You are a helpful research assistant. '
                'Answer questions thoroughly using your knowledge. '
                'If asked to browse websites or look up current information, do your best to provide accurate and helpful responses.'
            ),
        )

        # Collect streamed response
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
            'body': json.dumps({'response': result_text or 'No response generated.'}),
        }

    except Exception as e:
        print(f'Error: {e}')
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
