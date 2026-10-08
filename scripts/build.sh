#!/bin/bash
# Runs inside an ubuntu:18.04 container. Builds ClamAV from the official
# source release and turns the result into dist/clamav-opt_<ver>.deb.
set -euo pipefail

: "${CLAMAV_VERSION:?set CLAMAV_VERSION, for example 1.4.6}"
: "${PKG_REVISION:=1}"
CMAKE_VERSION=3.31.6
RUST_VERSION=1.88.0          # 1.4.6 vendors crates that need edition 2024 (cargo 1.85 or newer)
PREFIX=/opt/clamav
SRC_URL="https://www.clamav.net/downloads/production/clamav-${CLAMAV_VERSION}.tar.gz"

export DEBIAN_FRONTEND=noninteractive
echo "== build dependencies"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl gcc g++ make pkg-config python3 file dpkg-dev \
  libbz2-dev libcurl4-openssl-dev libjson-c-dev libncurses5-dev \
  libpcre2-dev libssl-dev libxml2-dev zlib1g-dev >/dev/null

echo "== CMake ${CMAKE_VERSION} (18.04 ships 3.10, too old)"
curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
  | tar xz -C /opt
export PATH="/opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin:$PATH"

echo "== Rust ${RUST_VERSION} (18.04 ships 1.57, too old)"
curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION" >/dev/null
export PATH="$HOME/.cargo/bin:$PATH"
cmake --version | head -1; rustc --version; gcc --version | head -1

echo "== ClamAV ${CLAMAV_VERSION} source"
work=$(mktemp -d)
curl -fsSL "$SRC_URL" -o "$work/clamav.tar.gz"
sha256sum "$work/clamav.tar.gz"
tar xzf "$work/clamav.tar.gz" -C "$work"
cd "$work/clamav-${CLAMAV_VERSION}"

echo "== configure and build"
cmake -S . -B build -G "Unix Makefiles" \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_INSTALL_PREFIX="$PREFIX" \
  -D CMAKE_INSTALL_LIBDIR=lib \
  -D CMAKE_INSTALL_RPATH="$PREFIX/lib" \
  -D APP_CONFIG_DIRECTORY="$PREFIX/etc" \
  -D DATABASE_DIRECTORY=/var/lib/clamav14 \
  -D ENABLE_MILTER=OFF \
  -D ENABLE_TESTS=OFF \
  -D ENABLE_EXAMPLES=OFF \
  -D ENABLE_MAN_PAGES=OFF
cmake --build build -j"$(nproc)"

echo "== stage and package"
stage="$work/stage"
DESTDIR="$stage" cmake --install build >/dev/null
bash /src/scripts/package.sh "$stage" "$PREFIX" "${CLAMAV_VERSION}-${PKG_REVISION}~bionic" /src/dist
