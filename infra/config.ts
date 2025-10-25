import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Centralized Configuration for SMTP Server Infrastructure
 *
 * Modify these values to customize your deployment without editing the stack code.
 */

export interface EnvironmentConfig {
  /** EC2 instance type */
  instanceType: ec2.InstanceType;

  /** EBS volume size in GB */
  volumeSize: number;

  /** Enable CloudWatch monitoring and alarms */
  enableMonitoring: boolean;

  /** Enable automatic backups */
  enableBackups: boolean;

  /** CloudWatch log retention period */
  logRetention: logs.RetentionDays;

  /** Maximum number of AZs for VPC */
  maxAzs: number;

  /** S3 lifecycle transitions */
  s3Lifecycle: {
    /** Days until transition to Infrequent Access */
    transitionToIA: number;
    /** Days until transition to Glacier */
    transitionToGlacier: number;
  };

  /** CloudWatch alarm thresholds */
  alarms: {
    /** CPU utilization percentage threshold */
    cpuThreshold: number;
    /** Number of evaluation periods */
    evaluationPeriods: number;
  };
}

export interface SmtpServerConfig {
  /** Environment-specific configurations */
  environments: {
    dev: EnvironmentConfig;
    staging: EnvironmentConfig;
    production: EnvironmentConfig;
  };

  /** VPC CIDR block */
  vpcCidr: string;

  /** Default AWS region */
  defaultRegion: string;

  /** Zig compiler version to install */
  zigVersion: string;

  /** Git repository URL for SMTP server code */
  gitRepository: string;

  /** Network ports configuration */
  ports: {
    ssh: number;
    smtp: number;
    smtps: number;
    submission: number;
    imap: number;
    imaps: number;
    pop3: number;
    pop3s: number;
    http: number;
    https: number;
    websocket: number;
    websocketSecure: number;
  };

  /** SMTP server configuration */
  smtpServer: {
    /** Default SMTP port */
    port: number;
    /** Maximum connections */
    maxConnections: number;
    /** Maximum message size in bytes */
    maxMessageSize: number;
    /** Maximum recipients per message */
    maxRecipients: number;
    /** Rate limit per IP */
    rateLimitPerIp: number;
    /** Rate limit per user */
    rateLimitPerUser: number;
  };

  /** Security configuration */
  security: {
    /** SSH allowed CIDR blocks per environment */
    sshAllowedCidrs: {
      dev: string[];
      staging: string[];
      production: string[];
    };
    /** Require IMDSv2 for EC2 metadata */
    requireImdsv2: boolean;
    /** Enable EBS encryption */
    enableEbsEncryption: boolean;
    /** Enable S3 bucket versioning */
    enableS3Versioning: boolean;
  };

  /** Installation paths */
  paths: {
    installDir: string;
    configDir: string;
    dataDir: string;
    logDir: string;
    mailDir: string;
    backupDir: string;
  };

  /** User data script configuration */
  userData: {
    /** Enable verbose logging during installation */
    verboseLogging: boolean;
    /** Install additional utilities */
    installUtils: string[];
  };
}

/**
 * Main configuration export
 *
 * Customize these values to match your requirements
 */
