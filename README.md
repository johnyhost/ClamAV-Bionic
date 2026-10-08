# ClamAV-Bionic

Current ClamAV for an Ubuntu 18.04 mail server.

Ubuntu 18.04 ships ClamAV 0.103, which reached end of life on 14 September 2024.
ClamAV's download servers now refuse it, so its virus definitions stop updating.
ClamAV's own ready-made 1.4 packages need glibc 2.28 or newer, and 18.04 has
2.27. This repo builds ClamAV from the official source inside an `ubuntu:18.04`
container on GitHub's machines, so the result fits an 18.04 server exactly.

## What the package does

- Package name `clamav-opt`, installed under `/opt/clamav`.
- Database in `/var/lib/clamav14`, socket at `/run/clamav14/clamd.ctl`.
- Two services, `clamav14-freshclam` and `clamav14-daemon`, installed but
  **not enabled or started**. Turning them on is a deliberate manual step.
- It does not replace, remove or reconfigure Ubuntu's own `clamav` packages.
  Both can be installed side by side, which is what makes rollback simple.
- Reuses the existing `clamav` system user, or creates it if it is missing.

| Path | What it is |
| --- | --- |
| `.github/workflows/build.yml` | Builds, tests and (on a tag) publishes the package |
| `scripts/build.sh` | Runs in the 18.04 container: build tools, compile, stage |
| `scripts/package.sh` | Turns the staged files into the `.deb`, works out dependencies |
| `packaging/etc/` | `clamd.conf` and `freshclam.conf` installed in `/opt/clamav/etc` |
| `packaging/systemd/` | The two service files |
| `packaging/debian/` | Install and removal scripts |

## Builds and releases

- Every push to `main` builds the package, installs it in a clean 18.04
  container, checks that every binary finds its libraries, and keeps the
  `.deb` as a workflow artifact.
- Pushing a tag `v<clamav version>-<package revision>`, for example `v1.4.6-1`,
  does the same and publishes the `.deb` and `SHA256SUMS` as a release.
- To build a new ClamAV patch release, change `CLAMAV_VERSION` in the workflow,
  push, and tag it.

Build tools, pinned for reproducible builds: CMake 3.31.6 from Kitware and Rust
1.88.0 from rustup. ClamAV documents Rust 1.70 as the minimum for 1.4.x, but
the 1.4.6 source vendors crates that use Rust edition 2024, which needs 1.85 or
newer.

## On the server

Each step below can be undone; the last section shows how.

### 1. Install the package (nothing starts yet)

```bash
cd /tmp && wget -q https://github.com/johnyhost/ClamAV-Bionic/releases/download/v1.4.6-1/clamav-opt_1.4.6-1~bionic_amd64.deb && apt install -y ./clamav-opt_1.4.6-1~bionic_amd64.deb && /opt/clamav/bin/clamscan --version
```

### 2. Download current definitions

```bash
systemctl enable --now clamav14-freshclam && sleep 120 && ls -l /var/lib/clamav14
```

### 3. Check memory, then start the new scanner

The new scanner needs about 1.5 GB of memory with current definitions. If
`free -m` shows less than 2,000 MB available, stop the old scanner first
(`systemctl stop clamav-daemon`); mail is held and retried meanwhile, not lost.

```bash
free -m && systemctl enable --now clamav14-daemon && sleep 90 && systemctl is-active clamav14-daemon
```

### 4. Test it with the harmless EICAR test string

```bash
printf 'X5O!P%%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt && /opt/clamav/bin/clamdscan --config-file=/opt/clamav/etc/clamd.conf --fdpass /tmp/eicar.txt; rm -f /tmp/eicar.txt
```

The expected result is `Eicar-Signature FOUND` (or a similar name).

### 5. Switch the mail filter to the new scanner

amavis finds clamd through a socket path in its scanner list. Change that path
from Ubuntu's socket to the new one, then restart amavis:

```bash
f=$(grep -rl '/var/run/clamav/clamd.ctl' /etc/amavis/conf.d/) && echo "$f" && sed -i 's#/var/run/clamav/clamd.ctl#/run/clamav14/clamd.ctl#' $f && systemctl restart amavis && sleep 5 && systemctl is-active amavis
```

Send yourself a test mail and check `/var/log/mail.log` for a `Passed CLEAN`
line without virus-scanner errors.

### 6. Retire Ubuntu's old scanner

```bash
systemctl disable --now clamav-daemon clamav-freshclam
```

## Rollback

Back to Ubuntu's old scanner at any point:

```bash
systemctl enable --now clamav-daemon && f=$(grep -rl '/run/clamav14/clamd.ctl' /etc/amavis/conf.d/) && sed -i 's#/run/clamav14/clamd.ctl#/var/run/clamav/clamd.ctl#' $f && systemctl restart amavis && systemctl disable --now clamav14-daemon clamav14-freshclam
```

Back to an earlier build: install the `.deb` from the earlier release with
`apt install ./<file>.deb`.

Remove everything this package added: `apt purge clamav-opt`.
