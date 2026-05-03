"""
Edge Payment Simulator — Simulates a POS terminal making payment transactions.
Deployed as Lambda in multiple regions to test Global Accelerator routing.
"""

import json
import os
import time
import urllib.request
import urllib.error
import uuid
import boto3

GA_ENDPOINT = os.environ.get("GA_ENDPOINT", "")
REGION_LABEL = os.environ.get("REGION_LABEL", "unknown")

cloudwatch = boto3.client("cloudwatch")


def lambda_handler(event, context):
    """Simulate 5 payment transactions and publish latency metrics."""
    results = []

    for i in range(5):
        transaction_id = str(uuid.uuid4())
        payload = json.dumps({
            "action": "authorize",
            "amount": round(10.0 + i * 5.50, 2),
            "currency": "USD",
            "card_last4": "4242",
            "merchant_id": f"MERCH-{REGION_LABEL.upper()}-001",
            "transaction_id": transaction_id,
        }).encode()

        headers = {
            "Content-Type": "application/json",
            "X-Transaction-ID": transaction_id,
            "X-Edge-Region": REGION_LABEL,
            "X-Edge-Timestamp": str(time.time()),
        }

        url = f"http://{GA_ENDPOINT}/api/payment"
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

        start = time.perf_counter()
        status_code = 0
        error_msg = None

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                status_code = resp.status
                _ = resp.read()
        except urllib.error.HTTPError as e:
            status_code = e.code
            error_msg = str(e)
        except Exception as e:
            error_msg = str(e)

        latency_ms = (time.perf_counter() - start) * 1000

        results.append({
            "transaction_id": transaction_id,
            "latency_ms": round(latency_ms, 2),
            "status": status_code,
            "error": error_msg,
        })

        # Publish per-request metric
        cloudwatch.put_metric_data(
            Namespace="PaymentEdge/Latency",
            MetricData=[
                {
                    "MetricName": "E2ELatency",
                    "Value": latency_ms,
                    "Unit": "Milliseconds",
                    "Dimensions": [
                        {"Name": "Region", "Value": REGION_LABEL},
                        {"Name": "StatusCode", "Value": str(status_code)},
                    ],
                },
                {
                    "MetricName": "TransactionCount",
                    "Value": 1,
                    "Unit": "Count",
                    "Dimensions": [
                        {"Name": "Region", "Value": REGION_LABEL},
                    ],
                },
            ],
        )

    # Summary
    latencies = [r["latency_ms"] for r in results]
    summary = {
        "region": REGION_LABEL,
        "transactions": len(results),
        "avg_latency_ms": round(sum(latencies) / len(latencies), 2),
        "max_latency_ms": round(max(latencies), 2),
        "min_latency_ms": round(min(latencies), 2),
        "errors": sum(1 for r in results if r["error"]),
        "results": results,
    }

    print(json.dumps(summary))
    return summary
