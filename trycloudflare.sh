#!/usr/bin/env bash

# Ensure script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "[-] This script requires Bash. Please run it with: bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Color Palette (High Contrast Cyberpunk)
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
RESET='\033[0m'
BOLD='\033[1m'

# Smooth & Minimalist Progress Bar
show_progress() {
    local task_name="$1"
    local steps=40
    echo -e "${CYAN}[*] ${task_name}...${RESET}"
    for ((i=1; i<=steps; i++)); do
        local filled=$((i * 20 / steps))
        local empty=$((20 - filled))
        local bar=""
        local pad=""
        for ((j=0; j<filled; j++)); do bar+="█"; done
        for ((j=0; j<empty; j++)); do pad+="░"; done
        printf "\r${CYAN} [%s%s] %3d%%${RESET}" "$bar" "$pad" $((i * 5))
        sleep 0.01
    done
    echo -e "\n${GREEN}[✔] Success!${RESET}\n"
}

# Smart OS Detection & Silent Installation
system_init() {
    clear
    echo -e "${CYAN}=== SYSTEM CHECK ===${RESET}"

    local skip_install=false

    if command -v apt-get &> /dev/null; then
        local missing=0
        for pkg in curl nodejs npm procps psmisc neofetch; do
            if ! dpkg -s "$pkg" &> /dev/null; then missing=1; break; fi
        done
        if [ $missing -eq 0 ] && command -v node &> /dev/null && [[ "$(node -v 2>/dev/null)" == v22* ]]; then
            skip_install=true
        fi

    elif command -v apk &> /dev/null; then
        local missing=0
        for pkg in curl nodejs npm procps psmisc neofetch bash; do
            if ! apk info -e "$pkg" &> /dev/null; then missing=1; break; fi
        done
        if [ $missing -eq 0 ] && command -v node &> /dev/null && [[ "$(node -v 2>/dev/null)" == v22* ]]; then
            skip_install=true
        fi

    elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
        local PKG_MGR="yum"
        command -v dnf &> /dev/null && PKG_MGR="dnf"
        local missing=0
        for pkg in curl nodejs npm procps-ng psmisc neofetch; do
            if ! rpm -q "$pkg" &> /dev/null; then missing=1; break; fi
        done
        if [ $missing -eq 0 ] && command -v node &> /dev/null && [[ "$(node -v 2>/dev/null)" == v22* ]]; then
            skip_install=true
        fi
    fi

    if [ "$skip_install" = true ]; then
        echo -e "${GREEN}[✔] Environment ready. Skipping setup.${RESET}"
        sleep 0.8
    else
        echo -e "${YELLOW}[!] Setting up dependencies...${RESET}"
        
        if command -v apt-get &> /dev/null; then
            show_progress "Updating Repositories"
            apt-get update -y > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps psmisc neofetch; do
                if ! dpkg -s "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Packages"
                apt-get install -y "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi

            if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
                show_progress "Installing Node.js 22"
                curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
                apt-get install -y nodejs > /dev/null 2>&1
            fi

        elif command -v apk &> /dev/null; then
            show_progress "Updating Repositories"
            apk update > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps psmisc neofetch bash; do
                if ! apk info -e "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Packages"
                apk add --no-cache "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi

        elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
            PKG_MGR="yum"
            command -v dnf &> /dev/null && PKG_MGR="dnf"
            show_progress "Updating Repositories"
            $PKG_MGR update -y > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps-ng psmisc neofetch; do
                if ! rpm -q "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Packages"
                $PKG_MGR install -y "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi
        fi
    fi

    if command -v neofetch &> /dev/null; then
        echo -e "${MAGENTA}"
        neofetch --off
        echo -e "${RESET}"
        sleep 1
    fi
}

