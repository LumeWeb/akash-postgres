ARG PG_VERSION=15

FROM postgres:${PG_VERSION}

# Install additional tools and dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-contrib \
        prometheus-postgres-exporter \
        && \
    rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /var/log/postgresql && \
    chown -R postgres:postgres /var/log/postgresql

# Copy files
COPY --chown=postgres:postgres entrypoint.sh /entrypoint.sh
COPY --chown=postgres:postgres paths.sh /paths.sh
COPY --chown=postgres:postgres lib/ /usr/local/lib/

# Make scripts executable
RUN chmod +x /entrypoint.sh

# Configure environment
ENV METRICS_PORT=9187 \
    METRICS_USERNAME=admin \
    METRICS_PASSWORD= \
    POSTGRES_PORT=5432 \
    PGDATA=/var/lib/postgresql/data

# Define volume
VOLUME ["/var/lib/postgresql/data"]

# Expose ports
EXPOSE 8080 5432

# Switch to postgres user
USER postgres

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres"]
