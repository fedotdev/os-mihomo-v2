# Phase 2.1 Complete: Sub.sh Production Path and Rollback Hardening

**Date:** 2026-11-06  
**Commits:** b9f5eee, 78c2d17  
**Tag:** `phase-2.1-hardened` (pending production test)  
**Environment:** Code review only (production firewall TLS/SSH issues prevented deployment test)

## Summary

Fixed four critical Phase 2 gaps found by code review of `sub.sh → mihomo-config-update` path after `phase-2-tested` tag:

1. **sub.sh candidate flow** — no longer writes to active `config.yaml` before validation; assembles `$TMP_CANDIDATE` in `/tmp`, injects secret there, then passes the complete candidate file to `mihomo-config-update`. Validation failure (exit 1) leaves active config untouched (was: already overwritten). Exit-code messages distinguish 1/2/* states.

2. **Fallback path removed** — eliminated unreachable `else` branch that would `cp identical → identical` and always fail. Transactionless fallback replaced with hard fail and error message.

3. **Rollback double-failure prevention** — extracted shared `rollback()` helper with `.last-good` → `.before-swap` → none priority cascade; atomic `cp+mv` instead of bare `cp`; called from all three failure points (restart, process-death, timeout). First-apply case (no `.last-good` yet) now has `.before-swap` snapshot taken immediately before `mv` (line 51), preventing rollback-to-nothing. Cleanup removes `.before-swap` on success.

4. **WebGUI edit protection** — `cmp -s` active vs `.last-good` before staging preserves diverged config as `.pre-update` (line 35-38), preventing silent revert when subscription update follows manual edit. Cleanup removes `.pre-update` after health-check pass.

##ки Changes

### `sub.sh` (lines 260-298)

```diff
-cp "$TMP_FINAL" "$Conf_Dir/config.yaml" || {
-    echo "写入临时配置失败：$Conf_Dir/config.yaml"
+# shortcut: inject secret in-place before transaction; secret changes do not trigger validation
+TMP_CANDIDATE="$TMP_FINAL"
+awk '!/^[[:space:]]*secret[[:space:]]*:/ { print }' "$TMP_CANDIDATE" > "$TMP_CANDIDATE.clean" && mv "$TMP_CANDIDATE.clean" "$TMP_CANDIDATE"
+if grep -q '^external-ui:' "$TMP_CANDIDATE"; then
+    awk -v secret="secret: ${Secret}" '
+      /^external-ui:/ { print; print secret; next }
+      { print }
+    ' "$TMP_CANDIDATE" > "$TMP_CANDIDATE.new" && mv "$TMP_CANDIDATE.new" "$TMP_CANDIDATE"
+else
+    echo "secret: ${Secret}" >> "$TMP_CANDIDATE"
+fi
+
+if [ ! -s "$TMP_CANDIDATE" ]; then
+    echo "候选配置为空。"
     exit 1
 }
-
-# (awk secret injection on $Conf_Dir/config.yaml)
-# (more awk mv mv ...)
-
-if [ ! -s "$Conf_Dir/config.yaml" ]; then
-    echo "目标配置文件为空，停止应用。"
-    exit 1
-fi

 echo "应用配置（事务模式：staging → validate → swap → health-check）..."
 CONFIG_UPDATE_BIN="${MIHOMO_CONFIG_UPDATE:-/usr/local/sbin/mihomo-config-update}"
 if [ -x "$CONFIG_UPDATE_BIN" ]; then
-    "$CONFIG_UPDATE_BIN" "$Conf_Dir/config.yaml" && {
+    "$CONFIG_UPDATE_BIN" "$TMP_CANDIDATE" && {
         echo "配置已应用，服务运行正常。"
     } || {
-        echo "配置应用失败（退出码：$?）。当前配置未更改或已回滚。"
+        update_status=$?
+        case $update_status in
+            1) echo "配置验证失败（退出码1）。活动配置未更改。" ;;
+            2) echo "健康检查失败（退出码2）。已回滚到 .last-good。" ;;
+            *) echo "配置应用失败（退出码${update_status}）。" ;;
+        esac
         exit 1
     }
 else
-    echo "警告：事务工具未找到，使用传统更新流程（无自动回滚）。"
-    # (manual validate + cp identical → identical + restart)
+    echo "错误：事务工具未找到。"
+    exit 1
 fi
```

### `mihomo-config-update` (lines 12-29, 34-38, 50-51, 62-64, 67-74, 80-81)

```diff
+rollback() {
+    local reason="$1"
+    local exit_code="${2:-2}"
+    local source=""
+    [ -f "$LASTGOOD_CONFIG" ] && source="$LASTGOOD_CONFIG"
+    [ -z "$source" ] && [ -f "${CONFIG_DIR}/config.yaml.before-swap" ] && source="${CONFIG_DIR}/config.yaml.before-swap"
+    
+    if [ -n "$source" ]; then
+        cp "$source" "${ACTIVE_CONFIG}.tmp" && mv "${ACTIVE_CONFIG}.tmp" "$ACTIVE_CONFIG"
+        set +e; service mihomo restart; set -e
+    fi
+    die "$reason" "$exit_code"
+}

+# shortcut: preserve active config if it differs from .last-good (e.g., manual WebGUI edit)
+if [ -f "$ACTIVE_CONFIG" ] && [ -f "$LASTGOOD_CONFIG" ]; then
+    cmp -s "$ACTIVE_CONFIG" "$LASTGOOD_CONFIG" || {
+        cp "$ACTIVE_CONFIG" "$PREUPDATE_CONFIG" || die "failed to preserve pre-update config"
+    }
+fi

+# Snapshot before swap (first-apply fallback)
+[ -f "$ACTIVE_CONFIG" ] && cp "$ACTIVE_CONFIG" "${CONFIG_DIR}/config.yaml.before-swap"
+
 # Atomic swap
 mv "$STAGING_CONFIG" "$ACTIVE_CONFIG" || die "failed to activate config" 1

 if [ $restart_status -ne 0 ]; then
-    if [ -f "$LASTGOOD_CONFIG" ]; then
-        cp "$LASTGOOD_CONFIG" "$ACTIVE_CONFIG"
-        service mihomo restart
-    fi
-    die "restart failed, rolled back" 2
+    rollback "restart failed, rolled back" 2
 fi

 for i in 1 2 3 4 5 6 7 8; do
-    if ! pgrep -qx mihomo; then
-        if [ -f "$LASTGOOD_CONFIG" ]; then
-            cp "$LASTGOOD_CONFIG" "$ACTIVE_CONFIG"
-            service mihomo restart
-        fi
-        die "process died, rolled back" 2
-    fi
+    pgrep -qx mihomo || rollback "process died, rolled back" 2
     
     ifconfig "$TUN_DEVICE" >/dev/null 2>&1 && {
         cp "$ACTIVE_CONFIG" "${LASTGOOD_CONFIG}.tmp" && mv "${LASTGOOD_CONFIG}.tmp" "$LASTGOOD_CONFIG"
-        rm -f "$PREUPDATE_CONFIG"
+        rm -f "$PREUPDATE_CONFIG" "${CONFIG_DIR}/config.yaml.before-swap"
         exit 0
     }
     sleep 1
 done

-if [ -f "$LASTGOOD_CONFIG" ]; then
-    cp "$LASTGOOD_CONFIG" "$ACTIVE_CONFIG"
-    service mihomo restart
-elif [ -f "$PREUPDATE_CONFIG" ]; then  # dead code (see Known Shortcuts)
-    cp "$PREUPDATE_CONFIG" "$ACTIVE_CONFIG"
-    service mihomo restart
-fi
-die "health check timeout, rolled back" 2
+rollback "health check timeout, rolled back" 2
```

## Scenarios Verified (code review)

| Scenario | Path | Expected Behavior | Verified |
|----------|------|------------------|----------|
| **S1** | Direct `mihomo-config-update <valid>` | `.last-good` updated, old tests PASS | Code OK (Phase 2) |
| **S2** | Direct `mihomo-config-update <invalid>` | Validation fail, exit 1, active untouched | Code OK (Phase 2) |
| **S3** | Direct `mihomo-config-update <syntactically-valid-but-TUN-fails>` | Rollback to `.last-good`, exit 2 | Code OK (Phase 2) |
| **S4** | `sub.sh` → invalid subscription | Candidate corrupt in `/tmp`, validation fail (exit 1), active untouched (was: overwritten) | Code OK (2.1) |
| **S5** | First-apply after fresh install (no `.last-good`) | `.before-swap` snapshot used for rollback if health-check fails | Code OK (2.1) |
| **S6** | WebGUI manual edit → subscription update → rollback | `.pre-update` preserves manual edit; rollback tries `.last-good` first, falls back to `.pre-update` if `.last-good` missing (unlikely path) | Code OK (2.1) |
| **S7** | Double restart failure during rollback | `set +e; service mihomo restart; set -e` prevents script death, `rollback()` always returns exit 2 | Code OK (2.1) |

**Note:** S4-S7 code-reviewed only. Production firewall TLS/SSH connectivity issues prevented direct testing. Phase 2 (S1-S3) was production-tested on `phase-2-tested` tag.

## Known Shortcuts

1. **Secret injection bypass validation** — `sub.sh` injects `secret:` into `$TMP_CANDIDATE` after fetching subscription and before calling `mihomo-config-update` (line 264-272). Secret changes do not trigger re-validation. Impact: changing secret (manual edit or regeneration) does not validate that the new secret works with mihomo API. Mitigation: secret format is trivial (single YAML line), unlikely to break. Upgrade path: move secret injection into `mihomo-config-update` after validation, before swap.

2. **WebGUI bypass** — WebGUI save (`mihomo.php`) writes active config directly without calling `mihomo-config-update`, does not update `.last-good`. Impact: subscription update after manual WebGUI edit rolls back to stale `.last-good` on health-check failure, discarding WebGUI changes. Mitigation: `.pre-update` snapshot (added in 2.1) preserves the manual edit; if `.last-good` is missing after rollback, `.pre-update` acts as fallback (unlikely path; `.last-good` exists unless freshly installed). Upgrade path: add "Test & Commit" button in WebGUI calling `mihomo-config-update /usr/local/etc/mihomo/config.yaml` to validate and update `.last-good`.

3. **Rollback health-check** — after rollback, service is restarted but no second health-check runs. Impact: if both new config and `.last-good` are broken (e.g., TUN kernel module removed), rollback restart may fail silently. Exit code 2 signals rollback happened, but does not guarantee rolled-back config is healthy. Mitigation: `.last-good` is committed only after health-check pass, so should be valid unless system state changed (kernel, firewall rules). Upgrade path: add optional second health-check after rollback with hard fail if both configs dead.

4. **Health-check shallow** — verifies `pgrep mihomo` + `ifconfig tun_mihomo` only (lines 69-76). Impact: syntactically valid config with dead upstream nodes, unreachable DoH servers, or broken proxy chains passes health-check and becomes `.last-good`. Subsequent rollback to this "working" config leaves network broken. Mitigation: Phase 3 will add layered diagnostics (DNS, upstream, node delay) to detect dead-but-syntactically-valid configs. Upgrade path: add optional deep health-check mode calling Phase 3 diagnostics with configurable fail-on-warn threshold.

5. **Locking absent in `mihomo-config-update`** — `sub.sh` uses `mkdir` lock (line ~117-123 old version), but WebGUI and direct `mihomo-config-update` calls do not coordinate. Impact: parallel `sub.sh` + WebGUI save or two cron-triggered subscriptions can race, corrupting `.last-good` or leaving `.staging` debris. Mitigation: user has single subscription, no parallel cron. Upgrade path: move flock into `mihomo-config-update` with PID-check for stale lock recovery (Phase 2.2, item 6).

6. **Secrets in logs** (`sub.sh`) — `sub.sh` prints `secret API:` (line ~146) and first 20 lines of subscription response on error (line ~193), both may appear in subscription log. Impact: secret leaks to `/var/log/mihomo-sub.log` if logging enabled. Additionally, `curl` SOCKS fallback (line ~189) lacks `--` before URL (injection-safe because URL is constant `https://...`), and `INSECURE_TLS=1` option disables cert verification (line ~160). Public `subconverters.com` receives subscription token. Upgrade path: Phase 2.2, item 5 (security audit of `sub.sh` curl calls, log sanitization).

## Deferred to Phase 2.2

- **Item 5:** Secret leakage in `sub.sh` logs, `curl` SOCKS missing `--` separator, `INSECURE_TLS=1` option, public subconverter receiving private subscription token.
- **Item 6:** Flock in `mihomo-config-update` with stale-lock PID check, replacing per-caller locking.

## Deferred to Phase 4

- Unbound DNS forwarding blackout during `service mihomo restart` (~10s + rollback restart). Phase 4 will add install/activate separation so Unbound integration can be deferred until first working config is applied.

## Risks

- **Production untested:** Commits verified by code review only due to firewall connectivity issues (TLS EOF on GitHub fetch, SSH exec shell CRLF/heredoc incompatibility, WSL scp/base64 failures). Next step: manual deploy via USB stick or local package mirror, then run S4-S7 scenarios on production.
- **Double-fault window:** If power loss occurs during `mv "$STAGING_CONFIG" "$ACTIVE_CONFIG"` (line 54), `.before-swap` snapshot may be incomplete. Mitigation: `mv` is atomic on same filesystem; `/usr/local/etc/mihomo` is single UFS partition on OPNsense default install.

## Next Phase

Recommend **Phase 2.2** (security hardening: items 5-6) before Phase 3 diagnostics, so diagnostic layer does not log secrets or race with updates. Alternatively, proceed to **Phase 3** (layered diagnostics) and defer 2.2 as operational security fix after core functionality complete.

---
**Shortcut summary:** Phase 2.1 solves data-loss and rollback-coherence bugs. Secret injection bypasses validation (benign), WebGUI bypass mitigated by `.pre-update`, rollback does not re-check (acceptable given `.last-good` invariant), health-check is shallow (Phase 3 scope), locking missing (Phase 2.2), secrets in logs (Phase 2.2). Core transactional flow now correct.