get_sys_info() {
    UPTIME_VAL=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    
    if [ -f /etc/os-release ]; then
        OS_VAL=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_VAL=$(uname -s 2>/dev/null || echo "Linux")
    fi

    PM2_COUNT=0
    if command -v pm2 &> /dev/null; then
        PM2_RAW=$(pm2 list --no-color 2>/dev/null | grep -c "online" || echo "0")
        PM2_COUNT=$(echo "$PM2_RAW" | tr -d '[:space:]')
        [[ ! "$PM2_COUNT" =~ ^[0-9]+$ ]] && PM2_COUNT=0
    fi

    if [ "$PM2_COUNT" -gt 0 ]; then
        PM2_VAL="${GREEN}${BOLD}Active (${PM2_COUNT})${RESET}"
    else
        PM2_VAL="${RED}${BOLD}Inactive${RESET}"
    fi

    CF_LINK=""
    if command -v pm2 &> /dev/null; then
        CF_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
    fi

    if [ -n "$CF_LINK" ]; then
        CF_STATUS="${GREEN}${BOLD}Running${RESET}"
    else
        CF_STATUS="${RED}${BOLD}Stopped${RESET}"
    fi
}

# Clean, Responsive, and Beautiful Box Banner
show_banner() {
    clear
    get_sys_info
    echo -e "${CYAN}┌────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${BLUE} │       ⚡ CLOUDFLARE TUNNEL v3.0 ⚡       │${RESET}"
    echo -e "${MAGENTA} │            By Mr. Zetrix               │${RESET}"
    echo -e "${CYAN}├────────────────────────────────────────┤${RESET}"
    echo -e "${YELLOW} │ Uptime        :${RESET} ${GREEN}${UPTIME_VAL}${RESET}"
    echo -e "${YELLOW} │ OS            :${RESET} ${CYAN}${OS_VAL}${RESET}"
    echo -e "${YELLOW} │ PM2 Status    :${RESET} ${PM2_VAL}"
    echo -e "${YELLOW} │ Tunnel Status :${RESET} ${CF_STATUS}"
    echo -e "${CYAN}└────────────────────────────────────────┘${RESET}"
}

exit_anim() {
    echo -e "${YELLOW}[*] Goodbye!${RESET}"; sleep 0.4
    exit 0
}

# Run Initialization
system_init

