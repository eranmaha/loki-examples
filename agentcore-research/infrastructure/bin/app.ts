#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ResearchAgentWebStack } from '../lib/stack';

const app = new cdk.App();

new ResearchAgentWebStack(app, 'ResearchAgentWeb', {
  env: {
    account: '033216807884',
    region: 'us-east-1',
  },
  description: 'Research Agent Web App - CloudFront + Cognito + VPC Backend',
});
