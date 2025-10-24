# Configuration Guide

**Version:** v0.21.0
**Date:** 2025-10-24

## Overview

The SMTP server supports configuration through multiple methods:
1. **Environment Variables** (highest priority)
2. **Command-line Arguments**
3. **Default Values** (lowest priority)

## Configuration Priority

```
Environment Variables > Command-line Args > Defaults
```

## Quick Start

### Basic Setup

```bash
# Minimal configuration
SMTP_HOST=0.0.0.0 \
SMTP_PORT=2525 \
./smtp-server
```

### Production Setup

```bash
# Production configuration
SMTP_HOST=0.0.0.0 \
SMTP_PORT=2525 \
SMTP_HOSTNAME=mail.example.com \
SMTP_MAX_CONNECTIONS=500 \
SMTP_ENABLE_AUTH=true \
SMTP_DB_PATH=/var/lib/smtp-server/smtp.db \
SMTP_ENABLE_DNSBL=true \
SMTP_ENABLE_GREYLIST=true \
SMTP_WEBHOOK_URL=https://api.example.com/webhook \
./smtp-server
```

## Configuration Reference

### Server Settings

#### SMTP_HOST
- **Description:** IP address to bind to
- **Type:** String (IP address)
- **Default:** `0.0.0.0` (all interfaces)
- **Examples:**
  ```bash
  SMTP_HOST=0.0.0.0        # Listen on all interfaces
  SMTP_HOST=127.0.0.1      # Listen on localhost only
  SMTP_HOST=192.168.1.100  # Listen on specific IP
  ```

#### SMTP_PORT
- **Description:** Port to listen on
- **Type:** Integer (1-65535)
- **Default:** `2525` (non-privileged)
- **Common Values:**
  - `25` - Standard SMTP (requires root)
  - `587` - SMTP Submission (requires root)
  - `2525` - Development/non-privileged
- **Examples:**
  ```bash
  SMTP_PORT=2525   # Development
  SMTP_PORT=25     # Production (with TLS proxy)
  ```

#### SMTP_HOSTNAME
- **Description:** Server hostname for SMTP greeting
- **Type:** String
- **Default:** `localhost`
- **Examples:**
  ```bash
  SMTP_HOSTNAME=mail.example.com
  SMTP_HOSTNAME=smtp.company.org
  ```

---

### Connection Limits

#### SMTP_MAX_CONNECTIONS
- **Description:** Maximum concurrent connections
- **Type:** Integer
- **Default:** `100`
- **Recommended:**
  - Small servers: 100-500
  - Medium servers: 500-2000
  - Large servers: 2000-10000
- **Examples:**
  ```bash
  SMTP_MAX_CONNECTIONS=100    # Small deployment
  SMTP_MAX_CONNECTIONS=1000   # Medium deployment
  SMTP_MAX_CONNECTIONS=5000   # Large deployment
  ```

---

### Timeout Configuration

The server supports granular timeout settings for different phases of SMTP communication.

#### SMTP_TIMEOUT_SECONDS
- **Description:** General connection timeout
- **Type:** Integer (seconds)
- **Default:** `300` (5 minutes)
- **Range:** 60-3600 seconds
- **Purpose:** Overall connection lifetime limit
- **Examples:**
  ```bash
  SMTP_TIMEOUT_SECONDS=300    # 5 minutes (default)
  SMTP_TIMEOUT_SECONDS=600    # 10 minutes (relaxed)
  ```

#### SMTP_DATA_TIMEOUT_SECONDS
- **Description:** Timeout for DATA command (message upload)
- **Type:** Integer (seconds)
- **Default:** `600` (10 minutes)
- **Range:** 300-3600 seconds
- **Purpose:** Allow time for large message uploads
- **Examples:**
  ```bash
  SMTP_DATA_TIMEOUT_SECONDS=600   # 10 minutes (default)
  SMTP_DATA_TIMEOUT_SECONDS=1200  # 20 minutes (large messages)
  SMTP_DATA_TIMEOUT_SECONDS=300   # 5 minutes (strict)
  ```

#### SMTP_COMMAND_TIMEOUT_SECONDS
- **Description:** Timeout between SMTP commands
- **Type:** Integer (seconds)
- **Default:** `300` (5 minutes)
- **Range:** 60-600 seconds
- **Purpose:** Prevent idle connections
- **Examples:**
  ```bash
  SMTP_COMMAND_TIMEOUT_SECONDS=300  # 5 minutes (default)
  SMTP_COMMAND_TIMEOUT_SECONDS=120  # 2 minutes (strict)
  ```

