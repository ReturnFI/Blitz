#!/bin/bash

set -euo pipefail
trap 'echo -e "\n❌ An error occurred. Aborting."; exit 1' ERR

# ========== Variables ==========
HYSTERIA_INSTALL_DIR="/etc/hysteria"
HYSTERIA_VENV_DIR="$HYSTERIA_INSTALL_DIR/hysteria2_venv"
GEOSITE_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat"
GEOIP_URL="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat"
MIGRATE_SCRIPT_PATH="$HYSTERIA_INSTALL_DIR/core/scripts/db/migrate_users.py"

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

# ========== Check AVX Support ==========
check_avx_support() {
    info "Checking CPU for AVX support (required for MongoDB)..."
    if grep -q -m1 -o -E 'avx|avx2|avx512' /proc/cpuinfo; then
        success "CPU supports AVX instruction set."
    else
        error "CPU does not support the required AVX instruction set for MongoDB."
        info "Your system is not compatible with this version."
        info "Please use the 'nodb' upgrade script instead:"
        echo -e "${YELLOW}bash <(curl -sL https://raw.githubusercontent.com/ReturnFI/Blitz/nodb/upgrade.sh)${RESET}"
        error "Upgrade aborted."
        exit 1
    fi
}

# ========== Fix Caddy Repository ==========
fix_caddy_repo() {
    info "Checking Caddy repository configuration..."
    local caddy_source_list="/etc/apt/sources.list.d/caddy-stable.list"
    local new_caddy_keyring="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    local old_caddy_key="/etc/apt/trusted.gpg.d/caddy.asc"

    if [[ -f "$old_caddy_key" ]] || { [[ -f "$caddy_source_list" ]] && grep -q "caddy.asc" "$caddy_source_list"; }; then
        warn "Outdated Caddy repository configuration detected. Fixing it..."
        
        if [[ -f "$old_caddy_key" ]]; then
            rm -f "$old_caddy_key"
            info "Removed old Caddy GPG key."
        fi
        
        rm -f "$new_caddy_keyring"
        info "Downloading new Caddy GPG key..."
        if ! curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o "$new_caddy_keyring"; then
            error "Failed to download or process the Caddy GPG key."
            exit 1
        fi
        
        info "Updating Caddy sources list..."
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee "$caddy_source_list" > /dev/null
        
        chmod o+r "$new_caddy_keyring"
        chmod o+r "$caddy_source_list"
        
        info "Running apt update to apply repository changes..."
        apt-get update -qq
        success "Caddy repository configuration has been updated."
    else
        success "Caddy repository configuration is up-to-date."
    fi
}

# ========== Install MongoDB ==========
install_mongodb() {
    info "Checking for MongoDB..."
    if ! command -v mongod &>/dev/null; then
        warn "MongoDB not found. Installing from official repository..."
        
        local os_name os_version
        os_name=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        os_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        
        apt-get update 
        apt-get install -y gnupg curl lsb-release
        
        curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
        
        if [[ "$os_name" == "ubuntu" ]]; then
            if [[ "$os_version" == "24.04" ]]; then
                echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
            elif [[ "$os_version" == "22.04" ]]; then
                echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
            else
                echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
            fi
        elif [[ "$os_name" == "debian" && "$os_version" == "12" ]]; then
            echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" > /etc/apt/sources.list.d/mongodb-org-8.0.list
        else
            error "Unsupported OS for MongoDB installation: $os_name $os_version"
            exit 1
        fi
        
        apt-get update -qq
        apt-get install -y mongodb-org
        systemctl start mongod
        systemctl enable mongod
        success "MongoDB installed and started successfully."
    else
        success "MongoDB is already installed."
    fi
}

# ========== New Function to Migrate Data ==========
migrate_json_to_mongo() {
    info "Checking for user data migration..."
    if [[ -f "$HYSTERIA_INSTALL_DIR/users.json" ]]; then
        info "Found users.json. Proceeding with migration to MongoDB."
        if python3 "$MIGRATE_SCRIPT_PATH"; then
            success "Data migration completed successfully."
        else
            error "Data migration script failed. Please check the output above."
            exit 1
        fi
    else
        info "No users.json found. Skipping migration."
    fi
}

