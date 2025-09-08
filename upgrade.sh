#!/bin/bash

set -euo pipefail
trap 'echo -e "\n❌ An error occurred. Aborting."; exit 1' ERR

# ========== Variables ==========
HYSTERIA_INSTALL_DIR="/etc/hysteria"
HYSTERIA_VENV_DIR="$HYSTERIA_INSTALL_DIR/hysteria2_venv"
AUTH_BINARY_DIR="$HYSTERIA_INSTALL_DIR/core/scripts/auth"
REPO_URL="https://github.com/ReturnFI/Blitz"
REPO_BRANCH="nodb"
GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"

# ========== Color Setup ==========
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] - ${RESET} $1"; }
success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [OK] - ${RESET} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] - ${RESET} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] - ${RESET} $1"; }

# ========== Capture Active Services ==========
declare -a ACTIVE_SERVICES_BEFORE_UPGRADE=()
ALL_SERVICES=(
    hysteria-caddy.service
    hysteria-server.service
    hysteria-auth.service
    hysteria-scheduler.service
    hysteria-telegram-bot.service
    hysteria-normal-sub.service
    hysteria-caddy-normalsub.service
    hysteria-webpanel.service
    hysteria-ip-limit.service
)

info "Checking for active services before upgrade..."
for SERVICE in "${ALL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        ACTIVE_SERVICES_BEFORE_UPGRADE+=("$SERVICE")
        info "Service '$SERVICE' is active and will be restarted."
    fi
done


# ========== New Function to Install Go and Compile Auth Binary ==========
install_go_and_compile_auth() {
    info "Checking for Go and compiling authentication binary..."
    if ! command -v go &>/dev/null; then
        warn "Go is not installed. Attempting to install..."
        #apt-get update -qq >/dev/null
        apt install golang-go -y
        success "Go installed successfully."
    else
        success "Go is already installed."
    fi

    if [[ -f "$AUTH_BINARY_DIR/user_auth.go" ]]; then
        info "Found auth binary source. Compiling..."
        (
            cd "$AUTH_BINARY_DIR"
            go mod init hysteria_auth >/dev/null 2>&1
            go mod tidy >/dev/null 2>&1
            if go build -o user_auth .; then
                chmod +x user_auth
                success "Authentication binary compiled successfully."
            else
                error "Failed to compile the authentication binary."
                exit 1
            fi
        )
    else
        warn "Authentication binary source not found. Skipping compilation."
    fi
}

# ========== Backup Files ==========
cd /root
TEMP_DIR=$(mktemp -d)
FILES=(
    "$HYSTERIA_INSTALL_DIR/ca.key"
    "$HYSTERIA_INSTALL_DIR/ca.crt"
    "$HYSTERIA_INSTALL_DIR/users.json"
    "$HYSTERIA_INSTALL_DIR/config.json"
    "$HYSTERIA_INSTALL_DIR/.configs.env"
    "$HYSTERIA_INSTALL_DIR/nodes.json"
    "$HYSTERIA_INSTALL_DIR/extra.json"
    "$HYSTERIA_INSTALL_DIR/core/scripts/telegrambot/.env"
    "$HYSTERIA_INSTALL_DIR/core/scripts/normalsub/.env"
    "$HYSTERIA_INSTALL_DIR/core/scripts/normalsub/Caddyfile.normalsub"
    "$HYSTERIA_INSTALL_DIR/core/scripts/webpanel/.env"
    "$HYSTERIA_INSTALL_DIR/core/scripts/webpanel/Caddyfile"
)

info "Backing up configuration files to: $TEMP_DIR"
for FILE in "${FILES[@]}"; do
    if [[ -f "$FILE" ]]; then
        mkdir -p "$TEMP_DIR/$(dirname "$FILE")"
        cp -p "$FILE" "$TEMP_DIR/$FILE"
        success "Backed up: $FILE"
    else
        warn "File not found: $FILE"
    fi
done

# ========== Replace Installation ==========
info "Removing old hysteria directory..."
rm -rf "$HYSTERIA_INSTALL_DIR"

