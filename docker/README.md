# Blitz — Docker Deployment

## Quick Start

```bash
# 1. Copy and edit the environment file
cp docker/.env.example docker/.env
nano docker/.env

# 2. Build and start
docker compose up -d --build

# 3. Check logs for the admin password and web panel URL
docker logs blitz 2>&1 | grep -E "ADMIN PASSWORD|Access at"

# 4. Check all services are running
docker exec blitz supervisorctl -c /tmp/supervisord.conf status
```

## Environment Variables

Create `docker/.env` from `docker/.env.example` and configure the following:

### Hysteria2 Core

| Variable | Default | Description |
|----------|---------|-------------|
| `HYSTERIA_PORT` | `8080` | UDP port for the Hysteria2 server. Must be open in the firewall (the entrypoint opens it automatically via iptables). |
| `HYSTERIA_SNI` | *(auto-detected)* | Domain or IP used as the TLS certificate CN and in client URIs. If blank, the public IP is auto-detected via `ip.sb`. |
| `SERVER_IPV6` | *(empty)* | Server IPv6 address. Used in `.configs.env` for client URI generation. |

### Traffic Obfuscation

OBFS and Masquerade are **mutually exclusive**. If both are set, OBFS takes priority.

| Variable | Default | Description |
|----------|---------|-------------|
| `OBFS_PASSWORD` | *(random)* | Salamander obfuscation password. If blank, a random 32-char password is generated. Set explicitly to share across reinstalls. |
| `MASQUERADE_URL` | *(empty)* | Disguise Hysteria2 when probed by non-clients. Set to a URL (e.g. `https://example.com`) to proxy requests to that site, or `string` to return a generic HTTP 502 response. **Only works when `OBFS_PASSWORD` is not set.** |

### Web Panel

| Variable | Default | Description |
|----------|---------|-------------|
| `WEBPANEL_PORT` | `2096` | TCP port for the web panel. Opened automatically in iptables. |
| `ADMIN_USERNAME` | `admin` | Web panel admin username. |
| `ADMIN_PASSWORD` | *(random)* | Web panel admin password. If blank, a random 16-char password is generated and printed to the container logs on first start. |
| `WEBPANEL_EXPIRATION_MINUTES` | `1440` | Admin session expiration time in minutes (1440 = 24 hours). |

### NormalSub (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `NORMALSUB_ENABLED` | `false` | Set to `true` to enable the NormalSub subscription service. |
| `NORMALSUB_PORT` | `2095` | TCP port for the NormalSub service. |

### Telegram Bot (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `TELEGRAM_ENABLED` | `false` | Set to `true` to enable the Telegram bot. |
| `TELEGRAM_BOT_TOKEN` | *(empty)* | Telegram Bot API token from @BotFather. Required if enabled. |
| `TELEGRAM_ADMIN_USER_IDS` | *(empty)* | Comma-separated Telegram user IDs with admin access (e.g. `123456,789012`). |
| `TELEGRAM_BACKUP_INTERVAL_HOUR` | `6` | Automatic backup interval in hours. |

## Architecture

The Docker deployment runs everything in **two containers**:

| Container | Description |
|-----------|-------------|
| `mongodb` | MongoDB 8.0 database |
| `blitz` | All Blitz services managed by supervisord |

Services inside the `blitz` container:

| Service | Description |
|---------|-------------|
| `hysteria-server` | Hysteria2 proxy server |
| `hysteria-auth` | Go-based authentication server |
| `hysteria-scheduler` | Traffic tracking and user expiration scheduler |
| `hysteria-webpanel` | Web management panel (hypercorn/FastAPI) |
| `hysteria-normalsub` | Subscription service (if enabled) |
| `hysteria-telegrambot` | Telegram bot (if enabled) |

Both containers use `network_mode: "host"` for direct access to host networking.

## Data Persistence

All persistent data is stored in the `blitz_data` Docker volume:

- `config.json` — Hysteria2 server configuration
- `ca.crt` / `ca.key` — TLS certificates
- `.configs.env` — Server IP/SNI configuration
- `webpanel.env` — Web panel credentials and settings
- `normalsub.env` — NormalSub settings
- `telegrambot.env` — Telegram bot settings
- `.initialized` — First-run marker

## Common Operations

```bash
# View service status
docker exec blitz supervisorctl -c /tmp/supervisord.conf status

# Restart Hysteria2 server
docker exec blitz supervisorctl -c /tmp/supervisord.conf restart hysteria-server

# View logs
docker logs blitz

# List users
docker exec blitz python3 /etc/hysteria/core/cli.py list-users

# Get user connection URI
docker exec blitz python3 /etc/hysteria/core/cli.py show-user-uri -u <username> -ip 4

# Full rebuild (reset all data)
docker compose down
docker volume rm blitz_blitz_data
docker compose up -d --build
```

## Troubleshooting

**Web panel not accessible externally:** Ensure `WEBPANEL_PORT` is open. The entrypoint opens it via iptables, but some cloud providers have separate firewall rules.

**Hysteria2 clients can't connect:** Ensure `HYSTERIA_PORT` is open for **UDP** traffic. The entrypoint opens it via iptables automatically.

**Forgot admin password:** Remove the volume and rebuild to regenerate credentials:
```bash
docker compose down && docker volume rm blitz_blitz_data && docker compose up -d --build
```

**Services show FATAL:** Check `docker logs blitz` for error details. Common causes: port already in use, invalid config.json.
