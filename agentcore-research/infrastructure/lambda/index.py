import json
import os
import uuid
import boto3
import base64

REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')
ACCOUNT_ID = '033216807884'

# Agent registry
AGENTS = {
    'research': {
        'name': 'Research Agent',
        'runtime_id': os.environ.get('AGENTCORE_RUNTIME_ID', ''),
        'description': 'General-purpose AI research assistant',
    },
    'resilience': {
        'name': 'AWS Infra Resilience Specialist',
        'runtime_id': os.environ.get('RESILIENCE_RUNTIME_ID', ''),
        'description': 'Infrastructure resilience analysis and recommendations',
    },
}


def handler(event, context):
    """Invoke AgentCore agents with agent selection and file upload support."""
    try:
        # Handle OPTIONS for CORS
        if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
            return {'statusCode': 200, 'headers': cors_headers(), 'body': ''}

        body = json.loads(event.get('body', '{}'))
        prompt = body.get('prompt', '')
        agent_id = body.get('agent', 'research')
        prd_content = body.get('prd_content', '')  # Base64 or plain text

        if not prompt and not prd_content:
            return {
                'statusCode': 400,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'prompt or prd_content is required'}),
            }

        # Get agent config
        agent_config = AGENTS.get(agent_id)
        if not agent_config:
            return {
                'statusCode': 400,
                'headers': cors_headers(),
                'body': json.dumps({'error': f'Unknown agent: {agent_id}', 'available': list(AGENTS.keys())}),
            }

        runtime_id = agent_config['runtime_id']
        if not runtime_id:
            # Fallback to inline agent
            return invoke_inline(prompt, prd_content, agent_id, context)

        # Build payload
        payload = {'prompt': prompt}
        if prd_content:
            payload['prd_content'] = prd_content

        client = boto3.client('bedrock-agentcore', region_name=REGION)
        trace_id = str(uuid.uuid4())

        runtime_arn = f'arn:aws:bedrock-agentcore:us-east-1:{ACCOUNT_ID}:runtime/{runtime_id}'

        response = client.invoke_agent_runtime(
            agentRuntimeArn=runtime_arn,
            contentType='application/json',
            accept='application/json',
            traceId=trace_id,
            payload=json.dumps(payload).encode('utf-8'),
        )

        # Parse SSE stream
        raw = response['response'].read().decode('utf-8')
        result_text = ''
        for line in raw.split('\n'):
            line = line.strip()
            if line.startswith('data: '):
                data_value = line[6:]
                try:
                    chunk = json.loads(data_value)
                    if isinstance(chunk, str):
                        result_text += chunk
                except json.JSONDecodeError:
                    result_text += data_value

        result_text = result_text.replace('\\n', '\n')

        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'response': result_text or 'No response generated.',
                'traceId': trace_id,
                'agent': agent_id,
            }),
        }

    except Exception as e:
        error_msg = str(e)
        print(f'Error: {error_msg}')
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': error_msg}),
        }


def invoke_inline(prompt, prd_content, agent_id, context):
    """Fallback to inline agent."""
    client = boto3.client('bedrock-agent-runtime', region_name=REGION)

    if agent_id == 'resilience':
        instruction = (
            'You are an AWS Infrastructure Resilience Specialist. '
            'Analyze architectures and PRD documents for resilience gaps. '
            'Identify single points of failure, recommend AWS-native improvements, '
            'and provide RTO/RPO estimates with cost impact analysis.'
        )
    else:
        instruction = (
            'You are a helpful research assistant. '
            'Answer questions thoroughly using your knowledge.'
        )

    full_prompt = prompt
    if prd_content:
        full_prompt = f"## PRD Document:\n{prd_content}\n\n## Question:\n{prompt or 'Analyze this PRD for infrastructure resilience.'}"

    response = client.invoke_inline_agent(
        inputText=full_prompt,
        endSession=False,
        enableTrace=True,
        sessionId=context.aws_request_id,
        foundationModel='us.anthropic.claude-sonnet-4-6',
        instruction=instruction,
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
        'body': json.dumps({'response': result_text or 'No response generated.', 'agent': agent_id, 'mode': 'inline'}),
    }


def cors_headers():
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
    }