#### SMTP_GREETING_TIMEOUT_SECONDS
- **Description:** Timeout for initial client greeting
- **Type:** Integer (seconds)
- **Default:** `30` (30 seconds)
- **Range:** 10-120 seconds
- **Purpose:** Quickly disconnect slow/broken clients
- **Examples:**
  ```bash
  SMTP_GREETING_TIMEOUT_SECONDS=30   # 30 seconds (default)
  SMTP_GREETING_TIMEOUT_SECONDS=60   # 1 minute (relaxed)
  SMTP_GREETING_TIMEOUT_SECONDS=10   # 10 seconds (strict)
  ```

#### Timeout Configuration Examples

**Conservative (relaxed timeouts):**
```bash
SMTP_TIMEOUT_SECONDS=600
SMTP_DATA_TIMEOUT_SECONDS=1200
SMTP_COMMAND_TIMEOUT_SECONDS=600
SMTP_GREETING_TIMEOUT_SECONDS=60
```

**Balanced (recommended):**
```bash
SMTP_TIMEOUT_SECONDS=300
SMTP_DATA_TIMEOUT_SECONDS=600
SMTP_COMMAND_TIMEOUT_SECONDS=300
SMTP_GREETING_TIMEOUT_SECONDS=30
```

**Aggressive (strict timeouts):**
```bash
SMTP_TIMEOUT_SECONDS=120
SMTP_DATA_TIMEOUT_SECONDS=300
SMTP_COMMAND_TIMEOUT_SECONDS=120
SMTP_GREETING_TIMEOUT_SECONDS=10
```

---

### Message Limits

#### SMTP_MAX_MESSAGE_SIZE
- **Description:** Maximum message size in bytes
- **Type:** Integer
- **Default:** `10485760` (10 MB)
- **Recommended:** 10MB - 50MB
- **Examples:**
  ```bash
  SMTP_MAX_MESSAGE_SIZE=10485760   # 10 MB
  SMTP_MAX_MESSAGE_SIZE=52428800   # 50 MB
  SMTP_MAX_MESSAGE_SIZE=104857600  # 100 MB
  ```

#### SMTP_MAX_RECIPIENTS
- **Description:** Maximum recipients per message
- **Type:** Integer
- **Default:** `100`
- **Recommended:** 50-500
- **Examples:**
  ```bash
  SMTP_MAX_RECIPIENTS=100   # Default
  SMTP_MAX_RECIPIENTS=50    # Strict (anti-spam)
  SMTP_MAX_RECIPIENTS=500   # Mailing lists
  ```

---

### Rate Limiting

#### SMTP_RATE_LIMIT_PER_IP
- **Description:** Maximum messages per hour per IP address
- **Type:** Integer
- **Default:** `100`
- **Purpose:** Prevent spam and abuse from individual IPs
- **Examples:**
  ```bash
  SMTP_RATE_LIMIT_PER_IP=100   # Default
  SMTP_RATE_LIMIT_PER_IP=50    # Strict
  SMTP_RATE_LIMIT_PER_IP=1000  # High volume
  ```

#### SMTP_RATE_LIMIT_PER_USER
- **Description:** Maximum messages per hour per authenticated user
- **Type:** Integer
- **Default:** `200`
- **Purpose:** Separate rate limit for authenticated users (typically higher than IP limit)
- **Examples:**
  ```bash
  SMTP_RATE_LIMIT_PER_USER=200   # Default
  SMTP_RATE_LIMIT_PER_USER=100   # Strict
  SMTP_RATE_LIMIT_PER_USER=5000  # High volume authenticated users
  ```
- **Note:** This applies only to authenticated SMTP submissions. Unauthenticated connections still use IP-based limiting.

#### SMTP_RATE_LIMIT_CLEANUP_INTERVAL
- **Description:** How often (in seconds) to clean up old rate limit entries
- **Type:** Integer (seconds)
- **Default:** `3600` (1 hour)
- **Purpose:** Memory management for rate limiter hashmaps
- **Examples:**
  ```bash
  SMTP_RATE_LIMIT_CLEANUP_INTERVAL=3600  # Default - 1 hour
  SMTP_RATE_LIMIT_CLEANUP_INTERVAL=1800  # 30 minutes for high traffic
  SMTP_RATE_LIMIT_CLEANUP_INTERVAL=7200  # 2 hours for low traffic
  ```
