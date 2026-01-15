#!/bin/bash
# Standard PostgreSQL image configuration

# Flavor name (used in image naming)
export FLAVOR_NAME="standard"

# PostgreSQL versions to support
export PG_VERSIONS="16 17 18"

# Description shown in workflow
export FLAVOR_DESCRIPTION="Standard PostgreSQL image with common extensions"
