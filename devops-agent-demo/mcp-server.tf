# ─── OpenSearch MCP Server EC2 ────────────────────────────────────────────────

variable "enable_mcp_server" {
  description = "Deploy the OpenSearch MCP Server EC2 instance"
  type        = bool
  default     = true
}

# ─── AMI Lookup ──────────────────────────────────────────────────────────────

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ─── IAM Role ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "mcp_server_role" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}-mcp-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "mcp_server_policy" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "mcp-server"
  role  = aws_iam_role.mcp_server_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = "arn:aws:aoss:${var.region}:${var.account_id}:collection/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mcp_server_ssm" {
  count      = var.enable_mcp_server ? 1 : 0
  role       = aws_iam_role.mcp_server_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mcp_server" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}-mcp-server"
  role  = aws_iam_role.mcp_server_role[0].name
}

# ─── Security Group ─────────────────────────────────────────────────────────

resource "aws_security_group" "mcp_server" {
  count       = var.enable_mcp_server ? 1 : 0
  name        = "${var.project_name}-mcp-server"
  description = "MCP Server EC2 - inbound 8080 from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-mcp-server"
    Project = var.project_name
  }
}

# ─── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "mcp_server" {
  count                  = var.enable_mcp_server ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = "t4g.small"
  subnet_id              = aws_subnet.private[0].id
  iam_instance_profile   = aws_iam_instance_profile.mcp_server[0].name
  vpc_security_group_ids = [aws_security_group.mcp_server[0].id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex

    # Install Python 3.12 + pip
    dnf install -y python3.12 python3.12-pip

    # Install opensearch-mcp-server-py
    python3.12 -m pip install opensearch-mcp-server-py

    # Create systemd service
    cat > /etc/systemd/system/mcp-server.service <<'UNIT'
    [Unit]
    Description=OpenSearch MCP Server (Streamable HTTP)
    After=network.target

    [Service]
    Type=simple
    Environment=OPENSEARCH_URL=${aws_opensearchserverless_collection.logs.collection_endpoint}
    Environment=OPENSEARCH_AUTH=iam
    Environment=OPENSEARCH_IS_SERVERLESS=true
    Environment=OPENSEARCH_REGION=us-east-1
    ExecStart=/usr/local/bin/opensearch-mcp-server-py --transport streamable-http --port 8080 --host 0.0.0.0
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now mcp-server
  EOF
  )

  tags = {
    Name    = "${var.project_name}-mcp-server"
    Project = var.project_name
  }
}

# ─── AOSS Data Access Policy (MCP server role) ──────────────────────────────

resource "aws_opensearchserverless_access_policy" "mcp_data" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}-mcp-data"
  type  = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.project_name}-logs"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${var.project_name}-logs/*"]
        Permission = [
          "aoss:CreateIndex", "aoss:UpdateIndex", "aoss:DescribeIndex",
          "aoss:ReadDocument", "aoss:WriteDocument"
        ]
      }
    ]
    Principal = [aws_iam_role.mcp_server_role[0].arn]
  }])
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "mcp_server_private_ip" {
  value       = var.enable_mcp_server ? aws_instance.mcp_server[0].private_ip : ""
  description = "OpenSearch MCP Server EC2 private IP"
}

output "mcp_server_host_address" {
  value       = var.enable_mcp_server ? "${aws_instance.mcp_server[0].private_ip}:8080" : ""
  description = "OpenSearch MCP Server endpoint (Streamable HTTP)"
}