- **Recommendation:** For high-traffic servers, use shorter intervals (30-60 minutes). For low-traffic servers, longer intervals (2-4 hours) are fine.

---

### Authentication

#### SMTP_ENABLE_AUTH
- **Description:** Enable SMTP authentication
- **Type:** Boolean
- **Default:** `true`
- **Values:** `true`, `false`, `1`, `0`
- **Examples:**
  ```bash
  SMTP_ENABLE_AUTH=true    # Enable (recommended)
  SMTP_ENABLE_AUTH=false   # Disable (open relay - DANGEROUS)
  ```

#### SMTP_DB_PATH
- **Description:** Path to SQLite database for user authentication
- **Type:** String (file path)
- **Default:** `./smtp.db`
- **Examples:**
  ```bash
  SMTP_DB_PATH=/var/lib/smtp-server/smtp.db
  SMTP_DB_PATH=/data/smtp/users.db
  ```

---

### TLS Configuration

#### SMTP_ENABLE_TLS
- **Description:** Enable native STARTTLS support
- **Type:** Boolean
- **Default:** `false`
- **Note:** **Use TLS proxy instead** (see [TLS_PROXY_SETUP.md](./TLS_PROXY_SETUP.md))
- **Examples:**
  ```bash
  SMTP_ENABLE_TLS=false    # Recommended (use proxy)
  SMTP_ENABLE_TLS=true     # Experimental (cipher issues)
  ```

#### SMTP_TLS_CERT
- **Description:** Path to TLS certificate file
- **Type:** String (file path)
- **Required if:** `SMTP_ENABLE_TLS=true`
- **Format:** PEM
- **Examples:**
  ```bash
  SMTP_TLS_CERT=/etc/ssl/certs/mail.example.com.crt
  SMTP_TLS_CERT=/opt/smtp-server/certs/server.pem
  ```

#### SMTP_TLS_KEY
- **Description:** Path to TLS private key file
- **Type:** String (file path)
- **Required if:** `SMTP_ENABLE_TLS=true`
- **Format:** PEM
- **Examples:**
  ```bash
  SMTP_TLS_KEY=/etc/ssl/private/mail.example.com.key
  SMTP_TLS_KEY=/opt/smtp-server/certs/server-key.pem
  ```

---

### Spam Prevention

#### SMTP_ENABLE_DNSBL
- **Description:** Enable DNSBL/RBL spam checking
- **Type:** Boolean
- **Default:** `false` (performance impact)
- **Purpose:** Block known spam sources
- **Examples:**
  ```bash
  SMTP_ENABLE_DNSBL=true   # Enable spam checking
  SMTP_ENABLE_DNSBL=false  # Disable (faster)
  ```

**DNSBL Lists Used:**
- zen.spamhaus.org
- bl.spamcop.net
- dnsbl.sorbs.net

#### SMTP_ENABLE_GREYLIST
- **Description:** Enable greylisting for spam prevention
- **Type:** Boolean
- **Default:** `false`
- **Purpose:** Temporarily reject unknown sender/recipient/IP triplets
- **Examples:**
  ```bash
  SMTP_ENABLE_GREYLIST=true   # Enable greylisting
  SMTP_ENABLE_GREYLIST=false  # Disable
  ```

**Greylist Parameters:**
- Initial delay: 5 minutes
- Retry window: 4 hours
- Auto-whitelist after: 36 days

---

### Webhook Integration

#### SMTP_WEBHOOK_URL
- **Description:** Webhook URL for message notifications
- **Type:** String (URL)
- **Protocols:** HTTP, HTTPS
- **Examples:**
  ```bash
  SMTP_WEBHOOK_URL=https://api.example.com/webhook
  SMTP_WEBHOOK_URL=http://localhost:3000/smtp-events
  ```

#### SMTP_WEBHOOK_ENABLED
- **Description:** Enable webhook notifications
- **Type:** Boolean
- **Default:** `false` (enabled if URL provided)
- **Examples:**
  ```bash
  SMTP_WEBHOOK_ENABLED=true
  SMTP_WEBHOOK_ENABLED=false
  ```

**Webhook Payload:**
```json
{
  "from": "sender@example.com",
  "recipients": ["recipient1@example.com", "recipient2@example.com"],
  "size": 12345,
  "timestamp": 1234567890,
  "remote_addr": "192.168.1.100"
}
```

