#!/bin/bash
source /etc/hysteria/core/scripts/utils.sh
define_colors

install_dependencies() {
   # Update system
    sudo apt update -y > /dev/null 2>&1

    # Install dependencies
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null 2>&1

    # Add Caddy repository
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | sudo tee /etc/apt/trusted.gpg.d/caddy.asc > /dev/null 2>&1
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/caddy.asc] https://dl.cloudsmith.io/public/caddy/stable/deb/ubuntu/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null 2>&1

    # Update package index again with Caddy repo
    sudo apt update -y > /dev/null 2>&1

    apt install libnss3-tools > /dev/null 2>&1

    # Install Caddy
    sudo apt install -y caddy
    if [ $? -ne 0 ]; then
        echo -e "${red}Error: Failed to install Caddy. ${NC}"
        exit 1
    fi

    echo -e "${green}Caddy installed successfully. ${NC}"
}
update_env_file() {
    local domain=$1
    local port=$2
    local admin_username=$3
    local admin_password=$4
    local expiration_minutes=$5
    local debug=$6

    local api_token=$(openssl rand -hex 32) 
    local root_path=$(openssl rand -hex 16)

    cat <<EOL > /etc/hysteria/core/scripts/webpanel/.env
DEBUG=$debug
DOMAIN=$domain
PORT=$port
ROOT_PATH=$root_path
API_TOKEN=$api_token
ADMIN_USERNAME=$admin_username
ADMIN_PASSWORD=$admin_password
EXPIRATION_MINUTES=$expiration_minutes
EOL
}

update_caddy_file() {
    local config_file="/etc/caddy/Caddyfile"
    
    source /etc/hysteria/core/scripts/webpanel/.env
    
    # Ensure all required variables are set
    if [ -z "$DOMAIN" ] || [ -z "$ROOT_PATH" ] || [ -z "$PORT" ]; then
        echo -e "${red}Error: One or more environment variables are missing.${NC}"
        return 1
    fi

    # Update the Caddyfile without the email directive
    cat <<EOL > "$config_file"
$DOMAIN:$PORT {
    route /$ROOT_PATH/* {
        uri strip_prefix /$ROOT_PATH
        reverse_proxy http://127.0.0.1:8080
    }
}
EOL
}


create_webpanel_service_file() {
    cat <<EOL > /etc/systemd/system/webpanel.service
[Unit]
Description=Hysteria2 Web Panel
After=network.target

[Service]
WorkingDirectory=/etc/hysteria/core/scripts/webpanel
EnvironmentFile=/etc/hysteria/core/scripts/webpanel/.env
ExecStart=/bin/bash -c 'source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/hysteria2_venv/bin/python /etc/hysteria/core/scripts/webpanel/app.py'
#Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOL
}

start_service() {
    local domain=$1
    local port=$2
    local admin_username=$3
    local admin_password=$4
    local expiration_minutes=$5
    local debug=$6

    # MAYBE I WANT TO CHANGE CONFIGS WITHOUT RESTARTING THE SERVICE MYSELF
    # # Check if the services are already active
    # if systemctl is-active --quiet webpanel.service && systemctl is-active --quiet caddy.service; then
    #     echo -e "${green}Hysteria web panel is already running with Caddy.${NC}"
    #     source /etc/hysteria/core/scripts/webpanel/.env
    #     echo -e "${yellow}The web panel is accessible at: http://$domain:$port/$ROOT_PATH${NC}"
    #     return
    # fi

    # Install required dependencies
    install_dependencies

    # Update environment file
    update_env_file "$domain" "$port" "$admin_username" "$admin_password" "$expiration_minutes" "$debug"
    if [ $? -ne 0 ]; then
        echo -e "${red}Error: Failed to update the environment file.${NC}"
        return 1
    fi

    # Create the web panel service file
    create_webpanel_service_file
    if [ $? -ne 0 ]; then
        echo -e "${red}Error: Failed to create the webpanel service file.${NC}"
        return 1
    fi

    # Reload systemd and enable webpanel service
    systemctl daemon-reload
    systemctl enable webpanel.service > /dev/null 2>&1
    systemctl start webpanel.service > /dev/null 2>&1

    # Check if the web panel is running
    if systemctl is-active --quiet webpanel.service; then
        echo -e "${green}Hysteria web panel setup completed. The web panel is running locally on: http://127.0.0.1:8080/${NC}"
    else
        echo -e "${red}Error: Hysteria web panel service failed to start.${NC}"
        return 1
    fi

    # Update Caddy configuration
    update_caddy_file
    if [ $? -ne 0 ]; then
        echo -e "${red}Error: Failed to update the Caddyfile.${NC}"
        return 1
    fi

    # Restart Caddy service
    systemctl restart caddy.service
    if [ $? -ne 0 ]; then
        echo -e "${red}Error: Failed to restart Caddy.${NC}"
        return 1
    fi

    # Check if the web panel is still running after Caddy restart
    if systemctl is-active --quiet webpanel.service; then
        source /etc/hysteria/core/scripts/webpanel/.env
        local webpanel_url="http://$domain:$port/$ROOT_PATH/"
        echo -e "${green}Hysteria web panel is now running. The service is accessible on: $webpanel_url ${NC}"
    else
        echo -e "${red}Error: Hysteria web panel failed to start after Caddy restart.${NC}"
    fi
}

show_webpanel_url() {
    source /etc/hysteria/core/scripts/webpanel/.env
    local webpanel_url="https://$DOMAIN:$PORT/$ROOT_PATH/"
    echo "$webpanel_url"
}

stop_service() {
    echo "Stopping Caddy..."
    systemctl disable caddy.service
    systemctl stop caddy.service
    echo "Caddy stopped."
    
    echo "Stopping Hysteria web panel..."
    systemctl disable webpanel.service
    systemctl stop webpanel.service
    echo "Hysteria web panel stopped."
}

case "$1" in
    start)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${red}Usage: $0 start <DOMAIN> <PORT> ${NC}"
            exit 1
        fi
        start_service "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    stop)
        stop_service
        ;;
    url)
        show_webpanel_url
        ;;
    *)
        echo -e "${red}Usage: $0 {start|stop} <DOMAIN> <PORT> ${NC}"
        exit 1
        ;;
esac


