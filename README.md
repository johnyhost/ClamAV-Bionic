# ClamAV-Bionic

**Current ClamAV for Ubuntu 18.04 (Bionic), as an installable `.deb`.**

Ubuntu 18.04 ships ClamAV 0.103, which reached end of life on 14 September
2024. ClamAV's download servers now refuse end-of-life versions, so on 18.04
the virus definitions silently stop updating. ClamAV's own ready-made 1.4
packages need glibc 2.28 or newer, and 18.04 has 2.27, so they will not run
either.

This repository builds ClamAV 1.4 LTS from the official source inside an
`ubuntu:18.04` container on GitHub Actions, so the result links against exactly
the libraries an 18.04 system has. It is published as a `.deb` that installs
beside Ubuntu's own ClamAV without touching it.

This is an unofficial build. It is not affiliated with or supported by Cisco
Talos, the maintainers of ClamAV.

## Is this for you?

Use it if you run Ubuntu 18.04, typically with Ubuntu Pro extended security
maintenance, and need a ClamAV that still receives virus definitions: for
example on a mail server with amavis.

You do not need it on Ubuntu 20.04 or newer. Those releases get a supported
ClamAV through normal updates.

## What you get

| | |
| --- | --- |
| ClamAV version | 1.4.6 (1.4 is a long-term support line: patches until August 2027, definitions until August 2028) |
| Package name | `clamav-opt` |
| Programs | `/opt/clamav/bin` (`clamscan`, `clamdscan`, `freshclam`, `sigtool` and others) and `/opt/clamav/sbin/clamd` |
| Configuration | `/opt/clamav/etc/clamd.conf` and `/opt/clamav/etc/freshclam.conf` |
| Definitions | `/var/lib/clamav14` |
| Scanner socket | `/run/clamav14/clamd.ctl` |
| Services | `clamav14-freshclam` (updates definitions twice a day) and `clamav14-daemon` (the scanner) |
| Runs as | the `clamav` system user, created if it does not exist |
| Memory | about 1 to 1.5 GB for the scanner with current definitions |

Every name and path differs from Ubuntu's `clamav` packages, so both can be
installed at the same time. That is what makes switching over, and back, safe.

Installing the package does **not** start anything. Both services stay off
until you enable them.

Not included: `clamav-milter` (build it yourself with `ENABLE_MILTER=ON` if you
need it) and a ready configuration for on-access scanning (`clamonacc` is
installed but not set up).

## Install

