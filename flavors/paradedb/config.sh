#!/bin/bash
# ParadeDB PostgreSQL image configuration

# Flavor name (used in image naming)
export FLAVOR_NAME="paradedb"

# PostgreSQL versions to support (ParadeDB currently supports 16, 17)
export PG_VERSIONS="16 17"

# ParadeDB extension versions
export PG_ANALYTICS_VERSION="0.3.7"
export PG_SEARCH_VERSION="0.17.10"

# Description shown in workflow
export FLAVOR_DESCRIPTION="PostgreSQL with ParadeDB extensions (pg_search, pg_analytics)"
