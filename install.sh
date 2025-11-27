#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;94m'
NC='\033[0m'
BOLD='\033[1m'

CHECK_MARK="[✓]"
CROSS_MARK="[✗]"
INFO_MARK="[i]"
WARNING_MARK="[!]"

readonly LOG_FILE="/tmp/.blitz_install_$$.txt"

init_logging() {
    local installer_version=$(cat VERSION)
    cat > "$LOG_FILE" <<EOF
===================================================================
            Blitz Installer $installer_version
===================================================================
Started: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
OS: $(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "Unknown")
===================================================================

EOF
    chmod 600 "$LOG_FILE"
}

log_info() {
    local msg="$1"
    echo -e "${BLUE}${INFO_MARK} $msg ${NC}"
    echo "${INFO_MARK} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}${CHECK_MARK} $msg${NC}"
    echo "${CHECK_MARK} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}${WARNING_MARK} $msg${NC}"
    echo "${WARNING_MARK} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}${CROSS_MARK} $msg${NC}" >&2
    echo "${CROSS_MARK} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
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
        . /etc/os-release
        os_name=$(echo "$ID")
        os_version=$(echo "$VERSION_ID" | awk -F '.' '{print $1}')
    else
        log_error "Unsupported OS or unable to determine OS version."
        exit 1
    fi

    if [[ "$os_name" == "ubuntu" && "$os_version" -ge 22 ]] ||
       [[ "$os_name" == "debian" && "$os_version" -ge 12 ]]; then
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
    log_info "Log File is ${LOG_FILE}"
    init_logging

    check_root
    check_os_version
    install_packages
    download_and_extract_release
    setup_python_env
    add_alias

    source ~/.bashrc &> /dev/null || true

    local i=0
    echo ""
    while [ $i -lt 3 ]; do
        echo -ne "\r${YELLOW}Starting Blitz in ${RED}$((3-i)) seconds...${NC}"
        sleep 1
        ((i++))
    done

    run_menu
}

main
