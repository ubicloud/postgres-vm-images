#!/bin/bash
# Postgres OS disks are created from image on Object store, resulting in a slow
# first time load. During Postgres package installation this results in 
# 30+ seconds total delay during the installation.
# Pre-loading Postgres packages in Linux page cache reduces the package installation
# time to single digit seconds.
set -uo pipefail

find /var/lib/dpkg /var/cache/postgresql-packages -type f -print0 2>/dev/null |
    xargs -0 -P 16 -n 16 cat > /dev/null 2>&1

exit 0