while true; do
    show_banner
    echo -e "${WHITE}[ A ]${RESET} Start Tunnel"
    echo -e "${WHITE}[ B ]${RESET} Uninstall / Clean"
    echo -e "${WHITE}[ C ]${RESET} Tunnel Status & Link"
    echo -e "${WHITE}[ E ]${RESET} Exit"
    echo -e "${CYAN}──────────────────────────────────────────${RESET}"
    read -p "Select option [A/B/C/E]: " CHOICE

    case "${CHOICE,,}" in
        a)
            clear
            echo -e "${CYAN}=== TUNNEL CONFIGURATION ===${RESET}"
            
            read -p "PM2 Name [cf-tunnel]: " PM2_NAME
            PM2_NAME=${PM2_NAME:-cf-tunnel}

            read -p "Protocol (http/https) [http]: " PROTOCOL
            PROTOCOL=${PROTOCOL:-http}
            PROTOCOL_LOWER=$(echo "$PROTOCOL" | tr '[:upper:]' '[:lower:]')

            read -p "Port / Target [3000]: " TUNNEL_TARGET
            TUNNEL_TARGET=${TUNNEL_TARGET:-3000}
            
            if [[ "$TUNNEL_TARGET" =~ ^[0-9]+$ ]]; then
                TUNNEL_TARGET="localhost:$TUNNEL_TARGET"
            fi

            NOTLS_ARG=""
            if [ "$PROTOCOL_LOWER" = "https" ]; then
                read -p "NoTLSVerify [T/F] [T]: " NOTLS_CHOICE
                NOTLS_CHOICE=${NOTLS_CHOICE:-T}
                if [[ "${NOTLS_CHOICE,,}" == "t" ]]; then
                    NOTLS_ARG="--no-tls-verify"
                fi
            fi

            echo -e "\n${CYAN}[*] Checking PM2 Manager...${RESET}"
            if ! command -v pm2 &> /dev/null; then
                show_progress "Installing PM2"
                npm install -g pm2 > /dev/null 2>&1
            else
                echo -e "${GREEN}[✔] PM2 is active.${RESET}"
            fi

            show_progress "Downloading Tunnel Binary"
            pm2 delete "$PM2_NAME" 2>/dev/null
            killall cloudflared 2>/dev/null
            rm -f /usr/local/bin/cloudflared
            
            ARCH=$(uname -m)
            if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
                CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            else
                CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            fi

            curl -L --output /usr/local/bin/cloudflared "$CF_URL" > /dev/null 2>&1
            chmod +x /usr/local/bin/cloudflared

            show_progress "Starting Background Tunnel"
            if [ -n "$NOTLS_ARG" ]; then
                pm2 start /usr/local/bin/cloudflared --name "${PM2_NAME}" -- --url ${PROTOCOL}://${TUNNEL_TARGET} ${NOTLS_ARG} > /dev/null 2>&1
            else
                pm2 start /usr/local/bin/cloudflared --name "${PM2_NAME}" -- --url ${PROTOCOL}://${TUNNEL_TARGET} > /dev/null 2>&1
            fi
            pm2 save > /dev/null 2>&1

            echo -e "${CYAN}[*] Fetching live tunnel link...${RESET}"
            TUNNEL_LINK=""
            for i in {1..10}; do
                sleep 1
                TUNNEL_LINK=$(pm2 logs "${PM2_NAME}" --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
                if [ -n "$TUNNEL_LINK" ]; then
                    break
                fi
            done

            echo -e "\n${GREEN}──────────────────────────────────────────${RESET}"
            echo -e "${BOLD}${GREEN}             ✅ SUCCESS!                  ${RESET}"
            echo -e "${GREEN}──────────────────────────────────────────${RESET}"
            if [ -n "$TUNNEL_LINK" ]; then
                echo -e "${WHITE} Name   : ${CYAN}${PM2_NAME}${RESET}"
                echo -e "${WHITE} Target : ${CYAN}${TUNNEL_TARGET}${RESET}"
                echo -e "${WHITE} Link   : ${CYAN}${BOLD}${TUNNEL_LINK}${RESET}"
            else
                echo -e "${YELLOW}[!] Check Option C for your live link.${RESET}"
            fi
            echo -e "${GREEN}──────────────────────────────────────────${RESET}"
            read -p "Press [Enter] to continue..."
            ;;
        b)
            clear
            echo -e "${RED}[!] Uninstalling Tunnel...${RESET}"
            read -p "PM2 Name to remove [cf-tunnel]: " DEL_NAME
            DEL_NAME=${DEL_NAME:-cf-tunnel}
            pm2 delete "$DEL_NAME" 2>/dev/null
            killall cloudflared 2>/dev/null
            rm -f /usr/local/bin/cloudflared
            pm2 save > /dev/null 2>&1
            echo -e "${GREEN}[✔] Cleaned successfully!${RESET}"
            read -p "Press [Enter] to continue..."
            ;;
        c)
            clear
            echo -e "${CYAN}=== TUNNEL STATUS & LOGS ===${RESET}"
            pm2 status
            echo -e "\n${MAGENTA}Active Link:${RESET}"
            ACTIVE_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
            if [ -n "$ACTIVE_LINK" ]; then
                echo -e "${WHITE} Link ====> ${CYAN}${BOLD}${ACTIVE_LINK}${RESET}"
            else
                echo -e "${YELLOW}[!] No active link found.${RESET}"
            fi
            echo -e "${CYAN}──────────────────────────────────────────${RESET}"
            read -p "Press [Enter] to exit"
            ;;
        e)
            exit_anim
            ;;
        *)
            echo -e "${RED}[!] Invalid option. Choose A, B, C, or E.${RESET}"
            sleep 1
            ;;
    esac
done
