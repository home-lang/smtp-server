# Kubernetes Deployment for SMTP Server

This directory contains Kubernetes manifests for deploying the SMTP server in a production environment.

## Prerequisites

- Kubernetes cluster (v1.24+)
- kubectl configured to access your cluster
- Persistent storage provisioner
- Optional: Prometheus Operator (for ServiceMonitor)
- Optional: Cert-Manager (for TLS certificates)

## Quick Start

### 1. Create Namespace and Resources

```bash
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f persistentvolumeclaim.yaml
```

### 2. Deploy SMTP Server

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### 3. Configure Autoscaling (Optional)

```bash
kubectl apply -f hpa.yaml
kubectl apply -f poddisruptionbudget.yaml
```

### 4. Setup Monitoring (Optional)

```bash
kubectl apply -f servicemonitor.yaml
```

### 5. Apply Network Policies (Optional)

```bash
kubectl apply -f networkpolicy.yaml
```

## Configuration

### Environment Variables

Edit `configmap.yaml` to configure the SMTP server:

- `SMTP_HOST`: Listen address (default: 0.0.0.0)
- `SMTP_PORT`: SMTP port (default: 2525)
- `SMTP_HOSTNAME`: Server hostname
- `SMTP_MAX_CONNECTIONS`: Maximum concurrent connections
- `SMTP_MAX_MESSAGE_SIZE`: Maximum message size in bytes
- `SMTP_MAX_RECIPIENTS`: Maximum recipients per message
- `SMTP_ENABLE_TLS`: Enable TLS (use ingress for production)
- `SMTP_ENABLE_AUTH`: Enable authentication
- `SMTP_ENABLE_DNSBL`: Enable DNSBL checking
- `SMTP_ENABLE_GREYLIST`: Enable greylisting

### Secrets

Edit `secret.yaml` to configure sensitive data:

- `SMTP_DB_PATH`: Database file path
- TLS certificates (if not using ingress)

### Persistent Storage

The deployment uses two PersistentVolumeClaims:

1. `smtp-data-pvc` (10Gi): Database and configuration
2. `smtp-queue-pvc` (5Gi): Message queue

Adjust sizes in `persistentvolumeclaim.yaml` based on your needs.

## Scaling

### Manual Scaling

```bash
kubectl scale deployment smtp-server -n smtp-server --replicas=5
```

### Horizontal Pod Autoscaler

The HPA automatically scales based on:
- CPU utilization (target: 70%)
- Memory utilization (target: 80%)
- Min replicas: 3
- Max replicas: 10

## Monitoring

### Health Checks

Health endpoint: `http://<pod-ip>:8080/health`

```bash
kubectl get pods -n smtp-server
kubectl port-forward -n smtp-server <pod-name> 8080:8080
curl http://localhost:8080/health
```

### Metrics

Prometheus metrics endpoint: `http://<pod-ip>:8081/metrics`

```bash
kubectl port-forward -n smtp-server <pod-name> 8081:8081
curl http://localhost:8081/metrics
```

### Viewing Logs

```bash
# View logs from all pods
kubectl logs -n smtp-server -l app=smtp-server --tail=100

# Stream logs
kubectl logs -n smtp-server -l app=smtp-server -f

# View logs from specific pod
kubectl logs -n smtp-server <pod-name>
```

## Networking

### Service Types

1. **smtp-server** (LoadBalancer): Exposes SMTP on port 25
2. **smtp-server-health** (ClusterIP): Internal health checks
3. **smtp-server-metrics** (ClusterIP): Prometheus metrics

### Network Policies

Network policies restrict traffic:
- Allow SMTP from anywhere
- Allow health checks within namespace
- Allow Prometheus scraping from monitoring namespace
- Allow DNS, SMTP relay, and HTTPS egress

## High Availability

### Pod Disruption Budget

Ensures minimum of 2 pods are always available during:
- Node maintenance
- Cluster upgrades
- Voluntary disruptions

### Session Affinity

The SMTP service uses ClientIP session affinity (3 hours) to maintain connection state.

## Security

### Container Security

- Runs as non-root (UID 1000)
- No privilege escalation
- Drops all capabilities
- Read-only root filesystem

### TLS Termination

For production, use a reverse proxy/ingress for TLS termination:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: smtp-tls
  namespace: smtp-server
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - mail.example.com
    secretName: smtp-tls-cert
  rules:
  - host: mail.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: smtp-server
            port:
              number: 25
```

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n smtp-server <pod-name>
kubectl logs -n smtp-server <pod-name>
```

### Connection issues

```bash
# Check service endpoints
kubectl get endpoints -n smtp-server smtp-server

# Test connectivity from another pod
kubectl run -it --rm debug --image=busybox --restart=Never -n smtp-server -- telnet smtp-server 2525
```

### Resource constraints

```bash
# Check resource usage
kubectl top pods -n smtp-server

# Check events
kubectl get events -n smtp-server --sort-by='.lastTimestamp'
```

### Database issues

```bash
# Access pod shell
kubectl exec -it -n smtp-server <pod-name> -- sh

# Check database
ls -la /data/
```

## Backup and Restore

### Backup PVC

```bash
# Create snapshot (if your storage class supports it)
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: smtp-data-snapshot
  namespace: smtp-server
spec:
  source:
    persistentVolumeClaimName: smtp-data-pvc
EOF
```

### Restore from backup

1. Create PVC from snapshot
2. Update deployment to use new PVC
3. Restart deployment

## Updating

### Rolling Update

```bash
# Update image
kubectl set image deployment/smtp-server smtp-server=smtp-server:v2 -n smtp-server

# Monitor rollout
kubectl rollout status deployment/smtp-server -n smtp-server

# Rollback if needed
kubectl rollout undo deployment/smtp-server -n smtp-server
```

### Blue-Green Deployment

1. Deploy new version with different label
2. Test new version
3. Update service selector
4. Remove old deployment

## Performance Tuning

### Resource Limits

Adjust based on your workload:

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### Replica Count

- Start with 3 replicas for HA
- Monitor metrics and adjust HPA settings
- Consider cluster size and node resources

## Support

For issues and questions:
- GitHub Issues: https://github.com/your-repo/issues
- Documentation: See main README.md

## License

MIT License - see LICENSE file
