#!/bin/bash
set -e

BLITZ_DATA_DIR="/blitz-data"
HYSTERIA_DIR="/etc/hysteria"
VENV_PYTHON="${HYSTERIA_DIR}/hysteria2_venv/bin/python3"
CONFIG_FILE="${HYSTERIA_DIR}/config.json"
CLI_PATH="${HYSTERIA_DIR}/core/cli.py"

# ---------------------------------------------------------------------------
# 1. Check CPU AVX support (required by MongoDB 5.0+)
# ---------------------------------------------------------------------------
if [ -f /proc/cpuinfo ] && ! grep -q -m1 -oE 'avx|avx2|avx512' /proc/cpuinfo; then
    echo "============================================================"
    echo "[entrypoint] ERROR: CPU does not support AVX instructions."
    echo "[entrypoint] MongoDB 5.0+ requires AVX. See: https://www.mongodb.com/docs/manual/administration/production-notes/"
    echo "[entrypoint] Consider using the 'nodb' branch of Blitz for systems without AVX."
    echo "============================================================"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Wait for MongoDB
# ---------------------------------------------------------------------------
echo "[entrypoint] Waiting for MongoDB at localhost:27017..."
until "${VENV_PYTHON}" -c \
    "import pymongo; pymongo.MongoClient('mongodb://localhost:27017', serverSelectionTimeoutMS=2000).admin.command('ping')" \
    2>/dev/null; do
    echo "[entrypoint] MongoDB not ready — retrying in 2s..."
    sleep 2
done
echo "[entrypoint] MongoDB is up."

# ---------------------------------------------------------------------------
# 2. Set up persistent volume directories and symlinks
# ---------------------------------------------------------------------------
mkdir -p "${BLITZ_DATA_DIR}"

# Symlink Hysteria2 config + TLS certs so they persist across container recreation
for f in config.json ca.crt ca.key; do
    target="${HYSTERIA_DIR}/${f}"
    source="${BLITZ_DATA_DIR}/${f}"
    [ -e "${target}" ] && [ ! -L "${target}" ] && rm -f "${target}"
    [ ! -L "${target}" ] && ln -sf "${source}" "${target}"
done

# Symlink blitz runtime data files into /etc/hysteria
for f in .configs.env nodes.json extra.json traffic_data.json hysteria_connections.json; do
    target="${HYSTERIA_DIR}/${f}"
    source="${BLITZ_DATA_DIR}/${f}"
    [ -e "${target}" ] && [ ! -L "${target}" ] && rm -f "${target}"
    [ ! -L "${target}" ] && ln -sf "${source}" "${target}"
done

# Symlink service .env files so they persist in blitz_data across container recreation
declare -A SERVICE_ENVS=(
    ["${HYSTERIA_DIR}/core/scripts/webpanel/.env"]="${BLITZ_DATA_DIR}/webpanel.env"
    ["${HYSTERIA_DIR}/core/scripts/normalsub/.env"]="${BLITZ_DATA_DIR}/normalsub.env"
    ["${HYSTERIA_DIR}/core/scripts/telegrambot/.env"]="${BLITZ_DATA_DIR}/telegrambot.env"
)
for target in "${!SERVICE_ENVS[@]}"; do
    source="${SERVICE_ENVS[$target]}"
    [ -e "${target}" ] && [ ! -L "${target}" ] && rm -f "${target}"
    [ ! -L "${target}" ] && ln -sf "${source}" "${target}"
done

# ---------------------------------------------------------------------------
# 3. Auto-detect SNI if not provided
# ---------------------------------------------------------------------------
if [ -z "${HYSTERIA_SNI}" ]; then
    echo "[entrypoint] HYSTERIA_SNI is empty — auto-detecting from ip.sb..."
    HYSTERIA_SNI=$(curl -s -4 --max-time 10 ip.sb 2>/dev/null || true)
    if [ -z "${HYSTERIA_SNI}" ]; then
        echo "[entrypoint] WARNING: could not detect public IP; using 'localhost' as SNI"
        HYSTERIA_SNI="localhost"
    fi
    echo "[entrypoint] HYSTERIA_SNI=${HYSTERIA_SNI}"
fi

