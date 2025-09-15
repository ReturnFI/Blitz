#!/bin/bash

source /etc/hysteria/core/scripts/path.sh

# --- Configuration ---
SERVICE_NAME="hysteria-ip-limit.service"
DB_NAME="blitz_panel"
CONNECTIONS_COLLECTION="active_connections"

# Load configurations from .configs.env
if [ -f "$CONFIG_ENV" ]; then
  source "$CONFIG_ENV"
  BLOCK_DURATION="${BLOCK_DURATION:-60}" # Default to 60 seconds
  MAX_IPS="${MAX_IPS:-1}"               # Default to 1 IP

  grep -q "^BLOCK_DURATION=" "$CONFIG_ENV" || echo -e "\nBLOCK_DURATION=$BLOCK_DURATION" >> "$CONFIG_ENV"
  grep -q "^MAX_IPS=" "$CONFIG_ENV" || echo "MAX_IPS=$MAX_IPS" >> "$CONFIG_ENV"
else
  echo -e "BLOCK_DURATION=240\nMAX_IPS=5" > "$CONFIG_ENV"
fi

# --- Ensure files exist ---
[ ! -f "$BLOCK_LIST" ] && touch "$BLOCK_LIST"

# --- Logging function ---
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [$level] $message"
}

# --- Add an IP to the database for a user ---
add_ip_to_db() {
    local username="$1"
    local ip_address="$2"
    
    mongosh "$DB_NAME" --quiet --eval "
        db.getCollection('$CONNECTIONS_COLLECTION').updateOne(
            { _id: '$username' },
            { \$addToSet: { ips: '$ip_address' } },
            { upsert: true }
        );
    "
    log_message "INFO" "DB Update: Added $ip_address for user $username"
}

# --- Remove an IP from the database for a user ---
remove_ip_from_db() {
    local username="$1"
    local ip_address="$2"
    
    mongosh "$DB_NAME" --quiet --eval "
        db.getCollection('$CONNECTIONS_COLLECTION').updateOne(
            { _id: '$username' },
            { \$pull: { ips: '$ip_address' } }
        );
        db.getCollection('$CONNECTIONS_COLLECTION').deleteMany(
            { _id: '$username', ips: { \$size: 0 } }
        );
    "
    log_message "INFO" "DB Update: Removed $ip_address for user $username"
}

# --- Block an IP using iptables and track it ---
block_ip() {
    local ip_address="$1"
    local username="$2"
    local unblock_time=$(( $(date +%s) + BLOCK_DURATION ))

    if iptables -C INPUT -s "$ip_address" -j DROP 2>/dev/null; then
        log_message "INFO" "IP $ip_address is already blocked"
        return
    fi

    iptables -I INPUT -s "$ip_address" -j DROP
    echo "$ip_address,$username,$unblock_time" >> "$BLOCK_LIST"
    log_message "WARN" "Blocked IP $ip_address for user $username for $BLOCK_DURATION seconds"
}

# --- Explicitly unblock an IP using iptables ---
unblock_ip() {
    local ip_address="$1"

    if iptables -C INPUT -s "$ip_address" -j DROP 2>/dev/null; then
        iptables -D INPUT -s "$ip_address" -j DROP
        log_message "INFO" "Unblocked IP $ip_address"
    fi
    sed -i "/$ip_address,/d" "$BLOCK_LIST"
}

