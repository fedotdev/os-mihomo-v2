#!/bin/sh
echo "=== Unbound config check ==="
grep -E "(forward|mihomo|1053)" /usr/local/etc/unbound/unbound.conf || echo "No forward to 1053 found"
echo ""
echo "=== var/unbound check ==="
ls -la /var/unbound/ 2>/dev/null || echo "/var/unbound not found"
echo ""
echo "=== Include files ==="
grep "^include:" /usr/local/etc/unbound/unbound.conf