Download the `.deb` and `SHA256SUMS` from the
[latest release](https://github.com/johnyhost/ClamAV-Bionic/releases/latest),
check the checksum, and install:

```bash
cd /tmp
wget https://github.com/johnyhost/ClamAV-Bionic/releases/download/v1.4.6-2/clamav-opt_1.4.6-2_bionic_amd64.deb
wget https://github.com/johnyhost/ClamAV-Bionic/releases/download/v1.4.6-2/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
sudo apt install ./clamav-opt_1.4.6-2_bionic_amd64.deb
/opt/clamav/bin/clamscan --version
```

`apt` pulls in any missing runtime libraries from Ubuntu's archive.

## Start it

### 1. Download definitions

```bash
sudo systemctl enable --now clamav14-freshclam
sleep 120 && ls -l /var/lib/clamav14
```

You should see `main.cvd`, `daily.cvd` (or `.cld`) and `bytecode.cvd`. A
warning that clamd "was NOT notified" is expected at this point, because the
scanner is not running yet.

### 2. Check memory, then start the scanner

```bash
free -m
```

The scanner needs about 1 to 1.5 GB. If an old ClamAV scanner is running and
the "available" column is below about 2,000 MB, stop the old one first:

```bash
sudo systemctl stop clamav-daemon clamav-freshclam
```

Then start the new scanner. Loading the definitions takes up to two minutes:

```bash
sudo systemctl enable --now clamav14-daemon
for i in $(seq 1 30); do [ -S /run/clamav14/clamd.ctl ] && break; sleep 5; done
systemctl is-active clamav14-daemon
```

### 3. Test it

[EICAR](https://www.eicar.org/download-anti-malware-testfile/) is a harmless
test string that every scanner detects:

```bash
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt
/opt/clamav/bin/clamdscan --config-file=/opt/clamav/etc/clamd.conf --fdpass /tmp/eicar.txt
rm /tmp/eicar.txt
```

The expected result is `Eicar-Test-Signature FOUND`.

## Connect it to your mail filter

### amavis (including ISPConfig servers)

amavis finds clamd by its socket path, in `/etc/amavis/conf.d/15-av_scanners`
on Debian and Ubuntu. Point it at the new socket and restart amavis:

```bash
f=$(grep -rl '/var/run/clamav/clamd.ctl' /etc/amavis/conf.d/)
echo "$f"
sudo sed -i 's#/var/run/clamav/clamd.ctl#/run/clamav14/clamd.ctl#' $f
sudo systemctl restart amavis
```

amavis passes clamd file paths in its own temporary directory, so the `clamav`
user must be a member of the `amavis` group. Ubuntu's amavis setup normally
does this already; check with `id clamav`.

Send yourself a test mail and look for a `Passed CLEAN` line in
`/var/log/mail.log` without virus-scanner errors.

### Anything else that talks to clamd

Rspamd, Exim and other programs connect to clamd through its socket. Point
them at `/run/clamav14/clamd.ctl`.

### Retire the old scanner

Once the new one works, stop Ubuntu's old ClamAV from starting at boot. It
stays installed, so you can still go back:

```bash
sudo systemctl disable --now clamav-daemon clamav-freshclam
```

Removing Ubuntu's `clamav` packages completely is optional. Before doing so,
check that the `clamav` user still exists afterwards (`id clamav`), since this
package runs as that user.

## Configuration

Settings live in `/opt/clamav/etc/clamd.conf` and `freshclam.conf`. They are
package configuration files, so your edits survive upgrades: `apt` asks before
replacing a changed file. The packaged defaults differ from ClamAV's stock
settings in a few deliberate ways:

- `ConcurrentDatabaseReload no`: when definitions update, the scanner reloads
  them in place instead of loading a second copy first. That avoids
  temporarily doubling memory use, at the cost of a pause in scanning of a few
  seconds during each reload.
- Size limits suited to mail: 25 MB per file or stream, 100 MB scanned per
  message.
- Logging to syslog under the mail facility, so it appears in
  `/var/log/mail.log`.
- `freshclam` checks for new definitions twice a day and tells the scanner to
  reload.

After a change, restart the service:
`sudo systemctl restart clamav14-daemon`.

## Update

Virus definitions update on their own through `clamav14-freshclam`; nothing to
do.

When a new package release appears here, for example for a ClamAV security
fix, install it the same way as the first time. Running services keep working
until you restart them:

```bash
sudo apt install ./clamav-opt_<new version>_bionic_amd64.deb
sudo systemctl restart clamav14-daemon
```

To be notified, use **Watch → Custom → Releases** on this repository.

## Roll back

To an earlier build: install the `.deb` from that release with
`sudo apt install ./<file>.deb`.

Back to Ubuntu's old scanner (amavis example):

```bash
sudo systemctl enable --now clamav-daemon
f=$(grep -rl '/run/clamav14/clamd.ctl' /etc/amavis/conf.d/)
sudo sed -i 's#/run/clamav14/clamd.ctl#/var/run/clamav/clamd.ctl#' $f
sudo systemctl restart amavis
sudo systemctl disable --now clamav14-daemon clamav14-freshclam
```

Remove everything this package added: `sudo apt purge clamav-opt`. This also
deletes `/var/lib/clamav14`; it leaves the `clamav` user alone.

## How it is built

The workflow in `.github/workflows/build.yml` runs on GitHub's standard Ubuntu
machines and does the actual work inside an `ubuntu:18.04` container:

1. Installs the build dependencies from Ubuntu 18.04's archive.
2. Installs CMake 3.31.6 from Kitware and Rust 1.88.0 through rustup, since
   18.04's own versions are too old. ClamAV documents Rust 1.70 as the minimum
   for 1.4, but the crates vendored with 1.4.6 need 1.85 or newer.
3. Downloads the official source release from clamav.net and builds it with
   tests, examples, man pages and the milter switched off.
4. Packages the result as a `.deb`, working out the runtime dependencies from
   the libraries the programs actually link to.
5. Installs the package in a fresh `ubuntu:18.04` container and checks that
   every program starts and finds all its libraries.

On a push to `main`, the package, its `SHA256SUMS` and the ClamAV source
tarball it was built from are published as release
`v<CLAMAV_VERSION>-<PKG_REVISION>`, unless that release already exists.

| Path | What it is |
| --- | --- |
| `.github/workflows/build.yml` | Build, test and publish |
| `scripts/build.sh` | Runs in the 18.04 container: tools, download, compile |
| `scripts/package.sh` | Builds the `.deb` and works out its dependencies |
| `packaging/etc/` | The two configuration files |
| `packaging/systemd/` | The two service files |
| `packaging/debian/` | Install and removal scripts |

### Building a new version

1. Change `CLAMAV_VERSION` in `.github/workflows/build.yml` (and set
   `PKG_REVISION` back to `1`).
2. Push to `main`. The new release appears when the workflow finishes, after
   about 6 minutes.

To publish a rebuild of the same ClamAV version, raise `PKG_REVISION` instead.

### Building your own copy

Fork the repository; the workflow runs in your fork the same way and publishes
releases there. To build locally with Docker:

```bash
docker run --rm -e CLAMAV_VERSION=1.4.6 -e PKG_REVISION=1 \
  -v "$PWD:/src" -w /src ubuntu:18.04 bash scripts/build.sh
```

The package lands in `dist/`.

## Licences

ClamAV is licensed under the GNU General Public License, version 2. Each
release includes the exact ClamAV source tarball its package was built from.
