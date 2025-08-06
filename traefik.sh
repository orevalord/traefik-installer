#!/bin/bash

# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Functions ---

# Check if script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root (use sudo).${NC}"
        exit 1
    fi
}

# Check distribution and version
check_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo -e "${RED}Could not determine distribution. /etc/os-release not found.${NC}"
        exit 1
    fi

    if [[ "$OS" == "debian" && "$VER" == "12" ]]; then
        echo -e "${GREEN}Debian 12 detected. Continuing...${NC}"
    elif [[ "$OS" == "ubuntu" && "$(echo "$VER >= 20.04" | bc)" -eq 1 ]]; then
        echo -e "${GREEN}Ubuntu $VER detected. Continuing...${NC}"
    else
        echo -e "${RED}Error: This script is intended only for Debian 12 or Ubuntu 20.04 and newer.${NC}"
        echo "Your system: $PRETTY_NAME"
        exit 1
    fi
}

# Check for required utilities and install missing ones
check_dependencies() {
    local missing_deps=()
    for cmd in curl tar jq bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}Installing missing dependencies: ${missing_deps[*]}...${NC}"
        apt-get update
        apt-get install -y "${missing_deps[@]}"
        echo -e "${GREEN}All dependencies installed.${NC}"
    fi
}

# Create user and directories
setup_user_and_dirs() {
    echo -e "${YELLOW}Creating user 'traefik' and directories...${NC}"
    if ! getent group traefik >/dev/null; then
        groupadd --system traefik
    fi
    if ! id -u traefik >/dev/null 2>&1; then
        useradd --system -g traefik -d /etc/traefik -s /bin/false traefik
    fi

    mkdir -p /etc/traefik
    touch /etc/traefik/acme.json
    chmod 600 /etc/traefik/acme.json
    chown -R traefik:traefik /etc/traefik
    echo -e "${GREEN}User and directories created successfully.${NC}"
}

# Download and install the Traefik binary
download_and_install_binary() {
    echo -e "${YELLOW}Searching for the latest Traefik version...${NC}"
    local LATEST_URL
    LATEST_URL=$(curl -sL "https://api.github.com/repos/traefik/traefik/releases/latest" | jq -r '.assets[] | select(.name | contains("linux_amd64.tar.gz")) | .browser_download_url')

    if [ -z "$LATEST_URL" ]; then
        echo -e "${RED}Failed to get the download URL for the latest Traefik version.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Downloading Traefik from ${LATEST_URL}...${NC}"
    curl -sL "$LATEST_URL" -o /tmp/traefik.tar.gz

    echo -e "${YELLOW}Unpacking and installing the binary to /usr/local/bin...${NC}"
    tar -xzf /tmp/traefik.tar.gz -C /tmp/
    mv /tmp/traefik /usr/local/bin/traefik
    chmod +x /usr/local/bin/traefik
    rm /tmp/traefik.tar.gz

    echo -e "${GREEN}Traefik installed successfully.${NC}"
    /usr/local/bin/traefik version
}

# Create the static configuration file
create_static_config() {
    echo -e "${YELLOW}Creating static configuration file /etc/traefik/traefik.yml...${NC}"
    cat <<EOF > /etc/traefik/traefik.yml
# --- traefik.yml ---
# Traefik Static Configuration

# EntryPoints (ports Traefik listens to)
entryPoints:
    web:
        address: ":80"
    websecure:
        address: ":443"

# Configuration Providers
providers:
    file:
        filename: "/etc/traefik/dynamic_conf.yml"
        watch: true

# Log Configuration
log:
    level: "INFO" # Levels: DEBUG, INFO, WARN, ERROR
    filePath: "/etc/traefik/traefik.log"

accessLog:
    filePath: "/etc/traefik/access.log"

# --- Let's Encrypt SSL Configuration ---
# To enable automatic SSL certificates:
# 1. Make sure your domain (e.g., sub1.yourdomain.com) points to this server's IP address.
# 2. In the dynamic_conf.yml file, for each router you want to use HTTPS:
#    - Change the entryPoint from 'web' to 'websecure'
#    - Add tls like router-app2 example
# 3. Restart Traefik: systemctl restart traefik

certificatesResolvers:
  myresolver:
    acme:
      email: "your-email@example.com" #Important: Change to your actual email!
      storage: "/etc/traefik/acme.json"
      httpChallenge:
        entryPoint: web
EOF
    chown traefik:traefik /etc/traefik/traefik.yml
    touch /etc/traefik/traefik.log /etc/traefik/access.log
    chown traefik:traefik /etc/traefik/traefik.log /etc/traefik/access.log
    echo -e "${GREEN}Static config created.${NC}"
}

