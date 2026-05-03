import json
import os
import boto3

API_TOKEN = os.environ.get('API_TOKEN', '')
KVS_ARN = os.environ.get('KVS_ARN', '')
kvs = boto3.client('cloudfront-keyvaluestore')

def handler(event, context):
    headers = {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "POST,OPTIONS",
        "access-control-allow-headers": "content-type,authorization"
    }
    
    method = event.get('requestContext', {}).get('http', {}).get('method', '') or event.get('httpMethod', '')
    if method == 'OPTIONS':
        return {"statusCode": 200, "headers": headers, "body": ""}
    
    req_headers = event.get('headers', {})
    auth = req_headers.get('authorization', '') or req_headers.get('Authorization', '')
    if auth != f"Bearer {API_TOKEN}":
        return {"statusCode": 401, "headers": headers, "body": json.dumps({"error": "Unauthorized"})}
    
    try:
        body = json.loads(event.get('body', '{}'))
        origin_id = body.get('originId')
        enabled = body.get('enabled')
        
        if origin_id is None or enabled is None:
            return {"statusCode": 400, "headers": headers, "body": json.dumps({"error": "originId and enabled required"})}
        
        # Write directly to KVS — instant routing change
        desc = kvs.describe_key_value_store(KvsARN=KVS_ARN)
        etag = desc['ETag']
        kvs.put_key(
            KvsARN=KVS_ARN,
            Key=f"origin_{origin_id}_enabled",
            Value=str(enabled).lower(),
            IfMatch=etag
        )
        
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({
                "success": True,
                "originId": origin_id,
                "enabled": enabled,
                "message": f"Origin {origin_id} {'enabled' if enabled else 'disabled'}. Edge propagation ~5-10s."
            })
        }
    except Exception as e:
        return {"statusCode": 500, "headers": headers, "body": json.dumps({"error": str(e)})}
