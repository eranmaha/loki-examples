# ─── OpenSearch Serverless ───────────────────────────────────────────────────

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.project_name}-enc"
  type = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${var.project_name}-logs"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_vpc_endpoint" "aoss" {
  name               = "${var.project_name}-aoss"
  vpc_id             = aws_vpc.main.id
  subnet_ids         = local.aoss_supported_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.project_name}-net"
  type = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.project_name}-logs"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${var.project_name}-logs"]
      }
    ]
    AllowFromPublic = false
    SourceVPCEs     = [aws_opensearchserverless_vpc_endpoint.aoss.id]
  }])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${var.project_name}-data"
  type = "data"
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
    Principal = [
      aws_iam_role.lambda_role.arn,
      aws_iam_role.logger_role.arn,
      "arn:aws:iam::${var.account_id}:root"
    ]
  }])
}

resource "aws_opensearchserverless_collection" "logs" {
  name = "${var.project_name}-logs"
  type = "TIMESERIES"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data,
  ]

  tags = { Project = var.project_name }
}

# ─── Outputs ────────────────────────────────────────────────────────────────

output "opensearch_endpoint" {
  value = aws_opensearchserverless_collection.logs.collection_endpoint
}
