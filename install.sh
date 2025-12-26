#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;94m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

CHECK_MARK="[✓]"
CROSS_MARK="[✗]"
INFO_MARK="[i]"
WARNING_MARK="[!]"

LOG_FILE="/tmp/.Blitz_install_$$"

log_init() {
    echo "=================================" > "$LOG_FILE"
    echo "   Log file created at $(date)" >> "$LOG_FILE"
    echo "=================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}${INFO_MARK} ${1}${NC}"
    echo "[INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${CHECK_MARK} ${1}${NC}"
    echo "[ OK ] $1" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}${WARNING_MARK} ${1}${NC}"
    echo "[WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}${CROSS_MARK} ${1}${NC}" >&2
    echo "[ERROR] $1" >> "$LOG_FILE"
}

handle_error() {
    log_error "Error occurred at line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root."
        exit 1
    fi
    log_info "Running with root privileges"
}

check_os_version() {
    local os_name os_version

    log_info "Checking OS compatibility..."
    
    if [ -f /etc/os-release ]; then
        os_name=$(grep '^ID=' /etc/os-release | cut -d= -f2)
        os_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        log_error "Unsupported OS or unable to determine OS version."
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        log_info "Installing bc package..."
        apt update -qq && apt install -y -qq bc
        if [ $? -ne 0 ]; then
            log_error "Failed to install bc package."
            exit 1
        fi
    fi

    if [[ "$os_name" == "ubuntu" && $(echo "$os_version >= 22" | bc) -eq 1 ]] ||
       [[ "$os_name" == "debian" && $(echo "$os_version >= 12" | bc) -eq 1 ]]; then
        log_success "OS check passed: $os_name $os_version"
    else
        log_error "This script is only supported on Ubuntu 22+ or Debian 12+."
        exit 1
    fi
    
    log_info "Checking CPU for AVX support (required for MongoDB)..."
    if grep -q -m1 -o -E 'avx|avx2|avx512' /proc/cpuinfo; then
        log_success "CPU supports AVX instruction set."
    else
        log_error "CPU does not support the required AVX instruction set for MongoDB."
        log_info "For systems without AVX support, you can use the 'nodb' version of the panel."
        log_info "To install it, please run the following command:"
        echo -e "${YELLOW}bash <(curl -sL https://raw.githubusercontent.com/ReturnFI/Blitz/nodb/install.sh)${NC}"
        log_error "Installation aborted."
        exit 1
    fi
}


install_mongodb() {
    log_info "Installing MongoDB..."
    
    if command -v mongod &> /dev/null; then
        log_success "MongoDB is already installed"
        return 0
    fi
    
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
    
    local codename
    codename=$(lsb_release -cs)
    local repo_line=""

    case "$codename" in
        "noble" | "jammy")
            repo_line="deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $codename/mongodb-org/8.0 multiverse"
            ;;
        "bookworm" | "trixie")
            repo_line="deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main"
            ;;
        *)
            log_error "Unsupported OS codename for MongoDB installation: $codename"
            exit 1
            ;;
    esac

    echo "$repo_line" | tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
    
    apt update -qq
    apt install -y -qq mongodb-org
    
    systemctl enable mongod
    systemctl start mongod
    
    if systemctl is-active --quiet mongod; then
        log_success "MongoDB installed and started successfully"
    else
        log_error "MongoDB installation failed or service not running"
        exit 1
    fi
}


install_packages() {
    local REQUIRED_PACKAGES=("jq" "curl" "pwgen" "python3" "python3-pip" "python3-venv" "bc" "zip" "unzip" "lsof" "gnupg" "lsb-release")
    local MISSING_PACKAGES=()
    
    log_info "Checking required packages..."
    
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$package" &> /dev/null && ! dpkg -l | grep -q "^ii.*$package "; then
            MISSING_PACKAGES+=("$package")
        else
            log_success "Package $package is already installed"
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
        apt update -qq || { log_error "Failed to update apt repositories"; exit 1; }
        apt upgrade -y -qq || { log_warning "Failed to upgrade packages, continuing..."; }
        
        for package in "${MISSING_PACKAGES[@]}"; do
            log_info "Installing $package..."
            if apt install -y -qq "$package"; then
                log_success "Installed $package"
            else
                log_error "Failed to install $package"
                exit 1
            fi
        done
    else
        log_success "All required packages are already installed."
    fi
    
    install_mongodb
}

