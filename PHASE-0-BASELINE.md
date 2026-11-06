# Phase 0: Baseline Documentation

**Date:** 2026-11-06  
**Purpose:** Reproducible starting point before any modifications

---

## System Information

### Firewall Platform
- **Device:** OPNsense gateway at `100.64.13.1`
- **OPNsense version:** `26.7.2_2` (CORE_VERSION from `/usr/local/opnsense/version/core`)
- **FreeBSD version:** `15.1-RELEASE-p2`
- **Architecture:** amd64/x86_64

### Installed Package
- **Package name:** `os-mihomo`
- **Package version:** `1.0.4`
- **Installation date:** Thu Oct 29 17:03:18 2026 UTC
- **Mihomo binary:** `/usr/local/bin/mihomo` (58,216,582 bytes, dated Oct 1 07:30)
- **Mihomo version:** `Mihomo Meta 1.19.31-vincent freebsd amd64 with go1.27.1` (tags: `with_gvisor`)

### Repository State
- **Local fork commit:** `f181fdc Release os-mihomo 1.0.4 with rebuilt packages and repository metadata`
- **Upstream reference:** [Vincent-Loeng/clash-meta v1.19.31-vincent](https://github.com/Vincent-Loeng/clash-meta/releases/tag/v1.19.31-vincent)
- **Binary source recorded in:** `src/os-mihomo/packaging/freebsd/binary-source.json`
- **Git dirty status:** Multiple deleted files from old projects (os-ddclient-opnwall, os-mosdns, os-vpn-watcher) — cleanup completed, pending commit

---

## Current Configuration

### Service Status
- **Service name:** `mihomo`
- **Running:** Yes (TUN interface `tun_mihomo` active)
- **TUN interface:** `tun_mihomo`, flags `UP,BROADCAST,RUNNING`, MTU 1500, inet `198.18.0.0/30`
- **Process owner:** PID 65492

### Active YAML Config
**Path:** `/usr/local/etc/mihomo/config.yaml`

**Key platform settings (must survive subscription updates):**
```yaml
socks-port: 7891
bind-address: 127.0.0.1
allow-lan: false
find-process-mode: 'off'
mode: rule
log-level: info
ipv6: false
external-controller: 127.0.0.1:9090
secret: nT7ej3WghNj_v3iZdwp-kRpe

tun:
  enable: true
  stack: gvisor
  device: tun_mihomo
  mtu: 1500
  auto-route: true
  strict-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
    - tcp://any:53

dns:
  enable: true
  listen: 127.0.0.1:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  fake-ip-filter-mode: blacklist
  fake-ip-filter:
    - "rule-set:geosite-private"
    - "rule-set:geosite-ru"
    - "*.lan"
    - "+.local"
    # ... (full list preserved)
  default-nameserver:
    - 77.88.8.8
    - 195.208.4.1
  proxy-server-nameserver:
    - 9.9.9.9
    - 77.88.8.8
  direct-nameserver:
    - 77.88.8.8
    - 195.208.4.1
  nameserver:
    - https://9.9.9.9/dns-query#🌍 VPN
    - https://149.112.112.112/dns-query#🌍 VPN
  nameserver-policy:
    "rule-set:geosite-ru": [77.88.8.8, 195.208.4.1]
    "rule-set:geosite-private": [77.88.8.8, 195.208.4.1]
```

**Active node providers:**
- Mono (3 nodes: AMSTERDAM, USA 🇺🇸, AMSTERDAM RESERV)
- Sirius (13 nodes: various XHTTP, Reality, grpc)
- Cralix (2 nodes: AM Hysteria2, AM VLESS)

**Group structure:**
- `🌍 VPN` (selector: Mono, Fastest, Sirius, Cralix)
- `📡 Mono` (fallback)
- `⚡️ Fastest` (url-test)
- `📡 Sirius` (manual select)
- `📡 Cralix` (fallback)
- `🎮 Steam` (selector: VPN or DIRECT)

**Active rule providers:** telegram, ru-inline-banned, ru-inline, ru-app-list, torrent-*, geosite-ru, geoip-ru, xiaomi, blender, drweb, debian, canonical, python, geosite-steam, geosite-private, geoip-private

---

## Control Measurements

### DNS Resolution
**Router DNS config:**
- Unbound running on `:53` (multiple interfaces, PID 49135)
- Mihomo DNS listener: `127.0.0.1:1053` (TCP + UDP, PID 65492)
- Unbound integration: **mechanism unknown** — no explicit forward-zone found in `/usr/local/etc/unbound/unbound.conf`, may use OPNsense dynamic config or include files
- Expected flow: LAN queries → Unbound `:53` → (forwarding to mihomo `:1053`) → VPN or DIRECT resolvers

**LAN client DNS test (before any changes):**
```bash
# From LAN client using OPNsense as DNS:
nslookup google.com       # Expected: resolves (may be fake-IP 198.18.x.x via mihomo)
nslookup ya.ru            # Expected: real IP (geosite-ru bypasses fake-IP)
```

### Routing Test
**DIRECT route baseline:**
```bash
# From LAN client:
curl -s https://ifconfig.me    # Russian IP (bypassed via PF or DIRECT rules)
```

**Proxied route baseline:**
```bash
# Same client, force VPN path:
curl -s https://ifconfig.me    # Expected: VPN exit IP (Amsterdam/US/etc.)
```

### Management Access
- **WebGUI:** `https://100.64.13.1/` (HTTPS on LAN)
- **SSH:** `root@100.64.13.1` (password cached in `~/.agentssh/100.64.13.1.pw`)
- **Mihomo API:** `http://127.0.0.1:9090` (local only, secret required)
- **Mihomo dashboard:** `http://100.64.13.1:9090/ui` (if LAN-exposed via NAT/proxy)

---

## Package File Inventory

### Source Repository Structure
```
src/os-mihomo/
├── build.sh
├── Makefile
├── README.md
├── README.US.md
├── images/
│   ├── mihomo.png
│   └── mihomo.us.png
├── packaging/
│   └── freebsd/
│       ├── +MANIFEST.in
│       ├── +POST_INSTALL
│       ├── +POST_DEINSTALL
│       ├── +PRE_DEINSTALL
│       ├── binary-source.json
│       └── pkg-descr
└── src/
    ├── etc/
    │   └── rc.conf.d/
    └── usr/
        ├── bin/
        └── local/
            ├── bin/
            ├── etc/
            ├── opnsense/
            └── www/
```

### Installed Package Contents
(Extract via `pkg info -l os-mihomo` or inspect manifest)

**Critical files for Phase 1 (data loss risk):**
- `/usr/local/etc/mihomo/config.yaml` (user-modified, must survive update)
- `/usr/local/etc/mihomo/subscription/` (subscription cache, if present)
- `/usr/local/etc/mihomo/cache.db` (fake-IP cache)
- `/usr/local/etc/mihomo/rules/` (downloaded rule-sets)
- Any custom scripts or secrets in `/usr/local/etc/mihomo/`

---

## Backup Checklist

### OPNsense System Backup
- [ ] Full config backup via WebGUI: **System > Configuration > Backups**
- [ ] Download backup to: `backups/opnsense-config-YYYY-MM-DD.xml`
- [ ] Verify backup contains mihomo settings

### Mihomo Files Backup
```bash
# From firewall (via fw-ssh or AgentSSH):
tar -czf /tmp/mihomo-backup-$(date +%Y%m%d).tar.gz \
  /usr/local/etc/mihomo/ \
  /usr/local/bin/mihomo \
  /var/log/mihomo.log
```

- [ ] Archive saved to: `backups/mihomo-files-YYYY-MM-DD.tar.gz`
- [ ] Verify archive contains:
  - `config.yaml`
  - Subscription data (if any)
  - Rule-sets cache
  - Binary (for rollback)

### Git State
- [ ] Current branch: `main` (or feature branch name)
- [ ] Last commit: (git log HEAD -1 --oneline)
- [ ] No uncommitted changes (git status clean)
- [ ] Tag baseline: `git tag phase-0-baseline`

---

## Test YAML Configs

### Working Config
**File:** `src/os-mihomo/test_yaml/config_opnsense_from_working.yaml`  
**Status:** ✅ Currently running on OPNsense  
**Key features:**
- `find-process-mode: 'off'`
- DNS: DoH over VPN, Russian domains via direct nameservers
- TUN stack: `gvisor`
- Nodes: Mono, Sirius, Cralix

### Desired Config (Not Working)
**File:** `src/os-mihomo/test_yaml/Configuration_AM_Cralix_DoH_Process_OFF.yaml`  
**Status:** ❌ Fails to work on OPNsense  
**Differences from working config:**
- `mixed-port: 7890` (vs. `socks-port: 7891`)
- TUN stack: `mixed` (vs. `gvisor`)
- DNS listen: `127.0.0.1:6868` (vs. `127.0.0.1:1053`)
- DNS mode: `redir-host` (vs. `fake-ip`)
- Bootstrap: DoH by IP (`https://1.1.1.1/dns-query`)
- All nameservers route through `🌍 VPN` (including DIRECT)

**TODO:** Validate desired config with installed kernel before switching.

---

## Known Constraints

### Platform Requirements (from README)
1. Only x86_64/amd64 supported
2. TUN interface name `tun_mihomo` is fixed (firewall rules depend on it)
3. OPNsense 26.7.5 / FreeBSD 15.1 tested
4. Official Mihomo v1.19.32 fails (`create NetworkUpdateMonitor: invalid argument`)
5. Vincent-Loeng adapted kernel required

### DNS Integration
- Unbound forwards queries to mihomo port 1053
- `geosite:cn` (Russian domains) excluded from fake-IP to return real IPs
- LAN clients using OPNsense as DNS are intercepted by mihomo

### Firewall Rules
- Russian IP bypass via PF (before mihomo)
- Telegram must not leak to WAN bypass
- Fake-IP traffic must route through TUN, not bypass

---

## Rollback Procedure

### If Package Install Breaks System
1. Boot to single-user mode or recovery shell
2. Restore from backup:
   ```bash
   pkg delete -f os-mihomo
   tar -xzf /path/to/mihomo-backup.tar.gz -C /
   ```
3. Restart service: `service mihomo start`

### If Config Change Breaks Connectivity
1. SSH to firewall: `fw-ssh.cmd "service mihomo stop"`
2. Restore last-known-good config:
   ```bash
   cp /usr/local/etc/mihomo/config.yaml.backup \
      /usr/local/etc/mihomo/config.yaml
   ```
3. Restart: `service mihomo start`
4. Verify TUN and DNS: `ifconfig tun_mihomo; sockstat -4 -l | grep 1053`

### VM Testing
- **Recommended:** Test Phase 1-4 changes on clean OPNsense VM before applying to production firewall
- **VM setup:** (document if VM exists, or note "production-only testing")

---

## Acceptance Criteria for Phase 0

- [x] System versions documented
- [x] Package metadata recorded (version, install date, binary version)
- [x] Active config captured (YAML platform settings, node providers, groups, rules)
- [x] Service status verified (TUN interface up, listeners active)
- [x] DNS/routing flow documented (Unbound → mihomo `:1053`, mechanism TBD)
- [x] Two test YAML configs inspected and differences documented
- [ ] **Pending:** Full system backup via OPNsense WebGUI
- [ ] **Pending:** Mihomo files backup tarball
- [ ] **Pending:** Control measurements (LAN client DNS test, routing test)
- [ ] **Pending:** Git baseline tag

**Status:** Core documentation complete. Backups and control tests require WebGUI access or stable SSH — deferred until Phase 1 prep.

**Next:** Phase 1 (Safe Deinstall & Update) — fix data loss during package upgrade.

---

## Notes
- SSH exec shell on OPNsense 26.7 is restricted; use `fw-ssh.cmd` wrapper
- `configctl` commands fail with "Action not allowed"; use `pfctl`, `pluginctl`, direct scripts
- WebGUI access via LAN requires HTTPS (self-signed cert)
- AgentSSH available for policy-audited remote execution

