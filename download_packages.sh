#!/bin/bash
set -uexo pipefail

export DEBIAN_FRONTEND=noninteractive

# Create download directory
mkdir -p downloads/packages downloads/binaries downloads/sources

echo "=== Downloading packages for Ubuntu 22.04 (jammy) ==="

# Helper function to download a package for jammy
download_pg_package() {
    local pkg=$1

    # Try to find and download the package
    echo "Downloading $pkg..."

    # Get package info from PostgreSQL APT repository
    wget -q -O - "http://apt.postgresql.org/pub/repos/apt/dists/jammy-pgdg/main/binary-amd64/Packages.gz" | \
        gunzip | \
        awk -v pkg="$pkg" '
            $1 == "Package:" && $2 == pkg { found=1 }
            found && $1 == "Filename:" { print $2; found=0 }
        ' | head -1 | while read filename; do
        if [ -n "$filename" ]; then
            wget -q -P downloads/packages "http://apt.postgresql.org/pub/repos/apt/$filename" || true
        fi
    done
}

# Download monitoring binaries first (these don't depend on release)
echo "=== Downloading monitoring binaries ==="

wget -q https://github.com/prometheus/prometheus/releases/download/v2.53.0/prometheus-2.53.0.linux-amd64.tar.gz \
  -O downloads/binaries/prometheus-2.53.0.linux-amd64.tar.gz &

wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz \
  -O downloads/binaries/node_exporter-1.8.1.linux-amd64.tar.gz &

wget -q https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz \
  -O downloads/binaries/postgres_exporter-0.15.0.linux-amd64.tar.gz &

wait

echo "=== Downloading PostgreSQL packages for jammy ==="

# Read all package names
cat assets/16.txt assets/17.txt assets/18.txt assets/common.txt > downloads/all-packages.txt

# Download PostgreSQL packages
while read pkg; do
    download_pg_package "$pkg"
done < downloads/all-packages.txt

# Download build dependencies from Ubuntu jammy repos
echo "=== Downloading build dependencies from Ubuntu jammy ==="
cd downloads/packages

# These URLs are for jammy packages from Ubuntu archives
wget -q http://archive.ubuntu.com/ubuntu/pool/main/m/make-dfsg/make_4.3-4.1build1_amd64.deb || true
wget -q http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-11/gcc_11.4.0-1ubuntu1~22.04_amd64.deb || true
wget -q http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-11/g++_11.4.0-1ubuntu1~22.04_amd64.deb || true
wget -q http://archive.ubuntu.com/ubuntu/pool/main/b/build-essential/build-essential_12.9ubuntu3_amd64.deb || true
wget -q http://archive.ubuntu.com/ubuntu/pool/main/c/cmake/cmake_3.22.1-1ubuntu1.22.04.2_amd64.deb || true
wget -q http://archive.ubuntu.com/ubuntu/pool/main/g/git/git_2.34.1-1ubuntu1.11_amd64.deb || true

# Download golang from PPA
wget -q https://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu/pool/main/g/golang-1.22/golang-1.22-go_1.22.10-1longsleep1%7Eubuntu22.04.1_amd64.deb -O golang-1.22-go.deb || true
wget -q https://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu/pool/main/g/golang-1.22/golang-1.22_1.22.10-1longsleep1%7Eubuntu22.04.1_all.deb -O golang-1.22.deb || true
wget -q https://ppa.launchpadcontent.net/longsleep/golang-backports/ubuntu/pool/main/g/golang-defaults/golang-go_1.22.4-1longsleep1%7Eubuntu22.04.1_amd64.deb -O golang-go.deb || true

cd ../..

echo "=== Cloning WAL-G source ==="
if [ -d downloads/sources/wal-g ]; then
    rm -rf downloads/sources/wal-g
fi

cd downloads/sources
git init wal-g
cd wal-g
git remote add origin https://github.com/wal-g/wal-g.git
git fetch origin --depth 1 cf1ce0f5b69048e31d740b508a79d8294707e339
git reset --hard FETCH_HEAD
cd ..

echo "=== Cloning pguint source ==="
if [ -d pguint ]; then
    rm -rf pguint
fi

git clone --depth 1 https://github.com/petere/pguint.git
cd ../..

echo "=== Download Summary ==="
echo "PostgreSQL packages: $(ls downloads/packages/*.deb 2>/dev/null | wc -l) files"
echo "Monitoring binaries: $(ls downloads/binaries/*.tar.gz 2>/dev/null | wc -l) files"
echo "WAL-G source: $(du -sh downloads/sources/wal-g 2>/dev/null | cut -f1)"
echo "pguint source: $(du -sh downloads/sources/pguint 2>/dev/null | cut -f1)"

echo ""
echo "All downloads complete! Ready to build."