# Create the dynamic configuration file with examples
create_dynamic_config() {
    echo -e "${YELLOW}Creating dynamic configuration file /etc/traefik/dynamic_conf.yml...${NC}"
    cat <<EOF > /etc/traefik/dynamic_conf.yml
# --- dynamic_conf.yml ---
# Dynamic Configuration (routers, services, etc.)

http:
  routers:
    router-app1:
      rule: "Host(\`sub1.yourdomain.com\`)"
      service: service-app1
      entryPoints:
        - web

    # router-app2:
    #   rule: "Host(\`sub2.yourdomain.com\`)"
    #   service: service-app2
    #   entryPoints:
    #     - websecure
    #   tls: 
    #     certResolver: myresolver

  services:
    service-app1:
      loadBalancer:
        servers:
          - url: "http://10.0.0.2:8000"

    # service-app2:
    #   loadBalancer:
    #     servers:
    #       - url: "http://10.0.0.2:8001"
EOF
    chown traefik:traefik /etc/traefik/dynamic_conf.yml
    echo -e "${GREEN}Dynamic config with examples created.${NC}"
    echo -e "${YELLOW}Remember to replace sub1.yourdomain.com, sub2.yourdomain.com, and traefik.yourdomain.com with your actual domains!${NC}"
}

# Setup dashboard and authentication
setup_dashboard_auth() {
    while true; do
        read -rp "Enable Traefik dashboard? [Y/n]: " dash_enable
        case "$dash_enable" in
            [Yy]* )
                # Insert dashboard block into static config after accessLog
                awk '
                    BEGIN {added=0}
                    /^accessLog:/ {
                        print
                        getline
                        print
                        if (!added) {
                            print "api:"
                            print "  dashboard: true"
                            print "  insecure: false"
                            added=1
                        }
                        next
                    }
                    {print}
                ' /etc/traefik/traefik.yml > /etc/traefik/traefik.yml.tmp && mv /etc/traefik/traefik.yml.tmp /etc/traefik/traefik.yml

                # Add dashboard routers to dynamic config for both /dashboard and /dashboard/
                sed -i '/^  routers:/a \    dashboard:\n      rule: "PathPrefix(`/dashboard/`)"\n      service: "api@internal"\n      entryPoints:\n        - web\n    dashboard-api:\n      rule: "PathPrefix(`/api`)"\n      service: "api@internal"\n      entryPoints:\n        - web' /etc/traefik/dynamic_conf.yml

                while true; do
                    read -rp "Enable password protection for the dashboard? [Y/n]: " choice
                    case "$choice" in
                        [Yy]* )
                            local DASH_USER="traefik"
                            echo "Dashboard username will be: ${DASH_USER}"
                            while true; do
                                read -rp "Enter password for '$DASH_USER': " DASH_PASS
                                read -rp "Confirm password: " DASH_PASS_CONFIRM
                                if [ -n "$DASH_PASS" ] && [ "$DASH_PASS" = "$DASH_PASS_CONFIRM" ]; then
                                    # Convert password to {SHA} hash
                                    DASH_HASH=$(printf "%s" "$DASH_PASS" | openssl sha1 -binary | base64)
                                    DASH_HASH="{SHA}$DASH_HASH"
                                    break
                                else
                                    echo -e "${RED}Passwords do not match or empty. Please try again.${NC}"
                                fi
                            done

                            # Add middleware block with user:hash format
                            echo -e "\n  middlewares:\n    auth:\n      basicAuth:\n        users:\n          - \"traefik:${DASH_HASH}\"" >> /etc/traefik/dynamic_conf.yml
                            # Apply the middleware to the dashboard routers
                            sed -i '/^    dashboard:/a \      middlewares:\n        - auth' /etc/traefik/dynamic_conf.yml
                            sed -i '/^    dashboard-api:/a \      middlewares:\n        - auth' /etc/traefik/dynamic_conf.yml

                            echo -e "${GREEN}Password protection for the dashboard is enabled.${NC}"
                            break
                            ;;
                        [Nn]* )
                            echo -e "${YELLOW}Dashboard will remain without a password. Access will be open.${NC}"
                            break
                            ;;
                        * ) echo "Please enter 'y' or 'n'."
                            ;;
                    esac
                done
                break
                ;;
            [Nn]* )
                # Remove dashboard from static config if present
                sed -i '/^api:/,/^$/d' /etc/traefik/traefik.yml
                # Remove dashboard router from dynamic config if present
                sed -i '/^    api:/,/^$/d' /etc/traefik/dynamic_conf.yml
                # Remove dashboard middleware if present
                sed -i '/^  middlewares:/,/^$/d' /etc/traefik/dynamic_conf.yml
                echo -e "${YELLOW}Dashboard will be disabled.${NC}"
                break
                ;;
            * ) echo "Please enter 'y' or 'n'.";;
        esac
    done
}

