# Phase 1: Safe Deinstall & Update

**Goal:** Prevent data loss during package upgrade and ensure clean uninstall behavior.

---

## Problem Statement

### Current Failure Mode
`+POST_DEINSTALL` contains this code:
```sh
echo "===> Scheduling mihomo residual directory cleanup"
(
    sleep 3
    rm -rf /usr/local/etc/mihomo
) >/dev/null 2>&1 &
```

**What breaks:**
1. User runs `pkg upgrade os-mihomo`
2. `pkg` deinstalls old version → `+POST_DEINSTALL` runs
3. Background job sleeps 3 seconds
4. New package installs → `+POST_INSTALL` runs
5. **Background cleanup wakes up and deletes active config**

Result: `/usr/local/etc/mihomo/config.yaml` vanishes, service can't start.

### Design Flaw
- Deferred cleanup in a background job races with package reinstall
- No mechanism to preserve user data (`config.yaml`, `subscription/`, `cache.db`, downloaded rule-sets)
- FreeBSD `@sample` directive not used for mutable config files

---

## Solution: FreeBSD @sample Pattern

### How @sample Works
1. Manifest declares: `@sample(root,wheel,0644) /usr/local/etc/mihomo/config.yaml.sample /usr/local/etc/mihomo/config.yaml`
2. **On first install:** if `config.yaml` doesn't exist, `pkg` copies `.sample` → `config.yaml`
3. **On upgrade:** `pkg` always overwrites `.sample`, but **leaves `config.yaml` untouched**
4. **On deinstall:** `pkg` deletes `.sample`, keeps `config.yaml` (user data preserved)

### Files to Mark as @sample
- `/usr/local/etc/mihomo/config.yaml` (user-modified config, **must survive upgrade**)
- `/usr/local/etc/mihomo/sub/env` (subscription credentials)
- `/usr/local/etc/rc.conf.d/mihomo` (service enable flag, if user-modified)

**Do NOT sample:**
- `/usr/local/bin/mihomo` (binary, always replaced)
- `/usr/local/etc/mihomo/dashboard/` (static assets, safe to overwrite)
- `/usr/local/etc/mihomo/sub/sub.sh` (script, not user-modified)

### Subscription Directory
User downloads rule-sets and subscription data into `/usr/local/etc/mihomo/subscription/` or `/usr/local/etc/mihomo/rules/`. These are **runtime-generated, not installed by pkg**.

