# ─── OpenSearch MCP Server EC2 ────────────────────────────────────────────────

variable "enable_mcp_server" {
  description = "Deploy the OpenSearch MCP Server EC2 instance"
  type        = bool
  default     = true
}

# ─── S3 Bucket for MCP Server Package ────────────────────────────────────────

resource "aws_s3_bucket" "mcp_assets" {
  count  = var.enable_mcp_server ? 1 : 0
  bucket = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "mcp_assets" {
  count  = var.enable_mcp_server ? 1 : 0
  bucket = aws_s3_bucket.mcp_assets[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Pre-build MCP Server Package ────────────────────────────────────────────

resource "null_resource" "mcp_server_package" {
  count = var.enable_mcp_server ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/.build/mcp-pkg
      mkdir -p ${path.module}/.build/mcp-pkg
      pip install opensearch-mcp-server-py \
        -t ${path.module}/.build/mcp-pkg/ \
        --platform manylinux2014_aarch64 \
        --platform any \
        --only-binary=:all: \
        --python-version 3.12 \
        --implementation cp
    EOT
  }
}

data "archive_file" "mcp_server_package" {
  count       = var.enable_mcp_server ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/.build/mcp-pkg"
  output_path = "${path.module}/.build/mcp-server-pkg.zip"

  depends_on = [null_resource.mcp_server_package]
}

resource "aws_s3_object" "mcp_server_package" {
  count  = var.enable_mcp_server ? 1 : 0
  bucket = aws_s3_bucket.mcp_assets[0].id
  key    = "mcp-server-pkg.zip"
  source = data.archive_file.mcp_server_package[0].output_path
  etag   = data.archive_file.mcp_server_package[0].output_md5

  depends_on = [data.archive_file.mcp_server_package]
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
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.project_name}-assets-${data.aws_caller_identity.current.account_id}/*"
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

# ─── MCP Server Network Interface (for stable IP in TLS cert) ────────────────

resource "aws_network_interface" "mcp_server" {
  count           = var.enable_mcp_server ? 1 : 0
  subnet_id       = aws_subnet.private[0].id
  security_groups = [aws_security_group.mcp_server[0].id]

  tags = {
    Name    = "${var.project_name}-mcp-server"
    Project = var.project_name
  }
}

# ─── MCP Server TLS Certificate ──────────────────────────────────────────────

resource "tls_private_key" "mcp_server" {
  count     = var.enable_mcp_server ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "mcp_server" {
  count           = var.enable_mcp_server ? 1 : 0
  private_key_pem = tls_private_key.mcp_server[0].private_key_pem

  subject {
    common_name  = aws_network_interface.mcp_server[0].private_ip
    organization = "devops-agent-demo"
  }

  ip_addresses = [aws_network_interface.mcp_server[0].private_ip]

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ─── MCP Server API Key ──────────────────────────────────────────────────────

resource "random_password" "mcp_api_key" {
  count   = var.enable_mcp_server ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "mcp_api_key" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}/mcp-api-key"
  tags  = { Project = var.project_name }
}

resource "aws_secretsmanager_secret_version" "mcp_api_key" {
  count         = var.enable_mcp_server ? 1 : 0
  secret_id     = aws_secretsmanager_secret.mcp_api_key[0].id
  secret_string = random_password.mcp_api_key[0].result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ─── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "mcp_server" {
  count                = var.enable_mcp_server ? 1 : 0
  ami                  = data.aws_ssm_parameter.al2023_arm64.value
  instance_type        = "t4g.small"
  iam_instance_profile = aws_iam_instance_profile.mcp_server[0].name

  network_interface {
    network_interface_id = aws_network_interface.mcp_server[0].id
    device_index         = 0
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(join("\n", [
    "#!/bin/bash",
    "set -ex",
    "",
    "# Install Python 3.12 + nginx",
    "dnf install -y python3.12 nginx",
    "",
    "# Download pre-built MCP server package from S3",
    "aws s3 cp s3://${aws_s3_bucket.mcp_assets[0].id}/mcp-server-pkg.zip /tmp/mcp-server-pkg.zip",
    "mkdir -p /opt/mcp-server",
    "cd /opt/mcp-server && unzip /tmp/mcp-server-pkg.zip",
    "rm /tmp/mcp-server-pkg.zip",
    "",
    "# Write TLS cert",
    "mkdir -p /etc/nginx/ssl",
    "cat > /etc/nginx/ssl/mcp.crt << 'CERTEOF'",
    tls_self_signed_cert.mcp_server[0].cert_pem,
    "CERTEOF",
    "cat > /etc/nginx/ssl/mcp.key << 'KEYEOF'",
    tls_private_key.mcp_server[0].private_key_pem,
    "KEYEOF",
    "",
    "# Configure nginx as HTTPS API key auth proxy",
    "cat > /etc/nginx/conf.d/mcp-proxy.conf << 'NGINXEOF'",
    "server {",
    "    listen 8080 ssl;",
    "    ssl_certificate /etc/nginx/ssl/mcp.crt;",
    "    ssl_certificate_key /etc/nginx/ssl/mcp.key;",
    "    ssl_protocols TLSv1.2 TLSv1.3;",
    "    location / {",
    "        set $api_key_valid 0;",
    "        if ($http_x_api_key = '${random_password.mcp_api_key[0].result}') {",
    "            set $api_key_valid 1;",
    "        }",
    "        if ($api_key_valid = 0) {",
    "            return 401;",
    "        }",
    "        proxy_pass http://127.0.0.1:8081;",
    "        proxy_set_header Host $host;",
    "        proxy_http_version 1.1;",
    "        proxy_set_header Upgrade $http_upgrade;",
    "        proxy_set_header Connection 'upgrade';",
    "        proxy_read_timeout 300s;",
    "    }",
    "}",
    "NGINXEOF",
    "",
    "# Remove default nginx config",
    "rm -f /etc/nginx/conf.d/default.conf",
    "systemctl enable --now nginx",
    "",
    "# Create systemd service for MCP server",
    "cat > /etc/systemd/system/mcp-server.service << 'UNITEOF'",
    "[Unit]",
    "Description=OpenSearch MCP Server",
    "After=network.target",
    "[Service]",
    "Type=simple",
    "Environment=OPENSEARCH_URL=${aws_opensearchserverless_collection.logs.collection_endpoint}",
    "Environment=OPENSEARCH_AUTH=iam",
    "Environment=OPENSEARCH_IS_SERVERLESS=true",
    "Environment=OPENSEARCH_REGION=${var.region}",
    "Environment=AWS_REGION=${var.region}",
    "Environment=AWS_DEFAULT_REGION=${var.region}",
    "Environment=PYTHONPATH=/opt/mcp-server",
    "ExecStart=/usr/bin/python3.12 -m mcp_server_opensearch --transport stream --port 8081 --host 127.0.0.1",
    "Restart=always",
    "RestartSec=5",
    "[Install]",
    "WantedBy=multi-user.target",
    "UNITEOF",
    "",
    "systemctl daemon-reload",
    "systemctl enable --now mcp-server",
  ]))

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
        Permission   = ["aoss:*"]
      }
    ]
    Principal = [aws_iam_role.mcp_server_role[0].arn]
  }])
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "mcp_server_private_ip" {
  value       = var.enable_mcp_server ? aws_network_interface.mcp_server[0].private_ip : ""
  description = "OpenSearch MCP Server EC2 private IP"
}

output "mcp_server_host_address" {
  value       = var.enable_mcp_server ? "${aws_network_interface.mcp_server[0].private_ip}:8080" : ""
  description = "OpenSearch MCP Server host:port (for DevOps Agent private connection)"
}

output "mcp_server_url" {
  value       = var.enable_mcp_server ? "http://${aws_network_interface.mcp_server[0].private_ip}:8080/mcp/" : ""
  description = "OpenSearch MCP Server full URL (for DevOps Agent MCP registration)"
}

output "mcp_server_api_key_secret_arn" {
  value       = var.enable_mcp_server ? aws_secretsmanager_secret.mcp_api_key[0].arn : ""
  description = "Secrets Manager ARN for MCP Server API key"
}

output "mcp_server_api_key" {
  value       = var.enable_mcp_server ? random_password.mcp_api_key[0].result : ""
  description = "MCP Server API key (use in DevOps Agent MCP registration)"
  sensitive   = true
}

output "mcp_server_tls_certificate" {
  value       = var.enable_mcp_server ? tls_self_signed_cert.mcp_server[0].cert_pem : ""
  description = "MCP Server TLS certificate (PEM) - paste into DevOps Agent private connection"
}

output "mcp_server_instance_id" {
  value       = var.enable_mcp_server ? aws_instance.mcp_server[0].id : ""
  description = "MCP Server EC2 instance ID (for SSM Session Manager)"
}
