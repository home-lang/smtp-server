import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';
import { config, getEnvironmentConfig, getSshAllowedCidrs } from '../config';

export interface SmtpServerStackProps extends cdk.StackProps {
  /**
   * Environment name (dev, staging, production)
   */
  environment: 'dev' | 'staging' | 'production';

  /**
   * Instance type for the SMTP server
   * @default t3.medium
   */
  instanceType?: ec2.InstanceType;

  /**
   * Domain name for the SMTP server (optional)
   * If provided, will create Route53 records
   */
  domainName?: string;

  /**
   * Hosted zone ID for Route53 (required if domainName is provided)
   */
  hostedZoneId?: string;

  /**
   * Whether to enable automatic backups
   * @default true
   */
  enableBackups?: boolean;

  /**
   * VPC CIDR block
   * @default 10.0.0.0/16
   */
  vpcCidr?: string;

  /**
   * Enable monitoring and CloudWatch alarms
   * @default true
   */
  enableMonitoring?: boolean;

  /**
   * Key pair name for SSH access
   */
  keyPairName?: string;

  /**
   * Allowed SSH CIDR blocks
   * @default ['0.0.0.0/0'] - Allow from anywhere (change in production!)
   */
  sshAllowedCidrs?: string[];

  /**
   * EBS volume size in GB
   * @default 50
   */
  volumeSize?: number;
}

