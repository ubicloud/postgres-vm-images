#!/bin/bash
set -euo pipefail

# Install PostgreSQL packages for a specific version using dpkg
# Usage: install-postgresql-packages.sh <version>
# Example: install-postgresql-packages.sh 17

PACKAGE_CACHE="/var/cache/postgresql-packages"

usage() {
    echo "Usage: $0 <postgresql-version>"
    echo "  postgresql-version: 16, 17, or 18"
    echo ""
    echo "Example: $0 17"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^(16|17|18)$ ]]; then
    echo "Error: Invalid PostgreSQL version '$VERSION'. Must be 16, 17, or 18."
    exit 1
fi

if [[ ! -d "$PACKAGE_CACHE/$VERSION" ]]; then
    echo "Error: Package cache directory not found: $PACKAGE_CACHE/$VERSION"
    exit 1
fi

if [[ ! -d "$PACKAGE_CACHE/common" ]]; then
    echo "Error: Common package cache directory not found: $PACKAGE_CACHE/common"
    exit 1
fi

echo "Installing PostgreSQL $VERSION packages..."

# Install common packages first, then version-specific packages
# Using dpkg with --force-depends to handle dependency ordering,
# then we'll verify everything is correctly installed
dpkg -i "$PACKAGE_CACHE/common"/*.deb "$PACKAGE_CACHE/$VERSION"/*.deb

# Fail loudly if the migrator tooling did not land. dpkg -i exits 0 when the
# cache simply lacks pgcopydb, so without this check a migrator-incapable VM
# provisions green and only surfaces at exec time. The client majors are all
# staged in the common cache, so verify each -- this mirrors what the rhizome
# capability probe reports.
for bin in \
    /usr/bin/pgcopydb \
    /usr/lib/postgresql/16/bin/psql \
    /usr/lib/postgresql/17/bin/psql \
    /usr/lib/postgresql/18/bin/psql; do
    if [[ ! -x "$bin" ]]; then
        echo "Error: required migrator tool not installed: $bin" >&2
        exit 1
    fi
done

echo "PostgreSQL $VERSION packages installed successfully."
