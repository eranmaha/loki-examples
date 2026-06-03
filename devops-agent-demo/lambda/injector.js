const { IAMClient, PutRolePolicyCommand, DeleteRolePolicyCommand } = require("@aws-sdk/client-iam");
const { SSMClient, PutParameterCommand, GetParameterCommand } = require("@aws-sdk/client-ssm");

const iam = new IAMClient({});
const ssm = new SSMClient({});

const APP_ROLE_NAME = process.env.APP_ROLE_NAME;
const SSM_SLEEP_PARAM = process.env.SSM_SLEEP_PARAM;
const SSM_DATA_CORRUPTION_PARAM = process.env.SSM_DATA_CORRUPTION_PARAM;
const SSM_BIZ_ERROR_PARAM = process.env.SSM_BIZ_ERROR_PARAM;
const DSQL_POLICY_NAME = process.env.DSQL_POLICY_NAME;

exports.handler = async (event) => {
  const body = JSON.parse(event.body || "{}");
  const action = body.action;

  try {
    switch (action) {
      case "remove_dsql_permission": {
        await iam.send(new DeleteRolePolicyCommand({
          RoleName: APP_ROLE_NAME,
          PolicyName: DSQL_POLICY_NAME,
        }));
        return respond(200, { success: true, message: "🔴 DSQL permission REMOVED" });
      }

      case "restore_dsql_permission": {
        const policy = JSON.stringify({
          Version: "2012-10-17",
          Statement: [{ Effect: "Allow", Action: ["dsql:DbConnectAdmin"], Resource: "*" }],
        });
        await iam.send(new PutRolePolicyCommand({
          RoleName: APP_ROLE_NAME,
          PolicyName: DSQL_POLICY_NAME,
          PolicyDocument: policy,
        }));
        return respond(200, { success: true, message: "🟢 DSQL permission RESTORED" });
      }

      case "inject_timeout": {
        await ssm.send(new PutParameterCommand({
          Name: SSM_SLEEP_PARAM, Value: "20", Type: "String", Overwrite: true,
        }));
        return respond(200, { success: true, message: "🟡 Timeout injected (20s sleep)" });
      }

      case "restore_timeout": {
        await ssm.send(new PutParameterCommand({
          Name: SSM_SLEEP_PARAM, Value: "0", Type: "String", Overwrite: true,
        }));
        return respond(200, { success: true, message: "🟢 Timeout restored" });
      }

      case "inject_data_corruption": {
        await ssm.send(new PutParameterCommand({
          Name: SSM_DATA_CORRUPTION_PARAM, Value: "true", Type: "String", Overwrite: true,
        }));
        return respond(200, { success: true, message: "🔴 Data corruption ENABLED - malformed data will be written to OpenSearch" });
      }

      case "inject_business_logic_error": {
        await ssm.send(new PutParameterCommand({
          Name: SSM_BIZ_ERROR_PARAM, Value: "true", Type: "String", Overwrite: true,
        }));
        return respond(200, { success: true, message: "🔴 Business logic errors ENABLED - invalid state transitions will occur" });
      }

      case "restore_app_errors": {
        await Promise.all([
          ssm.send(new PutParameterCommand({
            Name: SSM_DATA_CORRUPTION_PARAM, Value: "false", Type: "String", Overwrite: true,
          })),
          ssm.send(new PutParameterCommand({
            Name: SSM_BIZ_ERROR_PARAM, Value: "false", Type: "String", Overwrite: true,
          })),
        ]);
        return respond(200, { success: true, message: "🟢 App error injections cleared" });
      }

      default:
        return respond(400, { success: false, error: `Unknown action: ${action}` });
    }
  } catch (err) {
    console.error("[INJECTOR ERROR]", err);
    return respond(500, { success: false, error: err.message });
  }
};

function respond(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    body: JSON.stringify(body),
  };
}
