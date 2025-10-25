#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SmtpServerStack } from '../lib/smtp-server-stack';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const keyPairName = app.node.tryGetContext('keyPair') || process.env.KEY_PAIR_NAME;
const domainName = app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME;
const hostedZoneId = app.node.tryGetContext('hostedZoneId') || process.env.HOSTED_ZONE_ID;

// Environment-specific configurations
const getStackConfig = (env: string) => {
  const configs = {
    dev: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
      volumeSize: 30,
      enableMonitoring: false,
      enableBackups: false,
      sshAllowedCidrs: ['0.0.0.0/0'], // ⚠️ Change this in production!
    },
    staging: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      volumeSize: 50,
      enableMonitoring: true,
      enableBackups: true,
      sshAllowedCidrs: ['0.0.0.0/0'], // ⚠️ Change this to your office IP!
    },
    production: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE),
      volumeSize: 100,
      enableMonitoring: true,
      enableBackups: true,
      sshAllowedCidrs: ['YOUR_OFFICE_IP/32'], // ⚠️ CHANGE THIS!
    },
  };

  return configs[env as keyof typeof configs] || configs.dev;
};

const config = getStackConfig(environment);

// Development Stack
if (environment === 'dev') {
  new SmtpServerStack(app, 'SmtpServerDevStack', {
    environment: 'dev',
    stackName: 'smtp-server-dev',
    description: 'SMTP Server Development Environment',
    ...config,
    keyPairName,
    env: {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
    },
    tags: {
      Environment: 'dev',
      Project: 'SMTP Server',
      ManagedBy: 'CDK',
      CostCenter: 'Development',
    },
  });
}

// Staging Stack
if (environment === 'staging') {
  new SmtpServerStack(app, 'SmtpServerStagingStack', {
    environment: 'staging',
    stackName: 'smtp-server-staging',
    description: 'SMTP Server Staging Environment',
    ...config,
    keyPairName,
    domainName: domainName || 'smtp-staging.example.com',
    hostedZoneId,
    env: {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
    },
    tags: {
      Environment: 'staging',
      Project: 'SMTP Server',
      ManagedBy: 'CDK',
      CostCenter: 'Staging',
    },
  });
}

// Production Stack
if (environment === 'production') {
  new SmtpServerStack(app, 'SmtpServerProdStack', {
    environment: 'production',
    stackName: 'smtp-server-production',
    description: 'SMTP Server Production Environment',
    ...config,
    keyPairName,
    domainName: domainName || 'mail.example.com',
    hostedZoneId,
    env: {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
    },
    tags: {
      Environment: 'production',
      Project: 'SMTP Server',
      ManagedBy: 'CDK',
      CostCenter: 'Production',
      Backup: 'Required',
    },
  });
}

app.synth();