# --- Block all IPs for a user ---
block_all_user_ips() {
    local username="$1"
    
    local ips_json
    ips_json=$(mongosh "$DB_NAME" --quiet --eval "
        JSON.stringify(db.getCollection('$CONNECTIONS_COLLECTION').findOne({_id: '$username'}, {_id: 0, ips: 1}))
    ")

    if [[ -z "$ips_json" || "$ips_json" == "null" ]]; then
        log_message "INFO" "No IPs to block for user $username"
        return
    fi
    
    local ips
    readarray -t ips < <(echo "$ips_json" | jq -r '.ips[]')
    
    for ip in "${ips[@]}"; do
        if [[ -n "$ip" ]]; then
            block_ip "$ip" "$username"
        fi
    done

    log_message "WARN" "User $username has been completely blocked for $BLOCK_DURATION seconds"
}

# --- Check for and unblock expired IPs ---
check_expired_blocks() {
    local current_time=$(date +%s)
    local ip username expiry

    while IFS=, read -r ip username expiry || [ -n "$ip" ]; do
        if [[ -n "$ip" && -n "$expiry" ]]; then
            if (( current_time >= expiry )); then
                unblock_ip "$ip"
                log_message "INFO" "Auto-unblocked IP $ip for user $username (block expired)"
            fi
        fi
    done < "$BLOCK_LIST"
}

# --- Check if a user has exceeded the IP limit ---
check_ip_limit() {
    local username="$1"

    local is_unlimited
    is_unlimited=$(mongosh "$DB_NAME" --quiet --eval "
        db.users.findOne({_id: '$username'}, {_id: 0, unlimited_user: 1})?.unlimited_user || false;
    ")

    if [ "$is_unlimited" == "true" ]; then
        log_message "INFO" "User $username is exempt from IP limit. Skipping check."
        return
    fi
    
    local ip_count
    ip_count=$(mongosh "$DB_NAME" --quiet --eval "
        db.getCollection('$CONNECTIONS_COLLECTION').findOne({_id: '$username'})?.ips?.length || 0;
    ")

    if (( ip_count > MAX_IPS )); then
        log_message "WARN" "User $username has $ip_count IPs (max: $MAX_IPS) - blocking all IPs"
        block_all_user_ips "$username"
    fi
}

# --- Parse log lines for connections and disconnections ---
parse_log_line() {
    local log_line="$1"
    local ip_address
    local username

    ip_address=$(echo "$log_line" | grep -oP '"addr": "([^:]+)' | cut -d'"' -f4)
    username=$(echo "$log_line" | grep -oP '"id": "([^">]+)' | cut -d'"' -f4)

    if [[ -n "$username" && -n "$ip_address" ]]; then
        if echo "$log_line" | grep -q "client connected"; then
            if grep -q "^$ip_address," "$BLOCK_LIST"; then
                log_message "WARN" "Rejected connection from blocked IP $ip_address for user $username"
                if ! iptables -C INPUT -s "$ip_address" -j DROP 2>/dev/null; then
                    iptables -I INPUT -s "$ip_address" -j DROP
                fi
            else
                add_ip_to_db "$username" "$ip_address"
                check_ip_limit "$username"
            fi
        elif echo "$log_line" | grep -q "client disconnected"; then
            remove_ip_from_db "$username" "$ip_address"
        fi
    fi
}

# --- Install Systemd Service ---
install_service() {
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Hysteria2 IP Limiter (MongoDB version)
After=network.target hysteria-server.service mongod.service
Requires=hysteria-server.service mongod.service

[Service]
Type=simple
ExecStart=/bin/bash ${SCRIPT_PATH} run
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}
    log_message "INFO" "IP Limiter service started"
}

# --- Uninstall Systemd Service ---
uninstall_service() {
    systemctl stop ${SERVICE_NAME} 2>/dev/null
    systemctl disable ${SERVICE_NAME} 2>/dev/null
    rm -f /etc/systemd/system/${SERVICE_NAME}
    systemctl daemon-reload
    log_message "INFO" "IP Limiter service stopped and removed"
}

# --- Change Configuration ---
change_config() {
    local new_block_duration="$1"
    local new_max_ips="$2"

    if [[ -n "$new_block_duration" ]]; then
      if ! [[ "$new_block_duration" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid block duration: '$new_block_duration'. Must be a number."
        return 1
      fi
      sed -i "s/^BLOCK_DURATION=.*/BLOCK_DURATION=$new_block_duration/" "$CONFIG_ENV"
      BLOCK_DURATION=$new_block_duration
      log_message "INFO" "Block duration updated to $BLOCK_DURATION seconds"
    fi

    if [[ -n "$new_max_ips" ]]; then
      if ! [[ "$new_max_ips" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid max IPs: '$new_max_ips'. Must be a number."
        return 1
      fi
      sed -i "s/^MAX_IPS=.*/MAX_IPS=$new_max_ips/" "$CONFIG_ENV"
      MAX_IPS=$new_max_ips
      log_message "INFO" "Max IPs per user updated to $MAX_IPS"
    fi

    if systemctl is-active --quiet ${SERVICE_NAME}; then
      systemctl restart ${SERVICE_NAME}
      log_message "INFO" "IP Limiter service restarted to apply new configuration"
    fi
}

# --- Startup Checks ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root."
    exit 1
fi
if ! command -v mongosh &>/dev/null; then
    log_message "ERROR" "'mongosh' is not installed or not in PATH. This script requires the MongoDB Shell."
    exit 1
fi
if ! command -v jq &>/dev/null; then
    log_message "WARN" "'jq' is not installed. JSON parsing for blocking might fail."
fi

# --- Command execution ---
case "$1" in
    start)
        install_service
        ;;
    stop)
        uninstall_service
        ;;
    config)
        change_config "$2" "$3"
        ;;
    run)
        log_message "INFO" "Monitoring Hysteria connections. Max IPs: $MAX_IPS, Block Duration: $BLOCK_DURATION s"
        log_message "INFO" "--------------------------------------------------------"

        (
            while true; do
                check_expired_blocks
                sleep 10
            done
        ) &
        CHECKER_PID=$!
        
        cleanup() {
            log_message "INFO" "Stopping IP limiter..."
            kill $CHECKER_PID 2>/dev/null
            exit 0
        }
        trap cleanup SIGINT SIGTERM

        journalctl -u hysteria-server.service -f | while read -r line; do
            if echo "$line" | grep -q "client connected\|client disconnected"; then
                parse_log_line "$line"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|config|run} [block_duration] [max_ips]"
        exit 1
        ;;
esac

exit 0