info "Cloning Blitz repository (branch: $REPO_BRANCH)..."
git clone -q -b "$REPO_BRANCH" "$REPO_URL" "$HYSTERIA_INSTALL_DIR"

# ========== Download Geo Data ==========
info "Downloading geosite.dat and geoip.dat..."
wget -q -O "$HYSTERIA_INSTALL_DIR/geosite.dat" "$GEOSITE_URL"
wget -q -O "$HYSTERIA_INSTALL_DIR/geoip.dat" "$GEOIP_URL"
success "Geo data downloaded."

# ========== Restore Backup ==========
info "Restoring configuration files..."
for FILE in "${FILES[@]}"; do
    BACKUP="$TEMP_DIR/$FILE"
    if [[ -f "$BACKUP" ]]; then
        cp -p "$BACKUP" "$FILE"
        success "Restored: $FILE"
    else
        warn "Missing backup file: $BACKUP"
    fi
done

# ========== Update Configuration ==========
info "Updating Hysteria configuration for HTTP authentication..."
auth_block='{"type": "http", "http": {"url": "http://127.0.0.1:28262/auth"}}'
if [[ -f "$HYSTERIA_INSTALL_DIR/config.json" ]]; then
    jq --argjson auth_block "$auth_block" '.auth = $auth_block' "$HYSTERIA_INSTALL_DIR/config.json" > "$HYSTERIA_INSTALL_DIR/config.json.tmp" && mv "$HYSTERIA_INSTALL_DIR/config.json.tmp" "$HYSTERIA_INSTALL_DIR/config.json"
    success "config.json updated to use auth server."
else
    warn "config.json not found after restore. Skipping auth update."
fi

# ========== Permissions ==========
info "Setting ownership and permissions..."
chown hysteria:hysteria "$HYSTERIA_INSTALL_DIR/ca.key" "$HYSTERIA_INSTALL_DIR/ca.crt"
chmod 640 "$HYSTERIA_INSTALL_DIR/ca.key" "$HYSTERIA_INSTALL_DIR/ca.crt"
chown -R hysteria:hysteria "$HYSTERIA_INSTALL_DIR/core/scripts/telegrambot"
chmod +x "$HYSTERIA_INSTALL_DIR/core/scripts/hysteria2/kick.py"

# ========== Virtual Environment ==========
info "Setting up virtual environment and installing dependencies..."
cd "$HYSTERIA_INSTALL_DIR"
python3 -m venv "$HYSTERIA_VENV_DIR"
source "$HYSTERIA_VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install -r requirements.txt >/dev/null
success "Python environment ready."

# ========== Compile Go Binary ==========
install_go_and_compile_auth

# ========== Systemd Services ==========
info "Ensuring systemd services are configured..."
if source "$HYSTERIA_INSTALL_DIR/core/scripts/scheduler.sh"; then
    if ! check_auth_server_service; then
        setup_hysteria_auth_server && success "Auth server service configured." || warn "Auth server setup failed."
    else
        success "Auth server service already configured."
    fi

    if ! check_scheduler_service; then
        setup_hysteria_scheduler && success "Scheduler service configured." || warn "Scheduler setup failed."
    else
        success "Scheduler service already set."
    fi
else
    warn "Failed to source scheduler.sh, continuing without service setup..."
fi

# ========== Restart Services ==========
info "Reloading systemd daemon..."
systemctl daemon-reload

info "Restarting services that were active before the upgrade..."
if [ ${#ACTIVE_SERVICES_BEFORE_UPGRADE[@]} -eq 0 ]; then
    warn "No relevant services were active before the upgrade. Skipping restart."
else
    for SERVICE in "${ACTIVE_SERVICES_BEFORE_UPGRADE[@]}"; do
        systemctl restart "$SERVICE" && success "$SERVICE restarted." || warn "$SERVICE failed to restart."
    done
fi


# ========== Final Check ==========
if systemctl is-active --quiet hysteria-server.service; then
    success "🎉 Upgrade completed successfully!"
else
    warn "⚠️ hysteria-server.service is not active. Check logs if needed."
fi

# ========== Launch Menu ==========
sleep 10
chmod +x menu.sh
./menu.sh
