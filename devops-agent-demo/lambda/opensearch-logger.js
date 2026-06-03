const { defaultProvider } = require("@aws-sdk/credential-provider-node");
const { SignatureV4 } = require("@smithy/signature-v4");
const { Sha256 } = require("@aws-crypto/sha256-js");
const { HttpRequest } = require("@smithy/protocol-http");
const https = require("https");

const OPENSEARCH_ENDPOINT = process.env.OPENSEARCH_ENDPOINT;
const REGION = process.env.AWS_REGION || "us-east-1";

async function opensearchRequest(method, path, body) {
  const url = new URL(path, OPENSEARCH_ENDPOINT);
  const request = new HttpRequest({
    method,
    hostname: url.hostname,
    path: url.pathname,
    headers: {
      host: url.hostname,
      "content-type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const signer = new SignatureV4({
    service: "aoss",
    region: REGION,
    credentials: defaultProvider(),
    sha256: Sha256,
  });

  const signed = await signer.sign(request);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: signed.hostname,
        path: signed.path,
        method: signed.method,
        headers: signed.headers,
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode >= 400) {
            console.error(`[OPENSEARCH] ${res.statusCode}: ${data}`);
          }
          resolve(data);
        });
      }
    );
    req.on("error", reject);
    if (signed.body) req.write(signed.body);
    req.end();
  });
}

exports.handler = async (event) => {
  console.log("[OPENSEARCH-LOGGER] Received event:", JSON.stringify(event));

  if (!OPENSEARCH_ENDPOINT) {
    console.error("[OPENSEARCH-LOGGER] No OPENSEARCH_ENDPOINT configured");
    return { statusCode: 500, body: "No endpoint" };
  }

  const { index, document } = event;
  if (!index || !document) {
    console.error("[OPENSEARCH-LOGGER] Missing index or document in event");
    return { statusCode: 400, body: "Missing index or document" };
  }

  try {
    await opensearchRequest("POST", `/${index}/_doc`, document);
    console.log(`[OPENSEARCH-LOGGER] Written to ${index}`);
    return { statusCode: 200, body: "OK" };
  } catch (e) {
    console.error("[OPENSEARCH-LOGGER] Error:", e.message);
    return { statusCode: 500, body: e.message };
  }
};
