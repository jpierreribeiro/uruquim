# VPS verification gate

This is the remote repetition of the mandatory local pre-push gate. It does
not use GitHub Actions and does not receive GitHub credentials: the Uruquim
repository is public and fetched read-only.

The verifier runs as the unprivileged `uruquim-ci` user. Every five minutes it
fetches `main`, archives a new commit into a fresh temporary
directory, runs `build/check.sh`, and records an atomic status plus the latest
log under `/var/lib/uruquim-ci`.

Installation outline for Ubuntu/Debian x86_64:

1. Install host prerequisites: `git`, `curl`, `tar`, and `clang`.
2. Create system user `uruquim-ci` and writable directories
   `/opt/uruquim-ci` and `/var/lib/uruquim-ci`.
3. Copy `run.sh` to `/opt/uruquim-ci/run.sh` and make it executable.
4. From a trusted checkout, run `install-odin.sh` with permission to create
   `/opt/uruquim-odin`; it verifies the pinned SHA-256 and compiler commit.
5. Install the service and timer in `/etc/systemd/system/`.
6. Run `systemctl daemon-reload` and enable `uruquim-ci.timer`.

Optional `/etc/uruquim-ci.env` overrides:

```text
URUQUIM_CI_BRANCH=main
URUQUIM_CI_REPO_URL=https://github.com/jpierreribeiro/uruquim.git
URUQUIM_ODIN_BIN=/opt/uruquim-odin/odin
```

Check the last result with `/opt/uruquim-ci/status.sh` or inspect
`journalctl -u uruquim-ci.service`. No HTTP port, dashboard, token, or secret
is required.
