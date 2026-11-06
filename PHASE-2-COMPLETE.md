# Phase 2: Transactional Configuration — COMPLETE

## Scope
- Atomic config update with staging → validation → swap → health-check → rollback flow.
- `.last-good` preserved across rollbacks and committed only after health-check passes.
- Security fixes: TOCTOU in backup, curl argument injection safety.

## Deliverables
- `mihomo-config-update` script with exit codes 0/1/2 (success/validation-fail/rollback).
- `sub.sh` patched to call `mihomo-config-update` with fallback to legacy direct-write path.
- `build.sh` includes `mihomo-config-update` in package.

## Test Results (2026-11-06)

### Test Scenario 1: Valid Update
```
/usr/local/sbin/mihomo-config-update /tmp/valid-test.yaml
exit 0 (expect 0)
-rw-r--r--  1 root wheel 5748 Nov  6 10:57 /usr/local/etc/mihomo/config.yaml.last-good
```
**PASS:** Config staged, validated, swapped, restarted, health-check passed, `.last-good` committed.

### Test Scenario 2: Validation Failure
```
/usr/local/sbin/mihomo-config-update /tmp/invalid.yaml
exit 1 (expect 1)
error: validation failed 1
diff -q /tmp/valid.yaml /usr/local/etc/mihomo/config.yaml => Files are identical
```
**PASS:** Validation failed, staging cleaned up, active config untouched, service running.

### Test Scenario 3: Health-Check Rollback
```
/usr/local/sbin/mihomo-config-update /tmp/bad-tun.yaml
exit 2 (expect 2)
error: health check timeout, rolled back 2
-rw-r--r--  1 root wheel 5748 Nov  6 10:57 /usr/local/etc/mihomo/config.yaml.last-good
diff -q /usr/local/etc/mihomo/config.yaml.last-good /usr/local/etc/mihomo/config.yaml => Files are identical
mihomo is running: daemon pid 37687, mihomo pid 38349.
tun_mihomo: flags=1008043<UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1500
```
**PASS:** Bad config activated, restarted, health-check failed (TUN did not come up), `.last-good` restored via `cp`, service restarted, TUN up.

### Rollback Logic Evolution
| Commit | Behavior | Issue |
|--------|----------|-------|
| de1b83a | `cp` → active, then `mv` → `.last-good` before restart | `.last-good` destroyed on rollback |
| 374b098 | `cp` → `.last-good` in rollback paths | `.last-good` committed before health-check |
| b5cb1a4 | Commit `.last-good` only after health-check passes | ✓ Correct |

## Security Fixes (commit de1b83a)
- **TOCTOU in backup (PHP):** `copy()` now inside `flock()` critical section.
- **curl argument injection:** Subscription URL sanitized, `--` separator before URL.

## Integration Points
- **Unbound DNS forwarding:** Pre-configured via `setup_unbound.php` (installed in `+POST_INSTALL`).
  - `/var/unbound/etc/dot.conf` contains `forward-zone: name: "." forward-addr: 127.0.0.1@1053`.
  - All DNS queries routed through Mihomo port 1053 (except internal `*.neps.arpa` zones).

## Known Shortcut
**WebGUI save bypasses `mihomo-config-update`.**  
- `mihomo.php` saveConfig() writes directly to `config.yaml` via atomic `rename()`.
- No health-check, no `.last-good` update.
- **Risk:** Subscription updater rollback restores stale `.last-good` after manual WebGUI edit.
- **Mitigation:** Manual save is trusted user operation; subscription updates are protected.
- **Upgrade path:** Add "Test & Commit" button in WebGUI calling `mihomo-config-update /usr/local/etc/mihomo/config.yaml` to revalidate and commit active config as `.last-good`.

## Next Steps
- Phase 3: Layered diagnostics (connection health, proxy chain, upstream DNS).
- Phase 4: Package metadata (correct dependencies, deinstall preservation).
- Phase 5: WebGUI workflow hardening (Test & Commit button).