---

## Configuration Files

### systemd Service with Environment File

**Create `/etc/smtp-server/config`:**
```bash
# Server
SMTP_HOST=0.0.0.0
SMTP_PORT=2525
SMTP_HOSTNAME=mail.example.com
SMTP_MAX_CONNECTIONS=500

# Timeouts
SMTP_TIMEOUT_SECONDS=300
SMTP_DATA_TIMEOUT_SECONDS=600
SMTP_COMMAND_TIMEOUT_SECONDS=300
SMTP_GREETING_TIMEOUT_SECONDS=30

# Message Limits
SMTP_MAX_MESSAGE_SIZE=52428800
SMTP_MAX_RECIPIENTS=100

# Authentication
SMTP_ENABLE_AUTH=true
SMTP_DB_PATH=/var/lib/smtp-server/smtp.db

# Spam Prevention
SMTP_ENABLE_DNSBL=true
SMTP_ENABLE_GREYLIST=true

# Webhook
SMTP_WEBHOOK_URL=https://api.example.com/webhook
SMTP_WEBHOOK_ENABLED=true

# Rate Limiting
SMTP_RATE_LIMIT_PER_IP=100
SMTP_RATE_LIMIT_PER_USER=200
SMTP_RATE_LIMIT_CLEANUP_INTERVAL=3600
```

**Create `/etc/systemd/system/smtp-server.service`:**
```ini
[Unit]
Description=SMTP Server
After=network.target

[Service]
Type=simple
User=smtp
Group=smtp
WorkingDirectory=/opt/smtp-server
EnvironmentFile=/etc/smtp-server/config
ExecStart=/opt/smtp-server/smtp-server
Restart=always
RestartSec=5

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/smtp-server

[Install]
WantedBy=multi-user.target
```

---

## Configuration Profiles

### Development Profile

```bash
# .env.development
SMTP_HOST=127.0.0.1
SMTP_PORT=2525
SMTP_HOSTNAME=localhost
SMTP_MAX_CONNECTIONS=10
SMTP_ENABLE_AUTH=false
SMTP_ENABLE_DNSBL=false
SMTP_ENABLE_GREYLIST=false
SMTP_MAX_MESSAGE_SIZE=10485760
SMTP_TIMEOUT_SECONDS=600
```

### Staging Profile

```bash
# .env.staging
SMTP_HOST=0.0.0.0
SMTP_PORT=2525
SMTP_HOSTNAME=mail-staging.example.com
SMTP_MAX_CONNECTIONS=100
SMTP_ENABLE_AUTH=true
SMTP_DB_PATH=/var/lib/smtp-server/staging.db
SMTP_ENABLE_DNSBL=false
SMTP_ENABLE_GREYLIST=false
SMTP_WEBHOOK_URL=https://staging-api.example.com/webhook
```

### Production Profile

```bash
# .env.production
SMTP_HOST=0.0.0.0
SMTP_PORT=2525
SMTP_HOSTNAME=mail.example.com
SMTP_MAX_CONNECTIONS=1000
SMTP_ENABLE_AUTH=true
SMTP_DB_PATH=/var/lib/smtp-server/production.db
SMTP_ENABLE_DNSBL=true
SMTP_ENABLE_GREYLIST=true
SMTP_WEBHOOK_URL=https://api.example.com/webhook
SMTP_MAX_MESSAGE_SIZE=52428800
SMTP_MAX_RECIPIENTS=100
SMTP_RATE_LIMIT_PER_IP=100
SMTP_RATE_LIMIT_PER_USER=200
SMTP_RATE_LIMIT_CLEANUP_INTERVAL=3600
SMTP_TIMEOUT_SECONDS=300
SMTP_DATA_TIMEOUT_SECONDS=600
SMTP_COMMAND_TIMEOUT_SECONDS=300
SMTP_GREETING_TIMEOUT_SECONDS=30
```

---

## Docker Configuration

### docker-compose.yml