# ---------------------------------------------------------------------------
# 4. Generate ECDSA TLS certificates — same as bare-metal install (first run)
# ---------------------------------------------------------------------------
if [ ! -f "${BLITZ_DATA_DIR}/ca.crt" ]; then
    echo "[entrypoint] Generating ECDSA TLS certificate for CN=${HYSTERIA_SNI}..."
    openssl ecparam -genkey -name prime256v1 -out "${BLITZ_DATA_DIR}/ca.key" 2>/dev/null
    openssl req -new -x509 -days 36500 \
        -key "${BLITZ_DATA_DIR}/ca.key" \
        -out "${BLITZ_DATA_DIR}/ca.crt" \
        -subj "/CN=${HYSTERIA_SNI}" 2>/dev/null
    chmod 640 "${BLITZ_DATA_DIR}/ca.key" "${BLITZ_DATA_DIR}/ca.crt"
    echo "[entrypoint] TLS certificate generated."
fi

# ---------------------------------------------------------------------------
# 5. Generate Hysteria2 config.json using repo template + jq (first run)
# ---------------------------------------------------------------------------
if [ ! -f "${BLITZ_DATA_DIR}/config.json" ]; then
    echo "[entrypoint] Generating Hysteria2 config.json..."

    PORT="${HYSTERIA_PORT:-8080}"
    SHA256=$(openssl x509 -noout -fingerprint -sha256 -inform pem \
        -in "${BLITZ_DATA_DIR}/ca.crt" | sed 's/.*=//;s///g')
    TRAFFIC_SECRET=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    NETWORK_DEF=$(ip route | grep "^default" | awk '{print $5}' | head -n1)

    # Use the repo's config.json template and substitute values with jq,
    # exactly as the bare-metal install.sh does.
    OBFS_PASS="${OBFS_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)}"
    jq --arg port "$PORT" \
       --arg sha256 "$SHA256" \
       --arg obfspassword "$OBFS_PASS" \
       --arg UUID "$TRAFFIC_SECRET" \
       --arg networkdef "$NETWORK_DEF" \
       '.listen = ":\($port)" |
        .tls.cert = "/etc/hysteria/ca.crt" |
        .tls.key = "/etc/hysteria/ca.key" |
        .tls.pinSHA256 = $sha256 |
        .obfs.salamander.password = $obfspassword |
        .trafficStats.secret = $UUID |
        .outbounds[0].direct.bindDevice = $networkdef' \
       "${HYSTERIA_DIR}/config.json.template" > "${BLITZ_DATA_DIR}/config.json"

    # Masquerade and OBFS are mutually exclusive.
    # If MASQUERADE_URL is set and no explicit OBFS_PASSWORD was provided, replace obfs with masquerade.
    if [ -n "${MASQUERADE_URL}" ] && [ -z "${OBFS_PASSWORD}" ]; then
        echo "[entrypoint] Configuring masquerade (removing obfs)..."
        if [ "${MASQUERADE_URL}" = "string" ]; then
            # Return a generic HTTP 502 response (same as bare-metal masquerade.py)
            jq 'del(.obfs) | .masquerade = {
                "type": "string",
                "string": {
                    "content": "HTTP 502: Bad Gateway",
                    "headers": {"Content-Type": "text/plain; charset=utf-8", "Server": "Caddy"},
                    "statusCode": 502
                }
            }' "${BLITZ_DATA_DIR}/config.json" > "${BLITZ_DATA_DIR}/config.json.tmp" \
            && mv "${BLITZ_DATA_DIR}/config.json.tmp" "${BLITZ_DATA_DIR}/config.json"
        else
            # Proxy mode — forward requests to the specified URL
            jq --arg url "${MASQUERADE_URL}" 'del(.obfs) | .masquerade = {
                "type": "proxy",
                "proxy": {"url": $url}
            }' "${BLITZ_DATA_DIR}/config.json" > "${BLITZ_DATA_DIR}/config.json.tmp" \
            && mv "${BLITZ_DATA_DIR}/config.json.tmp" "${BLITZ_DATA_DIR}/config.json"
        fi
        echo "[entrypoint] Masquerade configured."
    fi

    echo "[entrypoint] config.json generated."
fi

# ---------------------------------------------------------------------------
# 7. Generate .configs.env (first run)
# ---------------------------------------------------------------------------
if [ ! -f "${BLITZ_DATA_DIR}/.configs.env" ]; then
    echo "[entrypoint] Generating .configs.env..."
    IP4="${HYSTERIA_SNI}"
    IP6="${SERVER_IPV6:-}"
    cat > "${BLITZ_DATA_DIR}/.configs.env" <<EOF
SNI=${HYSTERIA_SNI}
IP4=${IP4}
IP6=${IP6}
EOF
    echo "[entrypoint] .configs.env generated."