download_and_extract_release() {
    log_info "Downloading and extracting Blitz panel..."

    if [ -d "/etc/hysteria" ]; then
        log_warning "Directory /etc/hysteria already exists."
        read -p "Do you want to remove it and install again? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /etc/hysteria
        else
            log_info "Skipping download. Using existing directory."
            return 0
        fi
    fi

    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    log_info "Detected architecture: $arch"

    local zip_name="Blitz-${arch}.zip"
    local download_url="https://github.com/ReturnFI/Blitz/releases/latest/download/${zip_name}"
    local temp_zip="/tmp/${zip_name}"

    log_info "Downloading from ${download_url}..."
    if curl -sL -o "$temp_zip" "$download_url"; then
        log_success "Download complete."
    else
        log_error "Failed to download the release asset. Please check the URL and your connection."
        exit 1
    fi

    log_info "Extracting to /etc/hysteria..."
    mkdir -p /etc/hysteria
    if unzip -q "$temp_zip" -d /etc/hysteria; then
        log_success "Extracted successfully."
    else
        log_error "Failed to extract the archive."
        exit 1
    fi
    
    rm "$temp_zip"
    log_info "Cleaned up temporary file."
    
    local auth_binary="/etc/hysteria/core/scripts/auth/user_auth"
    if [ -f "$auth_binary" ]; then
        chmod +x "$auth_binary"
        log_success "Set execute permission for auth binary."
    else
        log_warning "Auth binary not found at $auth_binary. The installation might be incomplete."
    fi
}

setup_python_env() {
    log_info "Setting up Python virtual environment..."
    
    cd /etc/hysteria || { log_error "Failed to change to /etc/hysteria directory"; exit 1; }
    
    if python3 -m venv hysteria2_venv &> /dev/null; then
        log_success "Created Python virtual environment"
    else
        log_error "Failed to create Python virtual environment"
        exit 1
    fi
    
    source /etc/hysteria/hysteria2_venv/bin/activate || { log_error "Failed to activate virtual environment"; exit 1; }
    
    log_info "Installing Python requirements..."
    if pip install -r requirements.txt &> /dev/null; then
        log_success "Installed Python requirements"
    else
        log_error "Failed to install Python requirements"
        exit 1
    fi
}

add_alias() {
    log_info "Adding 'hys2' alias to .bashrc..."
    
    if ! grep -q "alias hys2='source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/menu.sh'" ~/.bashrc; then
        echo "alias hys2='source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/menu.sh'" >> ~/.bashrc
        log_success "Added 'hys2' alias to .bashrc"
    else
        log_info "Alias 'hys2' already exists in .bashrc"
    fi
}

run_menu() {
    log_info "Preparing to run menu..."
    
    cd /etc/hysteria || { log_error "Failed to change to /etc/hysteria directory"; exit 1; }
    chmod +x menu.sh || { log_error "Failed to make menu.sh executable"; exit 1; }
    
    log_info "Starting menu..."
    echo -e "\n${BOLD}${GREEN}======== Launching Blitz Menu ========${NC}\n"
    ./menu.sh
}

main() {
    echo -e "\n${BOLD}${BLUE}======== Blitz Setup Script ========${NC}\n"
    log_init

    check_root
    check_os_version
    install_packages
    download_and_extract_release
    setup_python_env
    add_alias

    source ~/.bashrc &> /dev/null || true

    echo -e "\n${CYAN}Installation logs can be found at: ${LOG_FILE}${NC}\n"
    echo -e "${CYAN}Press ${YELLOW}${BOLD}ENTER${NC}${CYAN} to continue...${NC}"
    read -r
    echo -e "\n${YELLOW}Starting Blitz in 3 seconds...${NC}"
    for i in {3..1};
    do
        if [ $i -eq 1 ]; then
            echo -ne "${RED}$i second left...${NC}\r"
        else
            echo -ne "${YELLOW}$i seconds left...${NC}\r"
        fi
        sleep 1
    done

    echo -ne "\r\033[KSetup complete! Starting menu!"
    sleep 2
    run_menu
}

main
