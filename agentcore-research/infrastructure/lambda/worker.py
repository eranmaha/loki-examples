import json
import os
import uuid
import time
import boto3
from botocore.config import Config

TASK_TABLE = os.environ['TASK_TABLE']
REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')
ACCOUNT_ID = '033216807884'

AGENTS = {
    'research': {
        'runtime_id': os.environ.get('AGENTCORE_RUNTIME_ID', ''),
        'instruction': (
            'You are a helpful research assistant. '
            'Answer questions thoroughly using your knowledge. '
            'If asked to browse websites or look up current information, '
            'do your best to provide accurate and helpful responses.'
        ),
    },
    'resilience': {
        'runtime_id': os.environ.get('RESILIENCE_RUNTIME_ID', ''),
        'instruction': (
            'You are an AWS Infrastructure Resilience Specialist. '
            'Analyze architectures and PRD documents for resilience gaps. '
            'Identify single points of failure, recommend AWS-native improvements, '
            'provide RTO/RPO estimates with cost impact analysis. '
            'Use tables, clear sections, and actionable recommendations.'
        ),
    },
}

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(TASK_TABLE)


def handler(event, context):
    """Worker: invoked async, runs agent, writes result to DynamoDB."""
    task_id = event.get('taskId')
    prompt = event.get('prompt', '')
    agent_id = event.get('agent', 'research')
    prd_content = event.get('prd_content', '')

    try:
        # Update status to RUNNING
        table.update_item(
            Key={'taskId': task_id},
            UpdateExpression='SET #s = :s',
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues={':s': 'RUNNING'},
        )

        # Get agent config
        agent_config = AGENTS.get(agent_id, AGENTS['research'])
        runtime_id = agent_config['runtime_id']

        # Try AgentCore runtime first
        result_text = ''
        trace_id = str(uuid.uuid4())

        try:
            if runtime_id:
                result_text = invoke_agentcore(runtime_id, prompt, prd_content, trace_id)
        except Exception as e:
            print(f'AgentCore failed, falling back to inline: {e}')

        # Fallback to inline agent
        if not result_text:
            result_text = invoke_inline(prompt, prd_content, agent_config['instruction'], context)

        # Write result
        table.update_item(
            Key={'taskId': task_id},
            UpdateExpression='SET #s = :s, #r = :r, #t = :t, completedAt = :c',
            ExpressionAttributeNames={'#s': 'status', '#r': 'response', '#t': 'traceId'},
            ExpressionAttributeValues={
                ':s': 'COMPLETE',
                ':r': result_text or 'No response generated.',
                ':t': trace_id,
                ':c': int(time.time()),
            },
        )

    except Exception as e:
        print(f'Worker error: {e}')
        table.update_item(
            Key={'taskId': task_id},
            UpdateExpression='SET #s = :s, #e = :e',
            ExpressionAttributeNames={'#s': 'status', '#e': 'error'},
            ExpressionAttributeValues={':s': 'FAILED', ':e': str(e)},
        )


def invoke_agentcore(runtime_id, prompt, prd_content, trace_id):
    """Invoke AgentCore runtime with full timeout."""
    client = boto3.client('bedrock-agentcore', region_name=REGION,
        config=Config(read_timeout=240, connect_timeout=10))

    payload = {'prompt': prompt}
    if prd_content:
        payload['prd_content'] = prd_content

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
            try:
                chunk = json.loads(line[6:])
                if isinstance(chunk, str):
                    result_text += chunk
            except json.JSONDecodeError:
                result_text += line[6:]

    return result_text.replace('\\n', '\n')


def invoke_inline(prompt, prd_content, instruction, context):
    """Invoke Bedrock inline agent."""
    client = boto3.client('bedrock-agent-runtime', region_name=REGION)

    full_prompt = prompt
    if prd_content:
        full_prompt = f"## PRD Document:\n{prd_content}\n\n## Question:\n{prompt or 'Analyze this PRD for infrastructure resilience.'}"

    response = client.invoke_inline_agent(
        inputText=full_prompt,
        endSession=False,
        enableTrace=True,
        sessionId=str(uuid.uuid4()),
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

    return result_text
