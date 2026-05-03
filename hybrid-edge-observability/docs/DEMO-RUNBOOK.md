# Demo Runbook — Customer Presentation

## Pre-Demo Checklist

- [ ] All infrastructure deployed (`terraform apply` succeeded)
- [ ] Edge simulators running (check CloudWatch `/aws/lambda/hybrid-edge-obs-edge-sim`)
- [ ] EKS pods healthy (`kubectl get pods -n payment`)
- [ ] Dashboard populated with data (wait 10-15 min after deploy)

## Demo Script (30 minutes)

### Act 1: The Architecture (5 min)

**Talking points:**
> "This simulates a real hybrid payment architecture — edge POS terminals connect through Global Accelerator for optimal routing, hit an ALB, get processed in EKS, and persist to a multi-region Aurora DSQL database."

Show the architecture diagram from the README.

### Act 2: Trigger a Live Transaction (5 min)

```bash
# Invoke the edge simulator manually
aws lambda invoke --function-name hybrid-edge-obs-edge-sim \
  --payload '{}' --cli-binary-format raw-in-base64-out /tmp/result.json
cat /tmp/result.json | python3 -m json.tool
```

**Key callout:** Point out the `X-Transaction-ID` — this is what we'll trace through every layer.

### Act 3: Follow the Packet (15 min)

#### Stop 1: Global Accelerator Flow Logs
> "Here we see the edge device connected from eu-west-1. GA routed it over the AWS backbone to us-east-1 in 12ms."

Open S3 → `ga-flow-logs/` or Athena query.

#### Stop 2: ALB Access Logs
> "Same transaction arrives at the ALB. Target processing time = 45ms — that's how long the pod took. The ALB added <1ms overhead."

Show the ALB access log entry with matching transaction ID.

#### Stop 3: X-Ray Trace
> "Here's the full distributed trace. You can see the waterfall: ALB routing (2ms) → API processing (5ms) → DSQL write (38ms). The DB write is the dominant latency because it's a multi-region consensus write."

Open X-Ray → filter by `annotation.transactionId = "<id>"`.

#### Stop 4: VPC Flow Logs
> "At the network layer, we can see the TCP connection from ALB ENI to the pod, and from the pod to the DSQL endpoint. Packets, bytes, TCP flags — full L4 visibility."

Run the Log Insights query.

#### Stop 5: Unified Dashboard
> "And here's the single pane of glass — edge latency by region, ALB performance, GA throughput, rejected traffic. All correlated, all real-time."

Show the CloudWatch dashboard.

### Act 4: Simulate a Failure (5 min)

```bash
# Scale down the payment pods
kubectl scale deployment payment-api -n payment --replicas=0
```

> "Watch the dashboard — GA health check will fail in ~30 seconds, the edge simulator will see 5xx responses, and CloudWatch alarms fire."

Then restore:
```bash
kubectl scale deployment payment-api -n payment --replicas=2
```

> "Recovery is automatic — GA detects the healthy endpoint and routes traffic back."

## Key Messages for Customer

1. **No single tool covers everything** — you need L3/L4 (flow logs) + L7 (access logs + X-Ray) + application (Container Insights) working together
2. **Correlation is king** — the `X-Transaction-ID` header lets you trace a single request across all layers
3. **AWS native tools are sufficient** — no third-party agents needed (VPC Flow Logs + ALB Access Logs + X-Ray + Container Insights + GA Flow Logs)
4. **Global Accelerator adds observability** — flow logs show exactly how traffic is routed across the backbone, something you can't see with DNS-based routing
5. **DSQL multi-region adds latency visibility** — you can measure and explain the consensus write overhead (~88ms) vs local reads (~3ms)
