# OPNsense Config Adaptation

## Автоматическая нормализация

Плагин автоматически адаптирует `config.yaml` при старте службы:

| Параметр | Требование OPNsense | Ваша настройка | Что происходит |
|----------|---------------------|-----------------|----------------|
| `dns.listen` | `127.0.0.1:1053` | Любой порт | Перезаписывается на 1053 (Unbound forward) |
| `tun.stack` | `gvisor` или `system` | `mixed`, `lwip` | Перезаписывается на `gvisor` (FreeBSD не поддерживает `mixed`) |
| `tun.device` | `tun_mihomo` | Отсутствует или другое | Добавляется/перезаписывается на `tun_mihomo` (правила firewall) |

### Пример

**До** (ваш конфиг с Android/Windows):
```yaml
dns:
  listen: 127.0.0.1:6868
tun:
  stack: mixed
```

**После** (автоматически при `service mihomo start`):
```yaml
dns:
  listen: 127.0.0.1:1053
tun:
  stack: gvisor
  device: tun_mihomo
```

### Откат

Оригинальный конфиг сохраняется один раз в `/usr/local/etc/mihomo/config.yaml.normalized` при первой нормализации.

```sh
# Посмотреть, что изменилось:
diff -u /usr/local/etc/mihomo/config.yaml.normalized /usr/local/etc/mihomo/config.yaml
```

### Когда это не нужно

Если ваш конфиг уже содержит правильные значения для OPNsense, нормализация **не выполняется** (идемпотентна).

## Совместимость синтаксиса

Плагин поддерживает **полный синтаксис mihomo v1.19.x**, включая:

- DoH/DoT/DoQ upstream (`nameserver: https://1.1.1.1/dns-query#🌍 VPN`)
- `redir-host` и `fake-ip` режимы
- `mixed-port` (одновременно HTTP/SOCKS5)
- Правила `rule-set`, `nameserver-policy`, `domain-suffix`
- `sniffer` с TLS/HTTP/QUIC (QUIC работает только при `stack: gvisor`)
- `find-process-mode` (рекомендуется `off` на FreeBSD)
- Proxy groups: `select`, `fallback`, `url-test`, `load-balance`

### Неподдерживаемые функции

| Параметр | Статус | Причина |
|----------|--------|---------|
| `tun.stack: mixed` | ❌ Не работает | FreeBSD не имеет mixed stack → mihomo не создаёт TUN |
| `tun.stack: lwip` | ❌ Не работает | Не реализовано в mihomo под FreeBSD |
| DoH bootstrap без `default-nameserver` | ❌ Не работает | Bootstrap требует plain IP для резолва DoH-хоста |

### Рекомендации

1. **DoH/DoT upstream**: добавьте `default-nameserver` с plain IP (нужны для bootstrap):
   ```yaml
   dns:
     default-nameserver:
       - 77.88.8.8
       - 1.1.1.1
     nameserver:
       - https://9.9.9.9/dns-query#🌍 VPN
   ```

2. **Прокси для российских сайтов**: используйте `nameserver-policy` и `rule-set`:
   ```yaml
   dns:
     direct-nameserver:
       - 77.88.8.8
     nameserver-policy:
       "rule-set:geosite-ru": &direct
         - 77.88.8.8
   rules:
     - RULE-SET,geosite-ru,🌍 VPN
   ```

3. **QUIC sniffer**: работает только с `stack: gvisor`.

4. **Process sniffing**: `find-process-mode: off` (strict/always требуют `/proc`, которого нет на FreeBSD).

## Переход с другой платформы

Если у вас готовый конфиг с Android/Windows/Linux mihomo:

1. **Скопируйте** файл целиком в OPNsense через WebGUI или `scp root@opnsense:/usr/local/etc/mihomo/config.yaml`.
2. **Добавьте** `default-nameserver`, если используете DoH (см. выше).
3. **Перезапустите** службу: `service mihomo restart`.

Плагин автоматически адаптирует три параметра, остальное работает как есть.

## Подробности

- [Нормализация выполняется в `mihomo_prestart()`](../src/os-mihomo/src/usr/local/etc/rc.d/mihomo)
- [Скрипт хранит awk state machine для трёх ключей](../src/os-mihomo/src/usr/local/etc/rc.d/mihomo#L28-L73)
- [Unbound forward всегда на 1053](../src/os-mihomo/src/usr/local/opnsense/scripts/mihomo/setup_unbound.php#L94)
- [Правило firewall хардкодит `tun_mihomo`](../src/os-mihomo/packaging/freebsd/+POST_INSTALL#L5)
