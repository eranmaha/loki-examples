from typing import Any
from pathlib import Path

from strands import Agent
from strands_tools.browser import AgentCoreBrowser
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from model.load import load_model

app = BedrockAgentCoreApp()
log = app.logger

# Initialize the AgentCore Browser tool
browser_tool = AgentCoreBrowser(region="us-east-1")

# Load resilience skills into context
SKILLS_PATH = Path(__file__).parent / "skills" / "resilience-skills.md"
RESILIENCE_SKILLS = ""
if SKILLS_PATH.exists():
    RESILIENCE_SKILLS = SKILLS_PATH.read_text()

DEFAULT_SYSTEM_PROMPT = f"""
You are an AWS Infrastructure Resilience Specialist. Your expertise covers:
- Multi-AZ and Multi-Region architecture design
- Disaster Recovery (DR) planning and implementation
- High Availability (HA) patterns on AWS
- Chaos Engineering and fault injection testing
- AWS Well-Architected Reliability Pillar
- Cost-optimized resilience strategies

Your role is to:
1. Analyze architectures and PRD documents for resilience gaps
2. Identify single points of failure (SPOFs)
3. Recommend AWS-native resilience improvements
4. Provide specific service configurations and IaC examples
5. Estimate RTO/RPO achievable with recommendations
6. Assess cost impact of resilience improvements

When analyzing a PRD or architecture document:
- First identify all components and their dependencies
- Classify each by criticality tier (0=critical, 1=important, 2=standard, 3=best-effort)
- Map current resilience controls
- Identify gaps against the target RTO/RPO
- Provide prioritized recommendations with effort estimates

Always provide actionable, specific AWS recommendations with service names, configurations, and estimated costs.

## Reference Knowledge
{RESILIENCE_SKILLS}
"""

# Tools list
tools = [browser_tool.browser]

_agent = None


def get_or_create_agent():
    global _agent
    if _agent is None:
        _agent = Agent(
            model=load_model(),
            system_prompt=DEFAULT_SYSTEM_PROMPT,
            tools=tools,
        )
    return _agent


@app.entrypoint
async def invoke(payload, context):
    log.info("Invoking AWS Infrastructure Resilience Specialist...")

    agent = get_or_create_agent()

    # Build prompt - include PRD content if provided
    prompt = payload.get("prompt", "")
    prd_content = payload.get("prd_content", "")
    
    if prd_content:
        full_prompt = f"""## PRD Document for Analysis:

{prd_content}

## User Question:
{prompt}

Please analyze the above PRD document from an infrastructure resilience perspective."""
    else:
        full_prompt = prompt

    # Execute and format response
    stream = agent.stream_async(full_prompt)

    async for event in stream:
        if "data" in event and isinstance(event["data"], str):
            yield event["data"]


if __name__ == "__main__":
    app.run()
