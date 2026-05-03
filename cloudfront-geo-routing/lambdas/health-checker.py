import json
import os
import boto3

KVS_ARN = os.environ['KVS_ARN']
kvs = boto3.client('cloudfront-keyvaluestore')
lambda_client = boto3.client('lambda')

ORIGIN_FUNCTIONS = {
    "0": "SimpleDynamicOriginRoutin-Origin0NodejsFunction529-VgxgmqPIBfMo",
    "1": "SimpleDynamicOriginRoutin-Origin1NodejsFunction975-Pq0yox0O7JkZ",
    "2": "SimpleDynamicOriginRoutin-Origin2NodejsFunction052-HvPwKCnKHQsk",
}

def handler(event, context):
    results = {}
    
    for origin_id, func_name in ORIGIN_FUNCTIONS.items():
        healthy = True
        try:
            resp = lambda_client.invoke(
                FunctionName=func_name,
                InvocationType='RequestResponse',
                Payload=json.dumps({"rawPath": "/health", "headers": {}}).encode()
            )
            payload = json.loads(resp['Payload'].read())
            status_code = payload.get('statusCode', 500)
            healthy = (status_code == 200)
        except Exception as e:
            print(f"Origin {origin_id} invoke failed: {e}")
            healthy = False
        
        results[origin_id] = healthy
    
    # Update KVS for any changes
    for origin_id, healthy in results.items():
        try:
            desc = kvs.describe_key_value_store(KvsARN=KVS_ARN)
            etag = desc['ETag']
            kvs.put_key(
                KvsARN=KVS_ARN,
                Key=f"origin_{origin_id}_enabled",
                Value=str(healthy).lower(),
                IfMatch=etag
            )
        except Exception as e:
            print(f"KVS update failed for origin {origin_id}: {e}")
    
    print(json.dumps({"results": results}))
    return results
