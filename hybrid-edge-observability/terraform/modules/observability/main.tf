variable "project_name" { type = string }
variable "vpc_flow_log_group" { type = string }
variable "eks_cluster_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "ga_accelerator_arn" { type = string }
variable "region" { type = string }

# ─── CloudWatch Dashboard ─────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-network-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# 🌐 Hybrid Edge-to-Cloud Network Observability\n**Architecture:** Edge Simulator → Global Accelerator → ALB → EKS → DSQL"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title   = "Edge Latency (E2E) by Region"
          region  = var.region
          metrics = [
            ["PaymentEdge/Latency", "E2ELatency", "Region", "us-east-1", { stat = "p50", label = "us-east-1 P50" }],
            ["PaymentEdge/Latency", "E2ELatency", "Region", "us-east-1", { stat = "p95", label = "us-east-1 P95" }],
            ["PaymentEdge/Latency", "E2ELatency", "Region", "eu-west-1", { stat = "p50", label = "eu-west-1 P50" }],
            ["PaymentEdge/Latency", "E2ELatency", "Region", "ap-southeast-1", { stat = "p50", label = "ap-southeast-1 P50" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title   = "ALB Target Response Time"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title   = "Transaction Count by Region"
          region  = var.region
          metrics = [
            ["PaymentEdge/Latency", "TransactionCount", "Region", "us-east-1", { stat = "Sum" }],
            ["PaymentEdge/Latency", "TransactionCount", "Region", "eu-west-1", { stat = "Sum" }],
            ["PaymentEdge/Latency", "TransactionCount", "Region", "ap-southeast-1", { stat = "Sum" }]
          ]
          period = 300
          view   = "bar"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Global Accelerator - Processed Bytes"
          region  = "us-west-2"  # GA metrics are in us-west-2
          metrics = [
            ["AWS/GlobalAccelerator", "ProcessedBytesIn", "Accelerator", var.ga_accelerator_arn, { stat = "Sum" }],
            ["AWS/GlobalAccelerator", "ProcessedBytesOut", "Accelerator", var.ga_accelerator_arn, { stat = "Sum" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "ALB Request Count & Errors"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "VPC Flow Logs — Rejected Traffic"
          region  = var.region
          query   = "SOURCE '${var.vpc_flow_log_group}' | fields @timestamp, srcAddr, dstAddr, dstPort, action | filter action = 'REJECT' | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "EKS Pod Network (Container Insights)"
          region  = var.region
          metrics = [
            ["ContainerInsights", "pod_network_rx_bytes", "ClusterName", var.eks_cluster_name, { stat = "Sum" }],
            ["ContainerInsights", "pod_network_tx_bytes", "ClusterName", var.eks_cluster_name, { stat = "Sum" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "Global Accelerator — New Flows & Healthy Endpoints"
          region  = "us-west-2"
          metrics = [
            ["AWS/GlobalAccelerator", "NewFlowCount", "Accelerator", var.ga_accelerator_arn, { stat = "Sum" }],
            ["AWS/GlobalAccelerator", "HealthyEndpointCount", "Accelerator", var.ga_accelerator_arn, { stat = "Average" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ─── Alarms ───────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.project_name}-high-edge-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "E2ELatency"
  namespace           = "PaymentEdge/Latency"
  period              = 300
  extended_statistic   = "p95"
  threshold           = 500
  alarm_description   = "Edge-to-cloud P95 latency exceeds 500ms"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Region = "us-east-1"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "ALB backend returning 5xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.project_name}-network-observability"
}
