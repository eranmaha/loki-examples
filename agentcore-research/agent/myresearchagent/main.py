from typing import Any

from strands import Agent
from strands_tools.browser import AgentCoreBrowser
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from model.load import load_model

app = BedrockAgentCoreApp()
log = app.logger

# Initialize the AgentCore Browser tool
browser_tool = AgentCoreBrowser(region="us-east-1")

DEFAULT_SYSTEM_PROMPT = """
You are a research agent. Your job is to browse the web, extract information,
and provide well-structured research summaries. Use the browser tool to navigate
websites, read content, and gather data to answer questions thoroughly.

When researching:
1. Navigate to relevant pages
2. Extract key information
3. Synthesize findings into clear, actionable summaries
4. Cite sources when possible
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
    log.info("Invoking Research Agent...")

    agent = get_or_create_agent()

    # Execute and format response
    stream = agent.stream_async(payload.get("prompt"))

    async for event in stream:
        if "data" in event and isinstance(event["data"], str):
            yield event["data"]


if __name__ == "__main__":
    app.run()