# Create and start the systemd service
create_systemd_service() {
    echo -e "${YELLOW}Creating systemd service...${NC}"
    cat <<EOF > /etc/systemd/system/traefik.service
[Unit]
Description=Traefik Ingress Controller
After=network.target

[Service]
User=traefik
Group=traefik
ExecStart=/usr/local/bin/traefik --configfile=/etc/traefik/traefik.yml --global.sendAnonymousUsage=false
Restart=on-failure

# Allow binding to ports below 1024 without root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${YELLOW}Reloading systemd daemon and starting Traefik...${NC}"
    systemctl daemon-reload
    systemctl enable --now traefik

    # A short pause to allow the service to start
    sleep 2
    systemctl status traefik --no-pager
    echo -e "${GREEN}Traefik service created and started.${NC}"
}


# --- Install and Uninstall Functions ---

install_traefik() {
    echo -e "${GREEN}--- Starting Traefik Installation ---${NC}"
    check_dependencies
    check_distro
    setup_user_and_dirs
    download_and_install_binary
    create_static_config
    create_dynamic_config
    setup_dashboard_auth
    create_systemd_service
    echo -e "${GREEN}--- Traefik Installation Complete! ---${NC}"
    echo "To check the logs, use: journalctl -u traefik -f"
}

uninstall_traefik() {
    echo -e "${RED}--- Starting Traefik Uninstallation ---${NC}"
    read -rp "Are you sure you want to COMPLETELY remove Traefik, including configs and user? [y/N]: " choice
    case "$choice" in
        [Yy]* )
            echo -e "${YELLOW}Stopping and disabling Traefik service...${NC}"
            systemctl stop traefik &>/dev/null || true
            systemctl disable traefik &>/dev/null || true

            echo -e "${YELLOW}Removing service files...${NC}"
            rm -f /etc/systemd/system/traefik.service
            systemctl daemon-reload

            echo -e "${YELLOW}Removing Traefik binary...${NC}"
            rm -f /usr/local/bin/traefik

            echo -e "${YELLOW}Removing configuration files and logs...${NC}"
            rm -rf /etc/traefik
            rm -rf /var/log/traefik

            echo -e "${YELLOW}Removing user and group 'traefik'...${NC}"
            userdel traefik &>/dev/null || true
            groupdel traefik &>/dev/null || true

            echo -e "${GREEN}Traefik has been completely removed from the system.${NC}"
            ;;
        * )
            echo -e "${YELLOW}Uninstall cancelled.${NC}"
            ;;
    esac
}

# --- Main script logic ---

main() {
    check_root

    case "$1" in
        install)
            install_traefik
            ;;
        uninstall)
            uninstall_traefik
            ;;
        *)
            echo "Usage: $0 {install|uninstall}"
            exit 1
            ;;
    esac
}

# Run the main function with provided arguments
main "$@"