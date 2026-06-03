"""
Lambda handler for OpenSearch MCP Server.

Wraps the opensearch-mcp-server-py Streamable HTTP transport behind
a Lambda Function URL using Mangum (ASGI→Lambda adapter).
"""

import os
import logging

from mangum import Mangum
from opensearch_mcp_server.server import create_opensearch_mcp_server

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Create the MCP server with OpenSearch configuration
server = create_opensearch_mcp_server()

# Get the ASGI app from the MCP server's streamable HTTP transport
app = server.streamable_http_app()

# Wrap with Mangum for Lambda compatibility
handler = Mangum(app, lifespan="off")
