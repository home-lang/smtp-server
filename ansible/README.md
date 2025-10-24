# Ansible Playbooks for SMTP Server

Comprehensive Ansible automation for deploying and managing the SMTP server.

## Prerequisites

- Ansible 2.10+
- Python 3.8+
- SSH access to target servers
- Sudo privileges on target servers

## Quick Start

### 1. Install Ansible

```bash
pip install ansible
```

### 2. Configure Inventory

Edit inventory files for your environment:
- `inventories/production/hosts.yml`
- `inventories/staging/hosts.yml`

### 3. Deploy

```bash
# Deploy to staging
ansible-playbook -i inventories/staging deploy.yml

# Deploy to production
ansible-playbook -i inventories/production deploy.yml

# Deploy with specific version
ansible-playbook -i inventories/production deploy.yml -e smtp_version=v1.0.0
```

## Playbooks

### deploy.yml
Full deployment of SMTP server including:
- Prerequisites installation
- User and group creation
- Binary installation
- Configuration
- TLS setup
- Firewall rules
- Backup configuration
- Monitoring setup
- Systemd service

### Partial Deployments

```bash
# Only update configuration
ansible-playbook -i inventories/production deploy.yml --tags configure

# Only restart service
ansible-playbook -i inventories/production deploy.yml --tags service

# Update TLS certificates
ansible-playbook -i inventories/production deploy.yml --tags tls
```

## Configuration

### Default Variables

See `roles/smtp-server/defaults/main.yml` for all configurable variables.

Common overrides:

```yaml
smtp_version: "v1.0.0"
smtp_port: 25
smtp_max_connections: 200
smtp_enable_tls: true
smtp_enable_auth: true
```

### Inventory Variables

Set per-environment or per-host variables in inventory files:

```yaml
smtp_servers:
  hosts:
    smtp1.example.com:
      smtp_max_connections: 300  # Override for this host
  vars:
    environment: production
    smtp_port: 25
```

## Common Tasks

### Update SMTP Server

```bash
# Update to latest version
ansible-playbook -i inventories/production deploy.yml -e smtp_version=latest

# Update to specific version
ansible-playbook -i inventories/production deploy.yml -e smtp_version=v2.0.0
```

### Manage Users

```bash
# Create user via CLI
ansible smtp_servers -i inventories/production -m shell \
  -a "user-cli create john john@example.com password123"

# List users
ansible smtp_servers -i inventories/production -m shell \
  -a "user-cli list"
```

### Check Service Status

```bash
# Check systemd status
ansible smtp_servers -i inventories/production -m systemd \
  -a "name=smtp-server"

# Check health endpoint
ansible smtp_servers -i inventories/production -m uri \
  -a "url=http://localhost:8080/health"
```

### View Logs

```bash
# Recent logs
ansible smtp_servers -i inventories/production -m shell \
  -a "journalctl -u smtp-server -n 100"

# Follow logs
ansible smtp_servers -i inventories/production -m shell \
  -a "journalctl -u smtp-server -f"
```

### Backup and Restore

```bash
# Trigger manual backup
ansible smtp_servers -i inventories/production -m shell \
  -a "/opt/smtp-server/backup.sh"

# List backups
ansible smtp_servers -i inventories/production -m shell \
  -a "ls -lh /var/lib/smtp-server/backups"
```

### Firewall Management

```bash
# Check firewall status
ansible smtp_servers -i inventories/production -m shell \
  -a "ufw status"

# Allow specific IP
ansible smtp_servers -i inventories/production -m ufw \
  -a "rule=allow from_ip=192.168.1.100 to_port=25"
```

## Security

### TLS Certificates

#### Self-Signed (Default)

Automatically generated during deployment.

#### Let's Encrypt

```yaml
tls_auto_generate: false
```

Then manually install certificates:

```bash
# On target server
certbot certonly --standalone -d smtp.example.com
ln -s /etc/letsencrypt/live/smtp.example.com/fullchain.pem /etc/smtp-server/tls/cert.pem
ln -s /etc/letsencrypt/live/smtp.example.com/privkey.pem /etc/smtp-server/tls/key.pem
```

### Firewall Rules

By default, only SMTP port is exposed. Health and metrics ports are localhost-only.

To allow monitoring from specific IPs:

```yaml
allowed_ips:
  - 192.168.1.0/24  # Monitoring network
```

## Monitoring

### Health Checks

Automated health checks run every 5 minutes via cron.

Manual check:

```bash
curl http://localhost:8080/health
```

### Metrics

Prometheus metrics available at:

```bash
curl http://localhost:8081/metrics
```

### Node Exporter

Automatically installed if `enable_prometheus: true`.

Access metrics:

```bash
curl http://localhost:9100/metrics
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
ansible smtp_servers -m shell -a "journalctl -u smtp-server -n 100"

# Check configuration
ansible smtp_servers -m shell -a "cat /etc/smtp-server/smtp.env"

# Test binary manually
ansible smtp_servers -m shell -a "su - smtp -s /bin/bash -c '/opt/smtp-server/smtp-server --version'"
```

### Connection Issues

```bash
# Test port
ansible smtp_servers -m shell -a "nc -zv localhost 25"

# Check firewall
ansible smtp_servers -m shell -a "ufw status numbered"

# Check listening ports
ansible smtp_servers -m shell -a "ss -tlnp | grep smtp"
```

### Database Issues

```bash
# Check database integrity
ansible smtp_servers -m shell \
  -a "sqlite3 /var/lib/smtp-server/smtp.db 'PRAGMA integrity_check;'"

# Check database size
ansible smtp_servers -m shell \
  -a "du -h /var/lib/smtp-server/smtp.db"
```

### Performance Issues

```bash
# Check resource usage
ansible smtp_servers -m shell -a "top -b -n 1 | grep smtp"

# Check connection count
ansible smtp_servers -m shell \
  -a "ss -tn | grep :25 | wc -l"

# Check queue size
ansible smtp_servers -m shell \
  -a "find /var/lib/smtp-server/queue -type f | wc -l"
```

## Advanced

### Rolling Updates

```bash
# Update one server at a time
ansible-playbook -i inventories/production deploy.yml --forks=1

# Update with confirmation
ansible-playbook -i inventories/production deploy.yml --step
```

### Dry Run

```bash
ansible-playbook -i inventories/production deploy.yml --check --diff
```

### Vault for Secrets

```bash
# Create encrypted vars file
ansible-vault create group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/all/vault.yml

# Deploy with vault
ansible-playbook -i inventories/production deploy.yml --ask-vault-pass
```

## Directory Structure

```
ansible/
├── ansible.cfg
├── deploy.yml
├── inventories/
│   ├── production/
│   │   └── hosts.yml
│   └── staging/
│       └── hosts.yml
└── roles/
    └── smtp-server/
        ├── defaults/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── prerequisites.yml
        │   ├── user.yml
        │   ├── install.yml
        │   ├── configure.yml
        │   ├── tls.yml
        │   ├── database.yml
        │   ├── firewall.yml
        │   ├── backup.yml
        │   ├── monitoring.yml
        │   └── service.yml
        └── templates/
            ├── smtp.env.j2
            ├── smtp-server.service.j2
            ├── logrotate.j2
            ├── backup.sh.j2
            ├── backup-cleanup.sh.j2
            └── health-check.sh.j2
```

## Support

For issues and questions:
- GitHub Issues: https://github.com/your-repo/issues
- Documentation: See main README.md

## License

MIT License - see LICENSE file