**Strategy:**
- Do not list them in manifest (pkg won't create or delete them)
- Keep deinstall cleanup for `subscription/` and `cache.db`, but **only if service is disabled**
- Add safety check: skip cleanup if `config.yaml` references subscription data

---

## Implementation Tasks

### 1. Rewrite +POST_DEINSTALL
```sh
#!/bin/sh

echo "===> Refreshing OPNsense menu cache"
rm -f /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json
rm -f /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf
service configd restart >/dev/null 2>&1 || true

# Safety check: only clean runtime data if service is disabled AND config is gone
if [ ! -f /usr/local/etc/mihomo/config.yaml ]; then
    echo "===> Cleaning up mihomo runtime data (config removed by user)"
    rm -rf /usr/local/etc/mihomo/subscription
    rm -f /usr/local/etc/mihomo/cache.db
    # Preserve config.yaml.sample (pkg handles it)
else
    echo "===> Preserving mihomo config (uninstall only, user data kept)"
fi
```

**Rationale:**
- No deferred cleanup (no `sleep` in background)
- Only removes runtime data if user explicitly deleted config (intentional uninstall)
- Leaves `config.yaml` and `.sample` for `pkg` to manage

### 2. Update +MANIFEST.in
Change:
```diff
-/usr/local/etc/mihomo/config.yaml
+@sample(root,wheel,0644) /usr/local/etc/mihomo/config.yaml.sample /usr/local/etc/mihomo/config.yaml
```

Change:
```diff
-/usr/local/etc/mihomo/sub/env
+@sample(root,wheel,0600) /usr/local/etc/mihomo/sub/env.sample /usr/local/etc/mihomo/sub/env
```

**Source tree changes:**
- Rename `src/usr/local/etc/mihomo/config.yaml` → `config.yaml.sample`
- Rename `src/usr/local/etc/mihomo/sub/env` → `env.sample`
- Update `build.sh` if it references these paths

### 3. Verify +POST_INSTALL Behavior
Current script:
```sh
service mihomo status >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "===> Restarting mihomo service"
    service mihomo restart
fi
```

**Check:** Does it handle missing `config.yaml` gracefully? (If `.sample` wasn't copied on first install, service won't start.)

**Action:** Add safety check:
```sh
if [ ! -f /usr/local/etc/mihomo/config.yaml ]; then
    echo "===> First install: creating default config from sample"
    cp /usr/local/etc/mihomo/config.yaml.sample /usr/local/etc/mihomo/config.yaml
fi
```

### 4. Test Matrix

#### Scenario A: Fresh Install
1. `pkg install os-mihomo`
2. **Expected:** `.sample` → `config.yaml` created, service starts
3. **Verify:** `ls -l /usr/local/etc/mihomo/config.yaml*`, `service mihomo status`

#### Scenario B: Upgrade (User Has Modified Config)
1. User edits `/usr/local/etc/mihomo/config.yaml`
2. `pkg upgrade os-mihomo`
3. **Expected:** User's `config.yaml` untouched, `.sample` updated, service restarts with user config
4. **Verify:** `diff config.yaml config.yaml.sample` (should show user changes), `service mihomo status`

#### Scenario C: Uninstall
1. `pkg delete os-mihomo`
2. **Expected:** `config.yaml` preserved (for reinstall or user backup), runtime data removed
3. **Verify:** `ls -l /usr/local/etc/mihomo/` (config.yaml exists, subscription/ gone)

#### Scenario D: Uninstall + Manual Config Removal
1. `pkg delete os-mihomo`
2. `rm /usr/local/etc/mihomo/config.yaml`
3. `pkg install os-mihomo` (reinstall)
4. **Expected:** Fresh `.sample` → `config.yaml`, no stale data
5. **Verify:** `cat config.yaml` matches `.sample`

---

## Rollback Strategy

### If New Package Breaks
1. SSH to firewall: `fw-ssh.cmd "pkg delete -f os-mihomo"`
2. Extract old package from local backup: `cd backups/ && tar -xzf mihomo-backup-*.tar.gz`
3. Copy files back: `scp -r mihomo/usr/local/etc/mihomo root@100.64.13.1:/usr/local/etc/`
4. Reinstall old version: `pkg install os-mihomo-1.0.4.pkg` (from local cache)
5. Restart service: `service mihomo start`

### Git Rollback
```bash
git revert <phase-1-commit>
git push
```

---

## Acceptance Criteria

- [ ] `+POST_DEINSTALL` no longer uses background cleanup
- [ ] `config.yaml` declared as `@sample` in manifest
- [ ] `sub/env` declared as `@sample` (mode 0600 for secrets)
- [ ] Source tree renamed: `config.yaml` → `config.yaml.sample`, `env` → `env.sample`
- [ ] `build.sh` updated if it references old paths
- [ ] `+POST_INSTALL` ensures `config.yaml` exists (copies from `.sample` if missing)
- [ ] Test scenario B passes on VM or production (user config survives upgrade)
- [ ] Test scenario C passes (uninstall preserves config, cleans runtime data)
- [ ] Git commit tagged: `phase-1-safe-deinstall`

---

## Risks

### Risk: @sample Doesn't Work as Expected
**Mitigation:** Test on OPNsense 26.7 / FreeBSD 15.1 first (VM if available, else production with backup)

### Risk: User Config Incompatible with New Mihomo Version
**Mitigation:** Phase 3 (Config Validator) will detect breaking changes and prompt user before activation

### Risk: Subscription Cleanup Breaks Active Service
**Mitigation:** Safety check in `+POST_DEINSTALL` only runs if `config.yaml` is gone (intentional removal)

---

## Time Estimate
- Script changes: 1 hour
- Manifest changes: 30 minutes
- Source tree rename + build.sh: 30 minutes
- Testing (all scenarios): 2-3 hours
- **Total:** 4-5 hours (half-day)

---

## Next Phase
**Phase 2:** Transactional Configuration (atomic config staging, rollback on validation failure)
