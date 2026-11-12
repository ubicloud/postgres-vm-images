#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# install-postgresql-packages runs dpkg -i on the cached debs at provisioning
# time, with no apt access. Simulate that install for each cached version
# against an empty package index, so apt can only use what is already
# installed plus the cached debs. A dependency that is in neither (a library
# missing from EXTENSION_LIBS, or PGDG packages from mismatched rebuilds)
# fails the build here instead of on the first VM.

echo "=== [verify_package_cache.sh] Simulating offline package installs ==="

PACKAGE_CACHE="/var/cache/postgresql-packages"
EMPTY_APT=$(mktemp -d)
mkdir -p "$EMPTY_APT/sources.list.d" "$EMPTY_APT/lists/partial"

for dir in "$PACKAGE_CACHE"/*/; do
    version=$(basename "$dir")
    [[ "$version" == "common" ]] && continue
    echo "[verify_package_cache.sh] Checking PostgreSQL $version..."
    apt-get install --simulate --no-remove \
        -o Dir::Etc::SourceList=/dev/null \
        -o Dir::Etc::SourceParts="$EMPTY_APT/sources.list.d" \
        -o Dir::State::Lists="$EMPTY_APT/lists" \
        -o Dir::Cache::pkgcache= \
        -o Dir::Cache::srcpkgcache= \
        "$PACKAGE_CACHE"/common/*.deb "$dir"*.deb
done

rm -rf "$EMPTY_APT"

echo "=== [verify_package_cache.sh] Complete ==="