fi

# ---------------------------------------------------------------------------
# 8. Generate webpanel .env (first run)
# ---------------------------------------------------------------------------
WEBPANEL_ENV="${BLITZ_DATA_DIR}/webpanel.env"
if [ ! -f "${WEBPANEL_ENV}" ]; then
    echo "[entrypoint] Generating webpanel .env..."
    ROOT_PATH=$(openssl rand -hex 16)
    API_TOKEN=$(openssl rand -hex 32)

    if [ -z "${ADMIN_PASSWORD}" ]; then
        GENERATED_PASSWORD=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16)
        echo "============================================================"
        echo "[entrypoint] ADMIN PASSWORD (save this): ${GENERATED_PASSWORD}"
        echo "============================================================"
        ADMIN_PASSWORD_HASH=$(echo -n "${GENERATED_PASSWORD}" | sha256sum | cut -d' ' -f1)
    else
        ADMIN_PASSWORD_HASH=$(echo -n "${ADMIN_PASSWORD}" | sha256sum | cut -d' ' -f1)
    fi

    cat > "${WEBPANEL_ENV}" <<EOF
DEBUG=false
DOMAIN=${HYSTERIA_SNI}
PORT=${WEBPANEL_PORT:-2096}
ROOT_PATH=${ROOT_PATH}
API_TOKEN=${API_TOKEN}
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD_HASH}
EXPIRATION_MINUTES=${WEBPANEL_EXPIRATION_MINUTES:-1440}
EOF
    echo "[entrypoint] Webpanel .env generated. Access at: http://<host>:${WEBPANEL_PORT:-2096}/${ROOT_PATH}/"
fi

# ---------------------------------------------------------------------------
# 9. Generate normalsub .env (first run, if enabled)
# ---------------------------------------------------------------------------
if [ "${NORMALSUB_ENABLED}" = "true" ]; then
    NORMALSUB_ENV="${BLITZ_DATA_DIR}/normalsub.env"
    if [ ! -f "${NORMALSUB_ENV}" ]; then
        echo "[entrypoint] Generating normalsub .env..."
        SUBPATH=$(openssl rand -hex 16)
        cat > "${NORMALSUB_ENV}" <<EOF
HYSTERIA_DOMAIN=${HYSTERIA_SNI}
HYSTERIA_PORT=${NORMALSUB_PORT:-2095}
AIOHTTP_LISTEN_ADDRESS=0.0.0.0
AIOHTTP_LISTEN_PORT=${NORMALSUB_PORT:-2095}
SUBPATH=${SUBPATH}
EOF
        echo "[entrypoint] Normalsub .env generated. Subscription at: http://<host>:${NORMALSUB_PORT:-2095}/${SUBPATH}/<username>"
    fi
fi

# ---------------------------------------------------------------------------
# 10. Generate telegrambot .env (first run, if enabled)
# ---------------------------------------------------------------------------
if [ "${TELEGRAM_ENABLED}" = "true" ]; then
    TELEGRAM_ENV="${BLITZ_DATA_DIR}/telegrambot.env"
    if [ ! -f "${TELEGRAM_ENV}" ]; then
        echo "[entrypoint] Generating telegrambot .env..."
        cat > "${TELEGRAM_ENV}" <<EOF
API_TOKEN=${TELEGRAM_BOT_TOKEN}
ADMIN_USER_IDS=[${TELEGRAM_ADMIN_USER_IDS}]
BACKUP_INTERVAL_HOUR=${TELEGRAM_BACKUP_INTERVAL_HOUR:-6}
EOF
        echo "[entrypoint] Telegrambot .env generated."
    fi
fi

# ---------------------------------------------------------------------------
# 11. Generate supervisord config (always — ephemeral, reflects current env)
# ---------------------------------------------------------------------------
echo "[entrypoint] Generating supervisord config..."

WEBPANEL_BIND_PORT=$(grep '^PORT=' "${BLITZ_DATA_DIR}/webpanel.env" 2>/dev/null | cut -d= -f2 || echo "${WEBPANEL_PORT:-2096}")

SUPERVISOR_CONF="/tmp/supervisord.conf"

