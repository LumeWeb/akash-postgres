# Akash PostgreSQL Container

A production-ready PostgreSQL container optimized for deployment on the Akash Network, featuring automatic resource optimization, comprehensive logging, and monitoring capabilities.

## Key Features

- Automatic PostgreSQL configuration optimization based on available CPU and memory
- Kubernetes-aware resource detection for optimal Akash deployments
- Comprehensive logging system with rotation and retention policies
- Prometheus metrics export for monitoring
- Secure default configurations with SCRAM-SHA-256 authentication
- Automatic cleanup and graceful shutdown handling
- Support for custom configuration overrides

## Configuration

### Required Environment Variables

- `POSTGRES_PASSWORD`: PostgreSQL superuser password
  - Required unless `POSTGRES_HOST_AUTH_METHOD=trust` is set
  - Must be secure and meet your security requirements

### Optional Environment Variables

- `POSTGRES_PORT`: Database port (default: 5432)
- `POSTGRES_HOST_AUTH_METHOD`: Authentication method (default: scram-sha-256)
- `METRICS_PORT`: Prometheus metrics port (default: 9187)
- `METRICS_USERNAME`: Metrics endpoint username (default: admin)
- `METRICS_PASSWORD`: Metrics endpoint password
- `PGDATA`: Data directory location (default: /var/lib/postgresql/data)

## Deployment

### Akash Deployment Configuration (SDL)

```yaml
version: "2.0"

services:
  postgres:
    image: ghcr.io/akash-network/postgres:latest
    env:
      - POSTGRES_PASSWORD=your-secure-password
      - METRICS_PASSWORD=metrics-password
    expose:
      - port: 5432
        as: 5432
        to:
          - global: true
      - port: 9187
        as: 9187
        to:
          - global: true
    params:
      storage:
        data:
          mount: /var/lib/postgresql/data
          size: 20Gi

profiles:
  compute:
    postgres:
      resources:
        cpu:
          units: 1
        memory:
          size: 2Gi
        storage:
          - size: 20Gi
  placement:
    dcloud:
      pricing:
        postgres:
          denom: uakt
          amount: 1000

deployment:
  postgres:
    dcloud:
      profile: postgres
      count: 1
```

## Monitoring

View container logs:
```bash
docker logs <container_name>
```

Access Prometheus metrics:
```bash
curl -u admin:<metrics-password> http://<host>:9187/metrics
```

Key metrics are available at:
- Basic health: http://<host>:9187/health
- Prometheus metrics: http://<host>:9187/metrics
- PostgreSQL status: http://<host>:9187/postgresql

## License

This project is licensed under the MIT License - see the LICENSE file for details.
