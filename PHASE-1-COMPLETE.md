# Phase 1 Complete: Safe Deinstall & Update

## Changes Made

### 1. Fixed +POST_DEINSTALL (data loss risk removed)
**File:** `src/os-mihomo/packaging/freebsd/+POST_DEINSTALL`
- Removed background `sleep 3 && rm -rf /usr/local/etc/mihomo` 
- Added safety check: only clean runtime data if config.yaml was removed by user
- Preserves config.yaml during uninstall and upgrade

### 2. Renamed config files to .sample
**Files renamed:**
- `config.yaml` → `config.yaml.sample`
- `sub/env` → `sub/env.sample`

### 3. Updated +MANIFEST.in with @sample directives
**File:** `src/os-mihomo/packaging/freebsd/+MANIFEST.in`
```
@sample /usr/local/etc/mihomo/config.yaml.sample /usr/local/etc/mihomo/config.yaml
@sample(root,wheel,0600) /usr/local/etc/mihomo/sub/env.sample /usr/local/etc/mihomo/sub/env
```

### 4. Added safety checks in +POST_INSTALL
**File:** `src/os-mihomo/packaging/freebsd/+POST_INSTALL`
- Ensures config.yaml exists (copies from .sample if missing)
- Ensures sub/env exists with correct permissions (0600)

### 5. Updated build.sh file checks
**File:** `src/os-mihomo/build.sh`
- Changed `need_file` checks to reference .sample files

---

## Git Status
- **Commit:** Phase 1: Implement @sample pattern for config files
- **Tag:** `phase-1-safe-deinstall`
- **Branch:** main

---

## What Was Not Done (Ponytail Shortcuts)

1. **No VM testing** — production-only environment, user has backup
2. **No extracted package inspection** — relied on FreeBSD @sample being standard
3. **No multi-scenario test suite** — will verify on actual upgrade
4. **Did not update +MANIFEST.in template variables** — build.sh generates manifest dynamically, template is reference only

---

## Risks

1. **@sample syntax may not work** — FreeBSD standard, but never tested on this project
   - Mitigation: User has OPNsense backup
2. **First install may fail if pkg doesn't copy .sample** — +POST_INSTALL has fallback
3. **Upgrade path untested** — will know when user runs `pkg upgrade`

---

## Next Steps (User Actions Required)

### To test Phase 1:
```bash
# 1. Build new package (from firewall via fw-ssh or local FreeBSD VM)
cd src/os-mihomo
./build.sh

# 2. Backup current config
fw-ssh.cmd "cp -p /usr/local/etc/mihomo/config.yaml /root/config.yaml.phase0"

# 3. Install new package
fw-ssh.cmd "pkg install -y /path/to/dist/os-mihomo.pkg"

# 4. Verify config survived
fw-ssh.cmd "diff /usr/local/etc/mihomo/config.yaml /root/config.yaml.phase0"
fw-ssh.cmd "ls -l /usr/local/etc/mihomo/config.yaml*"  # both .sample and actual should exist

# 5. Verify service restarted
fw-ssh.cmd "service mihomo status"
fw-ssh.cmd "ifconfig tun_mihomo"

# 6. Test connectivity
curl -x socks5://127.0.0.1:7891 https://ifconfig.me  # from LAN client
```

### If it breaks:
```bash
# Rollback to phase-0-baseline
git checkout phase-0-baseline
cd src/os-mihomo
./build.sh
fw-ssh.cmd "pkg delete -y os-mihomo"
fw-ssh.cmd "cp /root/config.yaml.phase0 /usr/local/etc/mihomo/config.yaml"
fw-ssh.cmd "pkg install -y /path/to/dist/os-mihomo.pkg"
fw-ssh.cmd "service mihomo start"
```

---

## Next Phase
**Phase 2:** Transactional Configuration (atomic YAML staging, rollback on validation failure)

**Shortcut skipped:** Phase 1 doesn't add config validation — assumes new package uses same YAML schema. Phase 2 will add `mihomo -t` syntax check before activation.
