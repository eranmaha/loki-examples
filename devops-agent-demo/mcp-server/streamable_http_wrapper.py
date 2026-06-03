#!/usr/bin/env python3
"""
Streamable HTTP wrapper for opensearch-mcp-server-py.

The opensearch-mcp-server-py only supports stdio and SSE transports.
AWS DevOps Agent requires Streamable HTTP (POST /mcp).
This wrapper starts the server with StreamableHTTP transport from the mcp SDK.
"""
import asyncio
import logging
import os
import sys

from starlette.applications import Starlette
from starlette.routing import Mount
from mcp.server.streamable_http import StreamableHTTPServerTransport

# Import the opensearch MCP server's create_server function
from mcp_server_opensearch.server_factory import create_mcp_server

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def create_app():
    """Create Starlette app with StreamableHTTP transport."""
    # Create the MCP server instance (same as opensearch-mcp-server-py does internally)
    server = create_mcp_server(mode="single", cli_tool_overrides={})

    # Create StreamableHTTP transport
    transport = StreamableHTTPServerTransport("/mcp")

    # Connect server to transport
    await server.connect(transport)

    # Create Starlette app
    app = Starlette(
        routes=[
            Mount("/mcp", app=transport.handle_request),
        ]
    )
    return app


def main():
    import uvicorn

    host = os.environ.get("MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("MCP_PORT", "8081"))

    logger.info(f"Starting OpenSearch MCP Server (Streamable HTTP) on {host}:{port}/mcp")

    # Run with uvicorn
    uvicorn.run(
        "streamable_http_wrapper:create_app",
        host=host,
        port=port,
        factory=True,
        log_level="info",
    )


if __name__ == "__main__":
    main()