export class SmtpServerStack extends cdk.Stack {
  public readonly instance: ec2.Instance;
  public readonly vpc: ec2.Vpc;
  public readonly securityGroup: ec2.SecurityGroup;
  public readonly bucket: s3.Bucket;
  public readonly secret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: SmtpServerStackProps) {
    super(scope, id, props);

    // Get environment-specific configuration
    const envConfig = getEnvironmentConfig(props.environment);

    const {
      environment,
      instanceType = envConfig.instanceType,
      domainName,
      hostedZoneId,
      enableBackups = envConfig.enableBackups,
      vpcCidr = config.vpcCidr,
      enableMonitoring = envConfig.enableMonitoring,
      keyPairName,
      sshAllowedCidrs = getSshAllowedCidrs(props.environment),
      volumeSize = envConfig.volumeSize,
    } = props;

    // =========================================================================
    // VPC and Networking
    // =========================================================================

    this.vpc = new ec2.Vpc(this, 'SmtpVpc', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: envConfig.maxAzs,
      natGateways: 0, // No NAT gateway for cost savings
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    cdk.Tags.of(this.vpc).add('Name', `smtp-server-vpc-${environment}`);
    cdk.Tags.of(this.vpc).add('Environment', environment);

    // =========================================================================
    // Security Groups
    // =========================================================================

    this.securityGroup = new ec2.SecurityGroup(this, 'SmtpSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for SMTP server',
      allowAllOutbound: true,
    });

    // SSH access
    if (sshAllowedCidrs.length > 0) {
      sshAllowedCidrs.forEach((cidr, index) => {
        this.securityGroup.addIngressRule(
          ec2.Peer.ipv4(cidr),
          ec2.Port.tcp(config.ports.ssh),
          `SSH access from ${cidr}`
        );
      });
    }

    // SMTP ports
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.smtp),
      'SMTP'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.smtps),
      'SMTPS (implicit TLS)'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.submission),
      'SMTP Submission (STARTTLS)'
    );

    // IMAP ports
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.imap),
      'IMAP'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.imaps),
      'IMAPS'
    );

    // POP3 ports
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.pop3),
      'POP3'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.pop3s),
      'POP3S'
    );

    // HTTP/HTTPS for ActiveSync, CalDAV, API
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.http),
      'HTTP'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.https),
      'HTTPS'
    );

    // WebSocket
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.websocket),
      'WebSocket'
    );
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(config.ports.websocketSecure),
      'WebSocket SSL'
    );

    cdk.Tags.of(this.securityGroup).add('Name', `smtp-server-sg-${environment}`);

    // =========================================================================
    // S3 Bucket for Email Storage
    // =========================================================================

    this.bucket = new s3.Bucket(this, 'SmtpEmailBucket', {
      bucketName: `smtp-server-emails-${environment}-${this.account}`,
      versioned: config.security.enableS3Versioning,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: environment === 'production'
        ? cdk.RemovalPolicy.RETAIN
        : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: environment !== 'production',
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(envConfig.s3Lifecycle.transitionToIA),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(envConfig.s3Lifecycle.transitionToGlacier),
            },
          ],
        },
      ],
    });

    cdk.Tags.of(this.bucket).add('Name', `smtp-server-emails-${environment}`);

    // =========================================================================
    // Secrets Manager for Credentials
    // =========================================================================

    this.secret = new secretsmanager.Secret(this, 'SmtpCredentials', {
      secretName: `smtp-server-credentials-${environment}`,
      description: 'SMTP server database credentials and secrets',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          environment,
          created: new Date().toISOString(),
        }),
        generateStringKey: 'admin_password',
        passwordLength: 32,
        excludePunctuation: true,
      },
    });

    // =========================================================================
    // IAM Role for EC2 Instance
    // =========================================================================

    const role = new iam.Role(this, 'SmtpInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for SMTP server EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Grant S3 bucket access
    this.bucket.grantReadWrite(role);

    // Grant Secrets Manager access
    this.secret.grantRead(role);

    // Allow CloudWatch Logs
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'],
    }));

    // =========================================================================
    // CloudWatch Log Group
    // =========================================================================

    const logGroup = new logs.LogGroup(this, 'SmtpLogGroup', {
      logGroupName: `/aws/ec2/smtp-server-${environment}`,
      retention: envConfig.logRetention,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // =========================================================================
    // User Data Script
    // =========================================================================

    const userDataScript = this.createUserDataScript(environment, {
      bucketName: this.bucket.bucketName,
      secretArn: this.secret.secretArn,
      logGroupName: logGroup.logGroupName,
      domainName: domainName || `smtp-${environment}.local`,
    });

    const userData = ec2.UserData.forLinux();
    userData.addCommands(userDataScript);

    // =========================================================================
    // EC2 Instance
    // =========================================================================

    // Use Amazon Linux 2023 (latest)
    const machineImage = ec2.MachineImage.latestAmazonLinux2023({
      cachedInContext: false,
    });

    this.instance = new ec2.Instance(this, 'SmtpInstance', {
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      instanceType,
      machineImage,
      securityGroup: this.securityGroup,
      role,
      userData,
      keyName: keyPairName,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(volumeSize, {
            encrypted: config.security.enableEbsEncryption,
            deleteOnTermination: environment !== 'production',
            volumeType: ec2.EbsDeviceVolumeType.GP3,
          }),
        },
      ],
      requireImdsv2: config.security.requireImdsv2,
      detailedMonitoring: enableMonitoring,
    });

    cdk.Tags.of(this.instance).add('Name', `smtp-server-${environment}`);
    cdk.Tags.of(this.instance).add('Environment', environment);
    cdk.Tags.of(this.instance).add('Application', 'SMTP Server');

    // =========================================================================
    // CloudWatch Alarms (if monitoring enabled)
    // =========================================================================

    if (enableMonitoring) {
      this.createCloudWatchAlarms(environment);
    }

    // =========================================================================
    // Route53 DNS Records (if domain provided)
    // =========================================================================

    if (domainName && hostedZoneId) {
      this.createDnsRecords(domainName, hostedZoneId);
    }

    // =========================================================================
    // Outputs
    // =========================================================================

    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.instance.instanceId,
      description: 'EC2 Instance ID',
      exportName: `SmtpInstanceId-${environment}`,
    });

    new cdk.CfnOutput(this, 'PublicIp', {
      value: this.instance.instancePublicIp,
      description: 'Public IP address',
      exportName: `SmtpPublicIp-${environment}`,
    });

    new cdk.CfnOutput(this, 'PublicDnsName', {
      value: this.instance.instancePublicDnsName,
      description: 'Public DNS name',
      exportName: `SmtpPublicDns-${environment}`,
    });

    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'S3 bucket for email storage',
      exportName: `SmtpBucketName-${environment}`,
    });

    new cdk.CfnOutput(this, 'SecretArn', {
      value: this.secret.secretArn,
      description: 'Secrets Manager ARN for credentials',
      exportName: `SmtpSecretArn-${environment}`,
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'Security Group ID',
      exportName: `SmtpSecurityGroupId-${environment}`,
    });

    new cdk.CfnOutput(this, 'SshCommand', {
      value: keyPairName
        ? `ssh -i ~/.ssh/${keyPairName}.pem ec2-user@${this.instance.instancePublicIp}`
        : 'No key pair specified - use AWS Systems Manager Session Manager',
      description: 'SSH command to connect to the instance',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group name',
      exportName: `SmtpLogGroupName-${environment}`,
    });
  }

  /**
   * Create user data script for instance initialization
   */
  private createUserDataScript(
    environment: string,
    scriptConfig: {
      bucketName: string;
      secretArn: string;
      logGroupName: string;
      domainName: string;
    }
  ): string {
    const installUtils = config.userData.installUtils.join(' \\\n  ');

    return `#!/bin/bash
set -e

# Logging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting SMTP server installation at $(date)"

# Update system
echo "Updating system packages..."
dnf update -y

# Install required packages
echo "Installing dependencies..."
dnf install -y \
  ${installUtils}

# Install Zig
echo "Installing Zig..."
ZIG_VERSION="${config.zigVersion}"
cd /tmp
wget https://ziglang.org/download/\${ZIG_VERSION}/zig-linux-x86_64-\${ZIG_VERSION}.tar.xz
tar -xf zig-linux-x86_64-\${ZIG_VERSION}.tar.xz
mv zig-linux-x86_64-\${ZIG_VERSION} /usr/local/zig
ln -sf /usr/local/zig/zig /usr/local/bin/zig
zig version

# Create SMTP user
echo "Creating smtp-server user..."
useradd -r -s /bin/bash -d ${config.paths.installDir} -m smtp-server

# Clone SMTP server repository
echo "Cloning SMTP server repository..."
cd ${config.paths.installDir}
git clone ${config.gitRepository} .
chown -R smtp-server:smtp-server ${config.paths.installDir}

# Build SMTP server
echo "Building SMTP server..."
cd ${config.paths.installDir}
sudo -u smtp-server zig build

# Create directories
echo "Creating directories..."
mkdir -p ${config.paths.dataDir}
mkdir -p ${config.paths.logDir}
mkdir -p ${config.paths.mailDir}
mkdir -p ${config.paths.configDir}
mkdir -p ${config.paths.backupDir}
chown -R smtp-server:smtp-server ${config.paths.dataDir}
chown -R smtp-server:smtp-server ${config.paths.logDir}
chown -R smtp-server:smtp-server ${config.paths.mailDir}

# Generate TLS certificates
echo "Generating self-signed certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\
  -keyout ${config.paths.configDir}/smtp-server.key \\
  -out ${config.paths.configDir}/smtp-server.crt \\
  -subj "/C=US/ST=State/L=City/O=Organization/CN=${scriptConfig.domainName}"
chmod 600 ${config.paths.configDir}/smtp-server.key
chown smtp-server:smtp-server ${config.paths.configDir}/smtp-server.*

# Retrieve credentials from Secrets Manager
echo "Retrieving credentials from Secrets Manager..."
aws secretsmanager get-secret-value \\
  --secret-id ${scriptConfig.secretArn} \\
  --region ${this.region} \\
  --query SecretString \\
  --output text > ${config.paths.configDir}/credentials.json
chmod 600 ${config.paths.configDir}/credentials.json
chown smtp-server:smtp-server ${config.paths.configDir}/credentials.json

# Create environment file
echo "Creating environment configuration..."
cat > ${config.paths.configDir}/smtp-server.env << 'EOF'
# SMTP Server Configuration
SMTP_PROFILE=${environment}
SMTP_HOST=0.0.0.0
SMTP_PORT=${config.smtpServer.port}
SMTP_HOSTNAME=${scriptConfig.domainName}

# TLS Configuration
SMTP_ENABLE_TLS=true
SMTP_TLS_CERT=${config.paths.configDir}/smtp-server.crt
SMTP_TLS_KEY=${config.paths.configDir}/smtp-server.key

# Authentication
SMTP_ENABLE_AUTH=true
SMTP_DB_PATH=${config.paths.dataDir}/smtp.db

# AWS S3 Storage
AWS_S3_BUCKET=${scriptConfig.bucketName}
AWS_REGION=${this.region}

# Logging
SMTP_ENABLE_JSON_LOGGING=true
SMTP_LOG_LEVEL=info

# Paths
SMTP_MAILBOX_PATH=${config.paths.mailDir}
SMTP_BACKUP_PATH=${config.paths.backupDir}

# Limits
SMTP_MAX_CONNECTIONS=${config.smtpServer.maxConnections}
SMTP_MAX_MESSAGE_SIZE=${config.smtpServer.maxMessageSize}
SMTP_MAX_RECIPIENTS=${config.smtpServer.maxRecipients}
SMTP_RATE_LIMIT_PER_IP=${config.smtpServer.rateLimitPerIp}
SMTP_RATE_LIMIT_PER_USER=${config.smtpServer.rateLimitPerUser}
EOF

chmod 600 ${config.paths.configDir}/smtp-server.env
chown smtp-server:smtp-server ${config.paths.configDir}/smtp-server.env

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/smtp-server.service << 'EOF'
[Unit]
Description=SMTP Server
After=network.target

[Service]
Type=simple
User=smtp-server
Group=smtp-server
WorkingDirectory=${config.paths.installDir}
EnvironmentFile=${config.paths.configDir}/smtp-server.env
ExecStart=${config.paths.installDir}/zig-out/bin/smtp-server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=smtp-server

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${config.paths.dataDir} ${config.paths.logDir} ${config.paths.mailDir}

[Install]
WantedBy=multi-user.target
EOF

# Configure CloudWatch Agent
echo "Configuring CloudWatch Agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "${config.paths.logDir}/*.log",
            "log_group_name": "${scriptConfig.logGroupName}",
            "log_stream_name": "{instance_id}/smtp-server",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${scriptConfig.logGroupName}",
            "log_stream_name": "{instance_id}/user-data",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "SmtpServer/${environment}",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          }
        ],
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          }
        ],
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEM_USED",
            "unit": "Percent"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\
  -a fetch-config \\
  -m ec2 \\
  -s \\
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

# Configure fail2ban
echo "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Enable and start SMTP server
echo "Starting SMTP server..."
systemctl daemon-reload
systemctl enable smtp-server
systemctl start smtp-server

# Wait for service to start
sleep 5

# Check service status
systemctl status smtp-server

echo "SMTP server installation completed at $(date)"
echo "Instance ready for use!"
`;
  }

  /**
   * Create CloudWatch alarms for monitoring
   */
  private createCloudWatchAlarms(environment: string): void {
    const envConfig = getEnvironmentConfig(environment as 'dev' | 'staging' | 'production');

    // CPU utilization alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'CpuAlarm', {
      metric: this.instance.metricCPUUtilization(),
      threshold: envConfig.alarms.cpuThreshold,
      evaluationPeriods: envConfig.alarms.evaluationPeriods,
      datapointsToAlarm: envConfig.alarms.evaluationPeriods,
      alarmDescription: `Alert when CPU exceeds ${envConfig.alarms.cpuThreshold}%`,
      alarmName: `smtp-server-cpu-${environment}`,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Status check alarm
    const statusAlarm = new cloudwatch.Alarm(this, 'StatusCheckAlarm', {
      metric: this.instance.metricStatusCheckFailed(),
      threshold: 1,
      evaluationPeriods: 2,
      datapointsToAlarm: 2,
      alarmDescription: 'Alert when instance status check fails',
      alarmName: `smtp-server-status-${environment}`,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Create Route53 DNS records
   */
  private createDnsRecords(domainName: string, hostedZoneId: string): void {
    const zone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
      hostedZoneId,
      zoneName: domainName.split('.').slice(-2).join('.'),
    });

    // A record pointing to instance
    new route53.ARecord(this, 'SmtpARecord', {
      zone,
      recordName: domainName,
      target: route53.RecordTarget.fromIpAddresses(this.instance.instancePublicIp),
      ttl: cdk.Duration.minutes(5),
    });

    // MX record
    new route53.MxRecord(this, 'SmtpMxRecord', {
      zone,
      recordName: domainName,
      values: [
        {
          hostName: domainName,
          priority: 10,
        },
      ],
      ttl: cdk.Duration.minutes(5),
    });
  }
}