cat > "${SUPERVISOR_CONF}" <<EOF
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0
loglevel=info

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:hysteria-server]
command=/usr/local/bin/hysteria server --config /etc/hysteria/config.json
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:hysteria-auth]
command=${HYSTERIA_DIR}/core/scripts/auth/user_auth
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:hysteria-scheduler]
command=${VENV_PYTHON} ${HYSTERIA_DIR}/core/scripts/scheduler.py
directory=${HYSTERIA_DIR}/core/scripts
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:hysteria-webpanel]
command=${HYSTERIA_DIR}/hysteria2_venv/bin/hypercorn app:app --bind 0.0.0.0:${WEBPANEL_BIND_PORT} --access-logfile - --error-logfile -
directory=${HYSTERIA_DIR}/core/scripts/webpanel
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

if [ "${NORMALSUB_ENABLED}" = "true" ]; then
    cat >> "${SUPERVISOR_CONF}" <<EOF

[program:hysteria-normalsub]
command=${VENV_PYTHON} ${HYSTERIA_DIR}/core/scripts/normalsub/normalsub.py
directory=${HYSTERIA_DIR}/core/scripts/normalsub
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

if [ "${TELEGRAM_ENABLED}" = "true" ]; then
    cat >> "${SUPERVISOR_CONF}" <<EOF

[program:hysteria-telegrambot]
command=${VENV_PYTHON} ${HYSTERIA_DIR}/core/scripts/telegrambot/tbot.py
directory=${HYSTERIA_DIR}/core/scripts/telegrambot
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

echo "[entrypoint] Supervisord config written to ${SUPERVISOR_CONF}."

# ---------------------------------------------------------------------------
# 12. Unset docker env vars that clash with per-service pydantic .env files
# ---------------------------------------------------------------------------
unset ADMIN_PASSWORD ADMIN_USERNAME WEBPANEL_PORT WEBPANEL_EXPIRATION_MINUTES
unset NORMALSUB_ENABLED NORMALSUB_PORT
unset TELEGRAM_ENABLED TELEGRAM_BOT_TOKEN TELEGRAM_ADMIN_USER_IDS TELEGRAM_BACKUP_INTERVAL_HOUR

# ---------------------------------------------------------------------------
# 13. Create default user on first run (same as bare-metal install.sh)
# ---------------------------------------------------------------------------
FIRST_RUN_MARKER="${BLITZ_DATA_DIR}/.initialized"
if [ ! -f "${FIRST_RUN_MARKER}" ]; then
    echo "[entrypoint] First run — starting services briefly to create default user..."
    /usr/bin/supervisord -c "${SUPERVISOR_CONF}" &
    SUPERVISOR_PID=$!

    # Wait for auth server to be ready
    echo "[entrypoint] Waiting for auth server..."
    for i in $(seq 1 30); do
        if supervisorctl -c "${SUPERVISOR_CONF}" status hysteria-auth 2>/dev/null | grep -q "RUNNING"; then
            break
        fi
        sleep 1
    done

    echo "[entrypoint] Creating default user..."
    "${VENV_PYTHON}" "${CLI_PATH}" add-user \
        --username default --traffic-limit 30 --expiration-days 30 || true

    touch "${FIRST_RUN_MARKER}"
    echo "[entrypoint] Default user created. Restarting supervisord cleanly..."

    # Stop the temporary supervisord and restart it via exec below
    kill "${SUPERVISOR_PID}" 2>/dev/null || true
    wait "${SUPERVISOR_PID}" 2>/dev/null || true
    sleep 1
fi

# ---------------------------------------------------------------------------
# 14. Open firewall ports
# ---------------------------------------------------------------------------
HYSTERIA_LISTEN_PORT=$(jq -r '.listen' "${BLITZ_DATA_DIR}/config.json" 2>/dev/null | tr -dc '0-9')
if [ -n "${HYSTERIA_LISTEN_PORT}" ]; then
    # Open Hysteria UDP port
    if ! iptables -C INPUT -p udp --dport "${HYSTERIA_LISTEN_PORT}" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport "${HYSTERIA_LISTEN_PORT}" -j ACCEPT 2>/dev/null && \
            echo "[entrypoint] Firewall: opened UDP port ${HYSTERIA_LISTEN_PORT}"
    fi
    # Open webpanel TCP port
    if ! iptables -C INPUT -p tcp --dport "${WEBPANEL_BIND_PORT}" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "${WEBPANEL_BIND_PORT}" -j ACCEPT 2>/dev/null && \
            echo "[entrypoint] Firewall: opened TCP port ${WEBPANEL_BIND_PORT}"
    fi
fi

# ---------------------------------------------------------------------------
# 15. Start supervisord
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting supervisord..."
exec /usr/bin/supervisord -n -c "${SUPERVISOR_CONF}"
