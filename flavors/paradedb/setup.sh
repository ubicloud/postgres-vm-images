#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# Source config for versions
source /tmp/flavors/paradedb/config.sh

echo "=== ParadeDB flavor setup ==="
echo "Installing ParadeDB extensions: pg_analytics v${PG_ANALYTICS_VERSION}, pg_search v${PG_SEARCH_VERSION}"

# Install ParadeDB extensions for each supported PostgreSQL version
for PG_VERSION in $PG_VERSIONS; do
    echo "=== Installing ParadeDB extensions for PostgreSQL ${PG_VERSION} ==="

    # Install pg_analytics
    curl -L -o /tmp/postgresql-${PG_VERSION}-pg-analytics_${PG_ANALYTICS_VERSION}-1PARADEDB-jammy_amd64.deb \
        "https://github.com/paradedb/pg_analytics/releases/download/v${PG_ANALYTICS_VERSION}/postgresql-${PG_VERSION}-pg-analytics_${PG_ANALYTICS_VERSION}-1PARADEDB-jammy_amd64.deb"
    apt-get install -y /tmp/postgresql-${PG_VERSION}-pg-analytics_${PG_ANALYTICS_VERSION}-1PARADEDB-jammy_amd64.deb

    # Install pg_search
    curl -L -o /tmp/postgresql-${PG_VERSION}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-jammy_amd64.deb \
        "https://github.com/paradedb/paradedb/releases/download/v${PG_SEARCH_VERSION}/postgresql-${PG_VERSION}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-jammy_amd64.deb"
    apt-get install -y /tmp/postgresql-${PG_VERSION}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-jammy_amd64.deb
done

# Clean up downloaded debs
rm -f /tmp/*.deb

echo "=== ParadeDB flavor setup complete ==="
