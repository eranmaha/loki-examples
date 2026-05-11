import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigatewayIntegrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as apigatewayAuthorizers from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as path from 'path';

export class ResearchAgentWebStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // === VPC: Import existing openclaw VPC and add private subnets ===
    const vpc = ec2.Vpc.fromLookup(this, 'ExistingVpc', {
      vpcId: 'vpc-0c7f243ebc19651b6',
    });

    // Create private subnets for the Lambda + VPC endpoint
    const privateSubnet1 = new ec2.PrivateSubnet(this, 'PrivateSubnet1', {
      vpcId: vpc.vpcId,
      cidrBlock: '10.0.10.0/24',
      availabilityZone: 'us-east-1a',
      mapPublicIpOnLaunch: false,
    });
    cdk.Tags.of(privateSubnet1).add('Name', 'research-agent-private-1a');

    const privateSubnet2 = new ec2.PrivateSubnet(this, 'PrivateSubnet2', {
      vpcId: vpc.vpcId,
      cidrBlock: '10.0.11.0/24',
      availabilityZone: 'us-east-1b',
      mapPublicIpOnLaunch: false,
    });
    cdk.Tags.of(privateSubnet2).add('Name', 'research-agent-private-1b');

    // NAT Gateway for outbound from private subnets (agent needs internet for browsing)
    const eip = new ec2.CfnEIP(this, 'NatEip', { domain: 'vpc' });
    const natGw = new ec2.CfnNatGateway(this, 'NatGateway', {
      subnetId: 'subnet-06a6490723bda459b', // public subnet us-east-1a
      allocationId: eip.attrAllocationId,
    });
    cdk.Tags.of(natGw).add('Name', 'research-agent-nat');

    // Route table for private subnets → NAT
    privateSubnet1.addRoute('DefaultRoute', {
      routerId: natGw.ref,
      routerType: ec2.RouterType.NAT_GATEWAY,
      destinationCidrBlock: '0.0.0.0/0',
    });
    privateSubnet2.addRoute('DefaultRoute', {
      routerId: natGw.ref,
      routerType: ec2.RouterType.NAT_GATEWAY,
      destinationCidrBlock: '0.0.0.0/0',
    });

    // Security group for Lambda
    const lambdaSg = new ec2.SecurityGroup(this, 'LambdaSg', {
      vpc,
      description: 'Lambda to invoke AgentCore via VPC endpoint',
      allowAllOutbound: true,
    });

    // === Cognito ===
    const userPool = new cognito.UserPool(this, 'ResearchAgentUserPool', {
      userPoolName: 'research-agent-users',
      selfSignUpEnabled: false,
      signInAliases: { email: true },
      autoVerify: { email: true },
      passwordPolicy: {
        minLength: 8,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const userPoolClient = new cognito.UserPoolClient(this, 'ResearchAgentClient', {
      userPool,
      userPoolClientName: 'research-agent-web',
      authFlows: {
        userSrp: true,
        userPassword: true,
      },
      generateSecret: false,
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
    });

    // === Backend Lambda (invokes AgentCore runtime) ===
    const backendFn = new lambda.Function(this, 'AgentInvokeFn', {
      functionName: 'research-agent-invoke',
      runtime: lambda.Runtime.PYTHON_3_12,
      architecture: lambda.Architecture.ARM_64,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '..', 'lambda')),
      timeout: cdk.Duration.seconds(300),
      memorySize: 512,
      vpc,
      vpcSubnets: { subnets: [privateSubnet1, privateSubnet2] },
      securityGroups: [lambdaSg],
      environment: {
        AGENTCORE_RUNTIME_ID: 'myresearchagent_myresearchagent-FYaWyF9elX',
        RESILIENCE_RUNTIME_ID: 'awsInfraRecSpec_awsinframrecspec-epROb3EMc3',
        AWS_REGION_NAME: 'us-east-1',
      },
    });

    // Grant Lambda permission to invoke AgentCore
    backendFn.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        'bedrock-agentcore:InvokeAgentRuntime',
        'bedrock-agentcore:InvokeRuntime',
        'bedrock-agentcore:InvokeRuntimeStreaming',
        'bedrock:InvokeModel',
        'bedrock:InvokeModelWithResponseStream',
        'bedrock:InvokeInlineAgent',
      ],
      resources: ['*'],
    }));

    // === HTTP API Gateway with Cognito JWT Authorizer ===
    const httpApi = new apigateway.HttpApi(this, 'ResearchAgentApi', {
      apiName: 'research-agent-api',
      corsPreflight: {
        allowHeaders: ['Content-Type', 'Authorization'],
        allowMethods: [apigateway.CorsHttpMethod.POST, apigateway.CorsHttpMethod.OPTIONS],
        allowOrigins: ['*'], // Will restrict to CloudFront domain later
      },
    });

    const jwtAuthorizer = new apigatewayAuthorizers.HttpJwtAuthorizer(
      'CognitoAuthorizer',
      `https://cognito-idp.us-east-1.amazonaws.com/${userPool.userPoolId}`,
      {
        jwtAudience: [userPoolClient.userPoolClientId],
      }
    );

    const lambdaIntegration = new apigatewayIntegrations.HttpLambdaIntegration(
      'AgentIntegration',
      backendFn
    );

    httpApi.addRoutes({
      path: '/api/invoke',
      methods: [apigateway.HttpMethod.POST],
      integration: lambdaIntegration,
      authorizer: jwtAuthorizer,
    });

    // === Frontend: S3 + CloudFront ===
    const siteBucket = new s3.Bucket(this, 'SiteBucket', {
      bucketName: `research-agent-web-${this.account}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    const oac = new cloudfront.S3OriginAccessControl(this, 'OAC', {
      signing: cloudfront.Signing.SIGV4_ALWAYS,
    });

    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(siteBucket, {
          originAccessControl: oac,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      additionalBehaviors: {
        '/api/*': {
          origin: new origins.HttpOrigin(
            `${httpApi.httpApiId}.execute-api.us-east-1.amazonaws.com`,
            { originPath: '' }
          ),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        },
      },
      defaultRootObject: 'index.html',
      errorResponses: [
        { httpStatus: 403, responseHttpStatus: 200, responsePagePath: '/index.html' },
        { httpStatus: 404, responseHttpStatus: 200, responsePagePath: '/index.html' },
      ],
    });

    // Deploy frontend
    new s3deploy.BucketDeployment(this, 'DeployFrontend', {
      sources: [s3deploy.Source.asset(path.join(__dirname, '..', '..', 'frontend'))],
      destinationBucket: siteBucket,
      distribution,
      distributionPaths: ['/*'],
    });

    // === Outputs ===
    new cdk.CfnOutput(this, 'CloudFrontUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'Research Agent Web App URL',
    });
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: userPool.userPoolId,
    });
    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: userPoolClient.userPoolClientId,
    });
    new cdk.CfnOutput(this, 'ApiUrl', {
      value: httpApi.url!,
    });
  }
}
