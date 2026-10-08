#!/bin/bash
# Turns a staged install tree into a .deb. Run inside the 18.04 build container.
# Usage: package.sh <stage dir> <prefix> <version> <output dir>
set -euo pipefail
stage=$1 prefix=$2 version=$3 out=$4
pkg=clamav-opt
here=$(cd "$(dirname "$0")/.." && pwd)

# Our own config templates, systemd units and maintainer scripts.
install -d "$stage$prefix/etc" "$stage/lib/systemd/system" "$stage/DEBIAN"
install -m 0644 "$here/packaging/etc/clamd.conf"     "$stage$prefix/etc/clamd.conf"
install -m 0644 "$here/packaging/etc/freshclam.conf" "$stage$prefix/etc/freshclam.conf"
install -m 0644 "$here"/packaging/systemd/*.service  "$stage/lib/systemd/system/"
install -m 0755 "$here/packaging/debian/postinst"    "$stage/DEBIAN/postinst"
install -m 0755 "$here/packaging/debian/postrm"      "$stage/DEBIAN/postrm"
printf '%s\n' "$prefix/etc/clamd.conf" "$prefix/etc/freshclam.conf" > "$stage/DEBIAN/conffiles"

# Work out runtime dependencies from what the binaries actually link to.
deps=$(find "$stage$prefix" -type f -exec file {} + | grep -E 'ELF .* (executable|shared object)' | cut -d: -f1 \
  | xargs -r env LD_LIBRARY_PATH="$stage$prefix/lib" ldd 2>/dev/null \
  | awk '/=> \// {print $3}' | grep -v "^$stage" | sort -u \
  | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u \
  | grep -v -E '^(libc6|libgcc1|libstdc\+\+6)$' | paste -sd, - | sed 's/,/, /g')
echo "runtime dependencies: $deps"

cat > "$stage/DEBIAN/control" <<CTRL
Package: $pkg
Version: $version
Architecture: amd64
Maintainer: johnyhost <noreply@github.com>
Depends: libc6 (>= 2.27), $deps
Section: utils
Priority: optional
Homepage: https://github.com/johnyhost/ClamAV-Bionic
Description: ClamAV ${version%%-*} built for Ubuntu 18.04, installed in $prefix
 Official ClamAV source built in an ubuntu:18.04 container. Lives entirely
 under $prefix with its database in /var/lib/clamav14 and services
 clamav14-daemon and clamav14-freshclam. Does not replace or touch Ubuntu's
 own clamav packages; services are not enabled on install.
CTRL

mkdir -p "$out"
dpkg-deb --root-owner-group --build "$stage" "$out/${pkg}_${version}_amd64.deb"
dpkg-deb --info "$out/${pkg}_${version}_amd64.deb"
