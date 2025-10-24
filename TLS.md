# TLS/STARTTLS Setup Guide

## Overview

The SMTP server supports TLS configuration but requires a reverse proxy for production TLS termination. This approach is recommended for several reasons:

1. **Security**: Reverse proxies (nginx, HAProxy) are battle-tested for TLS
2. **Performance**: Optimized TLS implementations
3. **Certificate Management**: Automatic renewal with Let's Encrypt
4. **Zero Dependencies**: No need for external crypto libraries in the SMTP server

## Current TLS Status

- ✅ STARTTLS command recognized
- ✅ TLS configuration (cert/key paths)
- ✅ Certificate file loading and validation
- ⚠️ TLS handshake requires reverse proxy (see below)

## Production Setup: Reverse Proxy with TLS

### Option 1: nginx (Recommended)

#### Install nginx

```bash
# Ubuntu/Debian
sudo apt-get install nginx

# macOS
brew install nginx
```

#### Configure nginx for SMTP TLS

Create `/etc/nginx/nginx.conf` (or `/usr/local/etc/nginx/nginx.conf` on macOS):

```nginx
stream {
    upstream smtp_backend {
        server 127.0.0.1:2525;
    }

    # SMTP with STARTTLS (port 587)
    server {
        listen 587;
        proxy_pass smtp_backend;
        proxy_protocol on;
        ssl_preread on;
    }

    # SMTPS (implicit TLS on port 465)
    server {
        listen 465 ssl;
        proxy_pass smtp_backend;

        ssl_certificate /etc/letsencrypt/live/mail.example.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/mail.example.com/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
    }
}
```

#### Get Let's Encrypt Certificate

```bash
# Install certbot
sudo apt-get install certbot

# Get certificate
sudo certbot certonly --standalone -d mail.example.com

# Certificates will be in /etc/letsencrypt/live/mail.example.com/
```

#### Start Services

```bash
# Start SMTP server on port 2525
./zig-out/bin/smtp-server --port 2525

# Start nginx
sudo nginx

# Or reload nginx
sudo nginx -s reload
```

### Option 2: HAProxy

#### Install HAProxy

```bash
sudo apt-get install haproxy
```

#### Configure HAProxy

Create `/etc/haproxy/haproxy.cfg`:

```haproxy
global
    maxconn 4096
    ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2

defaults
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# SMTPS (port 465)
frontend smtp_tls
    bind *:465 ssl crt /etc/ssl/private/mail.example.com.pem
    default_backend smtp_servers

backend smtp_servers
    server smtp1 127.0.0.1:2525 check

# SMTP with STARTTLS (port 587)
frontend smtp_starttls
    bind *:587
    default_backend smtp_servers
```

### Option 3: stunnel

#### Install stunnel

```bash
sudo apt-get install stunnel4
```

#### Configure stunnel

Create `/etc/stunnel/smtp.conf`:

```ini
[smtps]
accept = 465
connect = 127.0.0.1:2525
cert = /etc/letsencrypt/live/mail.example.com/fullchain.pem
key = /etc/letsencrypt/live/mail.example.com/privkey.pem
TIMEOUTclose = 0
```

#### Start stunnel

```bash
sudo stunnel /etc/stunnel/smtp.conf
```

## Development Setup: Self-Signed Certificates

For development and testing, you can generate self-signed certificates:

### Generate Self-Signed Certificate

```bash
# Generate private key and certificate
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem \
  -out cert.pem \
  -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=mail.example.com"

# Verify the certificate
openssl x509 -in cert.pem -text -noout
```

### Configure Server

```bash
export SMTP_ENABLE_TLS=true
export SMTP_TLS_CERT=cert.pem
export SMTP_TLS_KEY=key.pem
./zig-out/bin/smtp-server
```

**Note**: The server will load and validate the certificates but requires a reverse proxy for the actual TLS handshake.

## Testing TLS Connections

### Test with openssl s_client

```bash
# Test SMTPS (implicit TLS, port 465)
openssl s_client -connect localhost:465 -starttls smtp

# Test STARTTLS (port 587)
openssl s_client -connect localhost:587 -starttls smtp
```

### Test with swaks

```bash
# Test with TLS
swaks --to recipient@example.com \
      --from sender@example.com \
      --server mail.example.com:587 \
      --tls

# Test with STARTTLS
swaks --to recipient@example.com \
      --from sender@example.com \
      --server mail.example.com:587 \
      --tls-on-connect
```

## Certificate Management

### Automatic Renewal with certbot

```bash
# Set up auto-renewal
sudo certbot renew --dry-run

# Add to crontab for automatic renewal
0 3 * * * certbot renew --quiet --deploy-hook "nginx -s reload"
```

### Certificate Monitoring

```bash
# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/mail.example.com/fullchain.pem -noout -dates

# Check certificate chain
openssl s_client -connect mail.example.com:465 -showcerts
```

## Security Best Practices

1. **Use Strong Ciphers**
   ```nginx
   ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305';
   ssl_prefer_server_ciphers on;
   ```

2. **Disable Old TLS Versions**
   ```nginx
   ssl_protocols TLSv1.2 TLSv1.3;
   ```

3. **Enable HSTS** (for webmail/admin interfaces)
   ```nginx
   add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
   ```

4. **Use OCSP Stapling**
   ```nginx
   ssl_stapling on;
   ssl_stapling_verify on;
   ssl_trusted_certificate /etc/letsencrypt/live/mail.example.com/chain.pem;
   ```

5. **Monitor Certificate Expiration**
   - Set up alerts 30 days before expiration
   - Test renewal process regularly

## Troubleshooting

### Certificate Not Found

```bash
# Check certificate files exist
ls -la /etc/letsencrypt/live/mail.example.com/

# Check permissions
sudo chmod 644 /etc/letsencrypt/live/mail.example.com/fullchain.pem
sudo chmod 600 /etc/letsencrypt/live/mail.example.com/privkey.pem
```

### TLS Handshake Failures

```bash
# Test with verbose output
openssl s_client -connect localhost:465 -starttls smtp -debug

# Check nginx error log
sudo tail -f /var/log/nginx/error.log
```

### Certificate Chain Issues

```bash
# Verify certificate chain
openssl verify -CAfile /etc/letsencrypt/live/mail.example.com/chain.pem \
               /etc/letsencrypt/live/mail.example.com/cert.pem
```

## Future: Native TLS Support

Native TLS server support would require:

1. **External Crypto Library**
   - BearSSL (lightweight, recommended)
   - OpenSSL/LibreSSL
   - mbedTLS

2. **Implementation Work**
   - TLS handshake state machine
   - Certificate chain validation
   - Session management
   - SNI support

3. **Build System Changes**
   - Link against crypto library
   - Handle cross-platform builds

For most use cases, the reverse proxy approach is simpler, more secure, and easier to maintain.

## Summary

**For Production**: Use nginx/HAProxy with Let's Encrypt certificates

**For Development**: Use self-signed certificates with the TLS module

**For Maximum Security**: Deploy behind a reverse proxy with properly configured TLS

The current implementation provides the foundation for TLS configuration while delegating the complex cryptographic operations to battle-tested reverse proxy software.