download_and_extract_latest_release() {
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    info "Detected architecture: $arch"

    local zip_name="Blitz-${arch}.zip"
    local download_url="https://github.com/ReturnFI/Blitz/releases/latest/download/${zip_name}"
    local temp_zip="/tmp/${zip_name}"

    info "Downloading latest release from ${download_url}..."
    if ! curl -sL -o "$temp_zip" "$download_url"; then
        error "Failed to download the release asset. Please check the URL and your connection."
        exit 1
    fi
    success "Download complete."

    info "Removing old installation directory..."
    rm -rf "$HYSTERIA_INSTALL_DIR"
    mkdir -p "$HYSTERIA_INSTALL_DIR"
    
    info "Extracting to ${HYSTERIA_INSTALL_DIR}..."
    if ! unzip -q "$temp_zip" -d "$HYSTERIA_INSTALL_DIR"; then
        error "Failed to extract the archive."
        exit 1
    fi
    success "Extracted successfully."
    
    rm "$temp_zip"
    info "Cleaned up temporary file."
}

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

# ========== Check for existing upgrade process ==========
if [ -f "/tmp/hysteria_upgrade.lock" ]; then
    info "Found existing upgrade lock file. This might be from a previous interrupted upgrade."
    info "Removing lock file to allow this upgrade to proceed..."
    rm -f /tmp/hysteria_upgrade.lock
fi

# ========== Create new lock file ==========
echo $$ > /tmp/hysteria_upgrade.lock
info "Upgrade process started. PID: $$"

# ========== Check AVX Support Prerequisite ==========
check_avx_support

# ========== Fix Caddy Repo Prerequisite ==========
fix_caddy_repo

# ========== Install MongoDB Prerequisite ==========
install_mongodb

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

# ========== Download and Replace Installation ==========
download_and_extract_latest_release

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
if id -u hysteria >/dev/null 2>&1; then
    chown hysteria:hysteria "$HYSTERIA_INSTALL_DIR/ca.key" "$HYSTERIA_INSTALL_DIR/ca.crt" 2>/dev/null || true
    chmod 640 "$HYSTERIA_INSTALL_DIR/ca.key" "$HYSTERIA_INSTALL_DIR/ca.crt" 2>/dev/null || true
    chown -R hysteria:hysteria "$HYSTERIA_INSTALL_DIR/core/scripts/telegrambot" 2>/dev/null || true
fi
chmod +x "$HYSTERIA_INSTALL_DIR/core/scripts/hysteria2/kick.py"
chmod +x "$HYSTERIA_INSTALL_DIR/core/scripts/auth/user_auth"
success "Permissions updated."

# ========== Virtual Environment ==========
info "Setting up virtual environment and installing dependencies..."
cd "$HYSTERIA_INSTALL_DIR"
python3 -m venv "$HYSTERIA_VENV_DIR"
source "$HYSTERIA_VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install -r requirements.txt >/dev/null
success "Python environment ready."

# ========== Data Migration ==========
migrate_json_to_mongo

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
        info "Attempting to restart $SERVICE..."
        systemctl enable "$SERVICE" &>/dev/null || warn "Could not enable $SERVICE. It might not exist."
        systemctl restart "$SERVICE"
        sleep 2
        if systemctl is-active --quiet "$SERVICE"; then
            success "$SERVICE restarted successfully and is active."
        else
            warn "$SERVICE failed to restart or is not active."
            warn "Showing last 5 log entries for $SERVICE:"
            journalctl -u "$SERVICE" -n 5 --no-pager
        fi
    done
fi

# ========== Final Check ==========
if systemctl is-active --quiet hysteria-server.service; then
    success "🎉 Upgrade completed successfully!"
else
    warn "⚠️ hysteria-server.service is not active. Check logs if needed."
fi

# ========== Launch Menu ==========
info "Upgrade process finished. Launching menu..."
cd "$HYSTERIA_INSTALL_DIR"
chmod +x menu.sh

# ========== Cleanup ==========
info "Cleaning up upgrade lock file..."
rm -f /tmp/hysteria_upgrade.lock
success "Upgrade lock file removed."

./menu.sh
