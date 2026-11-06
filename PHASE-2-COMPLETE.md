# Phase 2: Transactional Configuration — Complete

**Status:** Code complete, ready for testing on production  
**Commit:** `597a2f1` (Phase 2 complete + removed fw-ssh.cmd)

---

## What Changed

### 1. New: `/usr/local/sbin/mihomo-config-update`
Atomic configuration update coordinator (85 lines).

**Flow:**
```
staging → validate → backup → swap → restart → health-check → rollback
```

**Exit codes:**
- `0` — success (config active, service healthy)
- `1` — validation failed (old config unchanged)
- `2` — rollback executed (service restored to last-good config)

**Key improvements:**
- Validation uses `-d "$CONFIG_DIR"` for geodata/providers path
- Health check: `pgrep -qx mihomo` + TUN interface `tun_mihomo` up within 10s
- Automatic rollback on failure (restart failure, process died, TUN timeout)
- Explicit error handling (no `set -e` fragility)
- Preserves last-known-good config as `.last-good` backup

### 2. Patched: `/usr/local/etc/mihomo/sub/sub.sh`
Subscription updater now calls `mihomo-config-update` instead of manual validation + restart (lines 286-314).

**Before (48 lines):**
- Manual validation (`mihomo -t -f`)
- Timestamped backup (`config.yaml.bak.sub_20241106_123456`)
- Manual restart + manual rollback on failure (no health check)

**After (29 lines):**
- Calls `mihomo-config-update "$Conf_Dir/config.yaml"`
- Uses transactional flow (validation + health-check + automatic rollback)
- Fallback to legacy flow if `mihomo-config-update` not found (backward compat)

### 3. Updated: `build.sh`
- Added `need_file "src/usr/local/sbin/mihomo-config-update"` (line 59)
- Added `chmod 0755 "$STAGEDIR/usr/local/sbin/mihomo-config-update"` (line 155)

---

## Testing Instructions

### Prerequisites
1. **Backup current config:** `cp /usr/local/etc/mihomo/config.yaml /root/config-backup-phase2.yaml`
2. **Set SSH password:** `$env:FW_ROOT_PASSWORD = "your_password"` (PowerShell)
3. **Verify service running:** `service mihomo status`

### Test Scenario 1: Valid Subscription Update
```sh
# Trigger subscription update (will use mihomo-config-update automatically)
mihomo_sub

# Expected output:
# ...
# 应用配置（事务模式：staging → validate → swap → health-check）...
# 配置已应用，服务运行正常。
# ...

# Verify:
service mihomo status
ifconfig tun_mihomo
ls -lh /usr/local/etc/mihomo/config.yaml*
```

**Expected:**
- Service restarts successfully
- TUN interface `tun_mihomo` active
- `config.yaml.last-good` exists (backup of previous working config)

### Test Scenario 2: Intentional Validation Failure
```sh
# Create invalid config
echo "invalid: yaml: syntax error [[[" > /tmp/bad-config.yaml

# Try to apply it directly
/usr/local/sbin/mihomo-config-update /tmp/bad-config.yaml

# Expected output:
# error: validation failed
# (exit code 1)

# Verify service still running with old config
service mihomo status
ifconfig tun_mihomo

# Check logs
tail -20 /var/log/mihomo/mihomo.log
```

**Expected:**
- Validation fails (exit code 1)
- Service still running with old config (no restart attempted)
- No `.staging` file left behind

### Test Scenario 3: Rollback on Health Check Failure
```sh
# Create config with syntax OK but incompatible network settings
# (e.g., wrong DNS, unreachable proxies, or interface name mismatch)
cat > /tmp/unhealthy-config.yaml <<'EOF'
mixed-port: 7890
external-controller: 127.0.0.1:9090
log-level: info
tun:
  enable: true
  device: tun_wrong_name  # Wrong interface name, mihomo will start but TUN won't appear
  stack: system
  auto-route: true
proxies: []
proxy-groups: []
rules: []
EOF

# Apply it
/usr/local/sbin/mihomo-config-update /tmp/unhealthy-config.yaml

# Expected output after 10-12 seconds:
# error: health check timeout, rolled back
# (exit code 2)

# Verify rollback
service mihomo status
ifconfig tun_mihomo
cat /usr/local/etc/mihomo/config.yaml | grep device  # Should be "tun_mihomo" (old config)
```

**Expected:**
- Mihomo restarts with new config
- Health check waits 10s for `tun_wrong_name` (doesn't appear)
- Automatic rollback: restores `.last-good`, restarts service
- Service running with old config, `tun_mihomo` active

### Test Scenario 4: Fallback to Legacy Flow
```sh
# Temporarily rename mihomo-config-update
mv /usr/local/sbin/mihomo-config-update /usr/local/sbin/mihomo-config-update.bak

# Trigger subscription update
mihomo_sub

# Expected output:
# ...
# 警告：事务工具未找到，使用传统更新流程（无自动回滚）。
# 配置校验通过
# 重启完成（未使用事务模式）。
# ...

# Restore
mv /usr/local/sbin/mihomo-config-update.bak /usr/local/sbin/mihomo-config-update
```

**Expected:**
- Subscription update still works (backward compatibility)
- No automatic health check or rollback (legacy behavior)

---

## Known Limitations

1. **No WebGUI integration yet:** If WebGUI writes `config.yaml` directly (not via subscription), it bypasses transactional flow. Needs investigation in Phase 3.
2. **No multi-config rollback history:** Only keeps last-good backup (no timestamped history like subscription's `.bak.sub_*` files).
3. **Health check timeout fixed at 10s:** Not configurable (acceptable for typical mihomo startup).
4. **No DNS validation:** Phase 3 will add Unbound forwarding health checks.

---

## Next Steps (Phase 3)

1. **Investigate WebGUI config write path:** Check if `/usr/local/www/mihomo.php` or MVC controller writes config directly.
2. **Add `configd` integration:** OPNsense plugin config changes should trigger `mihomo-config-update`.
3. **DNS integration health check:** Verify Unbound forwarding to mihomo port 1053 after config swap.
4. **Update WebGUI to call `mihomo-config-update`:** If WebGUI writes config directly, patch it to use transactional flow.

---

## Rollback Plan

If Phase 2 breaks production:

```sh
# Restore Phase 1 code
cd /root/os-mihomo-v2
git checkout phase-1-safe-deinstall

# Rebuild package
sh src/os-mihomo/build.sh

# Upgrade
pkg install -y src/os-mihomo/dist/os-mihomo.pkg

# Restart service
service mihomo restart
```

Phase 1 data-loss fixes (`.sample` files) are preserved in Phase 2.
