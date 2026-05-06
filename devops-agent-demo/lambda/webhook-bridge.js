const { createHmac } = require("crypto");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");

const sm = new SecretsManagerClient({});
const WEBHOOK_URL = process.env.WEBHOOK_URL;
const SECRET_ARN = process.env.WEBHOOK_SECRET_ARN;
const SERVICE_NAME = process.env.SERVICE_NAME || "devops-agent-demo";

let cachedSecret = null;

async function getSecret() {
  if (cachedSecret) return cachedSecret;
  const result = await sm.send(new GetSecretValueCommand({ SecretId: SECRET_ARN }));
  cachedSecret = result.SecretString;
  return cachedSecret;
}

exports.handler = async (event) => {
  const secret = await getSecret();

  for (const record of event.Records) {
    const snsMessage = record.Sns.Message;
    let alarmData;
    try {
      alarmData = JSON.parse(snsMessage);
    } catch (e) {
      console.log("Non-JSON SNS message, skipping:", snsMessage.substring(0, 200));
      continue;
    }

    const alarmName = alarmData.AlarmName || "unknown";
    const newState = alarmData.NewStateValue || "UNKNOWN";
    const reason = alarmData.NewStateReason || "";

    // Only fire on ALARM state
    if (newState !== "ALARM") {
      console.log(`Alarm ${alarmName} transitioned to ${newState}, skipping webhook`);
      continue;
    }

    // Determine priority and title based on alarm type
    let priority = "HIGH";
    let title = "";
    let description = "";

    if (alarmName.includes("error-rate")) {
      title = "Application Error Rate Spike - Lambda returning 500 errors";
      description = `The Lambda function is returning errors. CloudWatch Alarm '${alarmName}' triggered. Reason: ${reason}. Investigate CloudWatch Logs for /aws/lambda/${SERVICE_NAME}-app to identify root cause.`;
      priority = "CRITICAL";
    } else if (alarmName.includes("timeout")) {
      title = "Application Timeout - Lambda execution near timeout limit";
      description = `The Lambda function is timing out. CloudWatch Alarm '${alarmName}' triggered. Reason: ${reason}. Check if there's an artificial delay or downstream dependency issue.`;
      priority = "HIGH";
    } else {
      title = `CloudWatch Alarm: ${alarmName}`;
      description = reason;
    }

    const payload = {
      eventType: "incident",
      incidentId: `${alarmName}-${Date.now()}`,
      action: "created",
      priority: priority,
      title: title,
      description: description,
      timestamp: new Date().toISOString(),
      service: SERVICE_NAME,
      data: alarmData
    };

    // Sign with HMAC
    const timestamp = new Date().toISOString();
    const hmac = createHmac("sha256", secret);
    hmac.update(`${timestamp}:${JSON.stringify(payload)}`, "utf8");
    const signature = hmac.digest("base64");

    console.log(`Sending incident to DevOps Agent: ${title}`);

    const response = await fetch(WEBHOOK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-amzn-event-timestamp": timestamp,
        "x-amzn-event-signature": signature,
      },
      body: JSON.stringify(payload),
    });

    console.log(`Webhook response: ${response.status} ${response.statusText}`);
    if (!response.ok) {
      const body = await response.text();
      console.error(`Webhook error body: ${body}`);
    }
  }
};
