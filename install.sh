#!/bin/bash

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

log_info() {
    echo -e "${BLUE}${INFO_MARK} ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}${CHECK_MARK} ${1}${NC}"
}

log_warning() {
    echo -e "${YELLOW}${WARNING_MARK} ${1}${NC}"
}

log_error() {
    echo -e "${RED}${CROSS_MARK} ${1}${NC}" >&2
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
        return 0
    else
        log_error "This script is only supported on Ubuntu 22+ or Debian 12+."
        exit 1
    fi
}

install_packages() {
    local REQUIRED_PACKAGES=("jq" "curl" "pwgen" "python3" "python3-pip" "python3-venv" "git" "bc" "zip" "cron" "lsof" "golang-go")
    local MISSING_PACKAGES=()
    
    log_info "Checking required packages..."
    
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$package" &> /dev/null; then
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
}

clone_repository() {
    log_info "Cloning Blitz repository..."
    
    if [ -d "/etc/hysteria" ]; then
        log_warning "Directory /etc/hysteria already exists."
        read -p "Do you want to remove it and clone again? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /etc/hysteria
        else
            log_info "Using existing directory."
            return 0
        fi
    fi
    
    if git clone -b nodb https://github.com/ReturnFI/Blitz /etc/hysteria &> /dev/null; then
        log_success "Repository cloned successfully"
    else
        log_error "Failed to clone repository"
        exit 1
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
    
    check_root
    check_os_version
    install_packages
    clone_repository
    setup_python_env
    add_alias
    
    source ~/.bashrc &> /dev/null || true
    
    echo -e "\n${YELLOW}Starting Blitz in 3 seconds...${NC}"
    sleep 3
    
    run_menu
}

main