```yaml
version: '3.8'

services:
  smtp-server:
    image: smtp-server:latest
    container_name: smtp-server
    restart: unless-stopped
    ports:
      - "2525:2525"
    environment:
      - SMTP_HOST=0.0.0.0
      - SMTP_PORT=2525
      - SMTP_HOSTNAME=mail.example.com
      - SMTP_MAX_CONNECTIONS=500
      - SMTP_ENABLE_AUTH=true
      - SMTP_DB_PATH=/data/smtp.db
      - SMTP_ENABLE_DNSBL=true
      - SMTP_ENABLE_GREYLIST=true
      - SMTP_WEBHOOK_URL=https://api.example.com/webhook
      - SMTP_MAX_MESSAGE_SIZE=52428800
      - SMTP_TIMEOUT_SECONDS=300
      - SMTP_DATA_TIMEOUT_SECONDS=600
    volumes:
      - ./data:/data
      - ./logs:/logs
    networks:
      - mail-network

networks:
  mail-network:
    driver: bridge
```

---

## Kubernetes Configuration

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: smtp-server-config
  namespace: mail
data:
  SMTP_HOST: "0.0.0.0"
  SMTP_PORT: "2525"
  SMTP_HOSTNAME: "mail.example.com"
  SMTP_MAX_CONNECTIONS: "1000"
  SMTP_ENABLE_AUTH: "true"
  SMTP_DB_PATH: "/data/smtp.db"
  SMTP_ENABLE_DNSBL: "true"
  SMTP_ENABLE_GREYLIST: "true"
  SMTP_MAX_MESSAGE_SIZE: "52428800"
  SMTP_TIMEOUT_SECONDS: "300"
  SMTP_DATA_TIMEOUT_SECONDS: "600"
  SMTP_COMMAND_TIMEOUT_SECONDS: "300"
  SMTP_GREETING_TIMEOUT_SECONDS: "30"
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: smtp-server-secrets
  namespace: mail
type: Opaque
stringData:
  SMTP_WEBHOOK_URL: "https://api.example.com/webhook"
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smtp-server
  namespace: mail
spec:
  replicas: 3
  selector:
    matchLabels:
      app: smtp-server
  template:
    metadata:
      labels:
        app: smtp-server
    spec:
      containers:
      - name: smtp-server
        image: smtp-server:latest
        ports:
        - containerPort: 2525
        envFrom:
        - configMapRef:
            name: smtp-server-config
        - secretRef:
            name: smtp-server-secrets
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: smtp-server-data
```

---

## Validation

### Check Configuration

```bash
# Print current configuration
./smtp-server --help

# Test configuration
SMTP_PORT=2525 ./smtp-server &
SERVER_PID=$!

# Test connection
telnet localhost 2525

# Cleanup
kill $SERVER_PID
```

### Verify Environment Variables

```bash
# List all SMTP environment variables
env | grep SMTP_

# Check specific setting
echo $SMTP_PORT
```

---

## Troubleshooting

### Configuration Not Applied

**Problem:** Changes not taking effect

**Solutions:**
1. Check environment variable syntax:
   ```bash
   # Correct
   SMTP_PORT=2525

   # Incorrect
   SMTP_PORT = 2525  # No spaces
   ```

2. Verify systemd service file:
   ```bash
   sudo systemctl cat smtp-server.service
   ```

3. Restart service:
   ```bash
   sudo systemctl restart smtp-server
   ```

### Port Already in Use

**Problem:** `Address already in use`

**Solutions:**
1. Check what's using the port:
   ```bash
   sudo lsof -i :2525
   ```

2. Use different port:
   ```bash
   SMTP_PORT=2526 ./smtp-server
   ```

### Permission Denied

**Problem:** Cannot bind to privileged port (< 1024)

**Solutions:**
1. Use non-privileged port with proxy
2. Run as root (not recommended)
3. Use capabilities:
   ```bash
   sudo setcap 'cap_net_bind_service=+ep' ./smtp-server
   ```

---

## Best Practices

1. **Use Environment Variables:** Easier to manage across environments
2. **Enable Authentication:** Prevent open relay abuse
3. **Use TLS Proxy:** More reliable than native STARTTLS
4. **Set Appropriate Timeouts:** Balance between usability and resource usage
5. **Enable DNSBL/Greylist:** Reduce spam (production only)
6. **Configure Webhooks:** Enable event notifications
7. **Set Rate Limits:** Prevent abuse
8. **Monitor Configuration:** Log configuration at startup

---

## See Also

- [TLS Proxy Setup](./TLS_PROXY_SETUP.md)
- [Thread Safety Audit](./THREAD_SAFETY_AUDIT.md)
- [Known Issues](./KNOWN_ISSUES_AND_SOLUTIONS.md)
- [Deployment Guide](./DEPLOYMENT.md)

---

**Last Updated:** 2025-10-24
**Version:** v0.21.0