export const config: SmtpServerConfig = {
  // ============================================================================
  // Environment-Specific Settings
  // ============================================================================

  environments: {
    dev: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
      volumeSize: 30,
      enableMonitoring: false,
      enableBackups: false,
      logRetention: logs.RetentionDays.ONE_WEEK,
      maxAzs: 2,
      s3Lifecycle: {
        transitionToIA: 30,
        transitionToGlacier: 90,
      },
      alarms: {
        cpuThreshold: 90,
        evaluationPeriods: 3,
      },
    },

    staging: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      volumeSize: 50,
      enableMonitoring: true,
      enableBackups: true,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      maxAzs: 2,
      s3Lifecycle: {
        transitionToIA: 30,
        transitionToGlacier: 90,
      },
      alarms: {
        cpuThreshold: 85,
        evaluationPeriods: 2,
      },
    },

    production: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE),
      volumeSize: 100,
      enableMonitoring: true,
      enableBackups: true,
      logRetention: logs.RetentionDays.ONE_MONTH,
      maxAzs: 2,
      s3Lifecycle: {
        transitionToIA: 30,
        transitionToGlacier: 90,
      },
      alarms: {
        cpuThreshold: 80,
        evaluationPeriods: 2,
      },
    },
  },

  // ============================================================================
  // Network Configuration
  // ============================================================================

  vpcCidr: '10.0.0.0/16',
  defaultRegion: 'us-east-1',

  ports: {
    ssh: 22,
    smtp: 25,
    smtps: 465,
    submission: 587,
    imap: 143,
    imaps: 993,
    pop3: 110,
    pop3s: 995,
    http: 80,
    https: 443,
    websocket: 8080,
    websocketSecure: 8443,
  },

  // ============================================================================
  // SMTP Server Settings
  // ============================================================================

  zigVersion: '0.15.1',
  gitRepository: 'https://github.com/yourusername/smtp-server.git',

  smtpServer: {
    port: 2525,
    maxConnections: 1000,
    maxMessageSize: 52428800, // 50MB
    maxRecipients: 100,
    rateLimitPerIp: 100,
    rateLimitPerUser: 200,
  },

  // ============================================================================
  // Security Configuration
  // ============================================================================

  security: {
    sshAllowedCidrs: {
      dev: ['0.0.0.0/0'], // ⚠️ Open for development - change in production!
      staging: ['0.0.0.0/0'], // ⚠️ Change to your office IP!
      production: ['YOUR_OFFICE_IP/32'], // ⚠️ MUST CHANGE THIS!
    },
    requireImdsv2: true,
    enableEbsEncryption: true,
    enableS3Versioning: true,
  },

  // ============================================================================
  // Installation Paths
  // ============================================================================

  paths: {
    installDir: '/opt/smtp-server',
    configDir: '/etc/smtp-server',
    dataDir: '/var/lib/smtp-server',
    logDir: '/var/log/smtp-server',
    mailDir: '/var/spool/mail',
    backupDir: '/var/lib/smtp-server/backups',
  },

  // ============================================================================
  // User Data Configuration
  // ============================================================================

  userData: {
    verboseLogging: true,
    installUtils: [
      'git',
      'wget',
      'curl',
      'htop',
      'vim',
      'amazon-cloudwatch-agent',
      'python3',
      'python3-pip',
      'openssl',
      'sqlite',
      'fail2ban',
    ],
  },
};

/**
 * Helper function to get environment-specific configuration
 */
export function getEnvironmentConfig(env: 'dev' | 'staging' | 'production'): EnvironmentConfig {
  return config.environments[env];
}

/**
 * Helper function to get SSH allowed CIDRs for an environment
 */
export function getSshAllowedCidrs(env: 'dev' | 'staging' | 'production'): string[] {
  return config.security.sshAllowedCidrs[env];
}

/**
 * Helper function to validate configuration
 */
export function validateConfig(): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  // Check production SSH security
  if (config.security.sshAllowedCidrs.production.includes('0.0.0.0/0')) {
    errors.push('⚠️ WARNING: Production SSH is open to the world! Change security.sshAllowedCidrs.production');
  }

  if (config.security.sshAllowedCidrs.production.includes('YOUR_OFFICE_IP/32')) {
    errors.push('⚠️ WARNING: Production SSH has placeholder IP! Update security.sshAllowedCidrs.production');
  }

  // Check Git repository
  if (config.gitRepository.includes('yourusername')) {
    errors.push('⚠️ WARNING: Update gitRepository URL to your actual repository');
  }

  // Check instance sizes make sense
  const envs = ['dev', 'staging', 'production'] as const;
  for (const env of envs) {
    const envConfig = config.environments[env];
    if (envConfig.volumeSize < 20) {
      errors.push(`⚠️ WARNING: ${env} volume size is very small (${envConfig.volumeSize}GB)`);
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Configuration presets for common scenarios
 */
export const presets = {
  /**
   * Cost-optimized configuration (minimal resources)
   */
  costOptimized: {
    dev: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      volumeSize: 20,
    },
    staging: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
      volumeSize: 30,
    },
    production: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      volumeSize: 50,
    },
  },

  /**
   * High-performance configuration (more resources)
   */
  highPerformance: {
    dev: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      volumeSize: 50,
    },
    staging: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE),
      volumeSize: 100,
    },
    production: {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.XLARGE),
      volumeSize: 200,
    },
  },

  /**
   * Development-only configuration (single environment)
   */
  devOnly: {
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
    volumeSize: 30,
    enableMonitoring: false,
    enableBackups: false,
  },
};

// Export configuration validation on import (optional)
if (process.env.VALIDATE_CONFIG === 'true') {
  const validation = validateConfig();
  if (!validation.valid) {
    console.warn('⚠️  Configuration Warnings:');
    validation.errors.forEach(error => console.warn(`   ${error}`));
  }
}
