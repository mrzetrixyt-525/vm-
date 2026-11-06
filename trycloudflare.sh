#!/usr/bin/env bash

# Shell check guard
if [ -z "$BASH_VERSION" ]; then
    echo "[-] Error: This script requires Bash. Run with: bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Cyberpunk Palette
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
RESET='\033[0m'
BOLD='\033[1m'

# 1-100% Real-time Smooth Progress Animation
show_progress() {
    local task_name="$1"
    local steps=100
    echo -e "${CYAN}Loading: ${task_name}...${RESET}"
    for ((i=1; i<=steps; i++)); do
        local filled=$((i / 5))
        local empty=$((20 - filled))
        
        local bar=""
        local pad=""
        for ((j=0; j<filled; j++)); do bar+="█"; done
        for ((j=0; j<empty; j++)); do pad+="░"; done

        printf "\r${CYAN}[${GREEN}%s${WHITE}%s${CYAN}] ${YELLOW}%3d%%${RESET}" "$bar" "$pad" "$i"
        sleep 0.012
    done
    echo -e "\n${GREEN}[ Info ] ${task_name} Loaded...${RESET}\n"
}

# Smart OS Detection & Package Pre-check Logic
system_init() {
    clear
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${BOLD}${BLUE} 🔍 AUTO OS DETECTION & SYSTEM CHECK ${RESET}"
    echo -e "${CYAN}========= • =========${RESET}"

    local skip_install=true

    if command -v apt-get &> /dev/null; then
        for pkg in curl nodejs npm procps psmisc neofetch; do
            if ! dpkg -s "$pkg" &> /dev/null; then skip_install=false; break; fi
        done
        if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
            skip_install=false
        fi
    elif command -v apk &> /dev/null; then
        for pkg in curl nodejs npm procps psmisc neofetch bash; do
            if ! apk info -e "$pkg" &> /dev/null; then skip_install=false; break; fi
        done
        if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
            skip_install=false
        fi
    elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
        for pkg in curl nodejs npm procps-ng psmisc neofetch; do
            if ! rpm -q "$pkg" &> /dev/null; then skip_install=false; break; fi
        done
        if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
            skip_install=false
        fi
    else
        skip_install=false
    fi

    if [ "$skip_install" = true ]; then
        echo -e "${GREEN}[ Info ] All required packages & Node.js 22 are already installed. Skipping installation!${RESET}"
        sleep 1
    else
        echo -e "${YELLOW}[ Info ] Missing packages or Node.js 22 detected. Setting up environment...${RESET}"
        
        if command -v apt-get &> /dev/null; then
            show_progress "System Repository Update"
            apt-get update -y > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps psmisc neofetch; do
                if ! dpkg -s "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Required Packages"
                apt-get install -y "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi

            if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
                show_progress "Node.js 22 Environment Setup"
                curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
                apt-get install -y nodejs > /dev/null 2>&1
            fi

        elif command -v apk &> /dev/null; then
            show_progress "System Repository Update"
            apk update > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps psmisc neofetch bash; do
                if ! apk info -e "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Required Packages"
                apk add --no-cache "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi

        elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
            local PKG_MGR="yum"
            command -v dnf &> /dev/null && PKG_MGR="dnf"
            show_progress "System Repository Update"
            $PKG_MGR update -y > /dev/null 2>&1

            NEEDED_PKGS=()
            for pkg in curl nodejs npm procps-ng psmisc neofetch; do
                if ! rpm -q "$pkg" &> /dev/null; then NEEDED_PKGS+=("$pkg"); fi
            done

            if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
                show_progress "Installing Required Packages"
                $PKG_MGR install -y "${NEEDED_PKGS[@]}" > /dev/null 2>&1
            fi
        fi
    fi

    # Neofetch startup view (4-second delay)
    if command -v neofetch &> /dev/null; then
        echo -e "${MAGENTA}"
        neofetch --off
        echo -e "${RESET}"
        sleep 4
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
        CF_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -oE 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com|tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
    fi

    if [ -n "$CF_LINK" ]; then
        CF_STATUS="${GREEN}${BOLD}Running${RESET}"
    else
        CF_STATUS="${RED}${BOLD}Stopped${RESET}"
    fi
}

# Cyberpunk ASCII Banner
show_banner() {
    clear
    get_sys_info
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${BOLD}${BLUE} ██████╗  ██████╗ ███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗™${RESET}"
    echo -e "${BOLD}${BLUE} ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝ ${RESET}"
    echo -e "${BOLD}${BLUE} ██████╔╝██║  ███╗██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗ ${RESET}"
    echo -e "${BOLD}${BLUE} ██╔══██╗██║   ██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║ ${RESET}"
    echo -e "${BOLD}${BLUE} ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝██████╔╝███████╗███████║ ${RESET}"
    echo -e "${MAGENTA}           Made By 𝐌ɾ. 𝐙ᥱ𝚝𝚛𝐢xs                 ${RESET}"
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${YELLOW}  Uptime        :${RESET} ${GREEN}${UPTIME_VAL}${RESET}"
    echo -e "${YELLOW}  OS            :${RESET} ${CYAN}${OS_VAL}${RESET}"
    echo -e "${YELLOW}  PM2           :${RESET} ${PM2_VAL}"
    echo -e "${YELLOW}  TryCloudflare :${RESET} ${CF_STATUS}"
    echo -e "${CYAN}========= • =========${RESET}"
}

exit_anim() {
    echo -e "${YELLOW}Good Bye!${RESET}"; sleep 0.5
    exit 0
}

# Run Auto OS Setup On Startup
system_init

while true; do
    show_banner
    echo -e "${WHITE}[ A ]${RESET} Install ( HTTP / HTTPS / TCP Setup )"
    echo -e "${WHITE}[ B ]${RESET} Uninstall ( Remove Tunnel )"
    echo -e "${WHITE}[ C ]${RESET} Tunnel Logs ( Checking Status )"
    echo -e "${WHITE}[ E ]${RESET} Exit"
    echo -e "${CYAN}========= • =========${RESET}"
    read -p "Choose Option [ Info ]: " CHOICE

    case "${CHOICE,,}" in
        a)
            clear
            echo -e "${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} 🚀 CLOUDFLARE TUNNEL SETUP ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            
            read -p "PM2 name [Default: cf-tunnel]: " PM2_NAME
            PM2_NAME=${PM2_NAME:-cf-tunnel}

            read -p "Protocol (http / https / tcp) [Default: http]: " PROTOCOL
            PROTOCOL=${PROTOCOL:-http}
            PROTOCOL_LOWER=$(echo "$PROTOCOL" | tr '[:upper:]' '[:lower:]')

            NOTLS_ARG=""
            REGION_ARG=""
            TUNNEL_TARGET=""

            if [ "$PROTOCOL_LOWER" = "tcp" ]; then
                read -p "Local Port (e.g., 22, 3306, 3000) [Default: 3000]: " LOCAL_PORT
                LOCAL_PORT=${LOCAL_PORT:-3000}
                TUNNEL_TARGET="tcp://localhost:$LOCAL_PORT"

                echo -e "${YELLOW}Select Region:${RESET}"
                echo -e "  [ 1 ] Asia (ap)"
                echo -e "  [ 2 ] Europe (eur)"
                read -p "Choose Region [1/2] [Default: 1]: " REG_CHOICE
                REG_CHOICE=${REG_CHOICE:-1}

                if [ "$REG_CHOICE" = "2" ]; then
                    REGION_ARG="--region eur"
                else
                    REGION_ARG="--region ap"
                fi
            else
                read -p "Tunnel Port (e.g., 3000) [Default: 3000]: " TUNNEL_PORT
                TUNNEL_PORT=${TUNNEL_PORT:-3000}
                TUNNEL_TARGET="${PROTOCOL_LOWER}://localhost:${TUNNEL_PORT}"

                if [ "$PROTOCOL_LOWER" = "https" ]; then
                    read -p "NoTLSVerify [ T/F ] [Default: T]: " NOTLS_CHOICE
                    NOTLS_CHOICE=${NOTLS_CHOICE:-T}
                    if [[ "${NOTLS_CHOICE,,}" == "t" ]]; then
                        NOTLS_ARG="--no-tls-verify"
                    fi
                fi
            fi

            echo -e "\n${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} ⚙️ CHECKING PM2 ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            
            if ! command -v pm2 &> /dev/null; then
                show_progress "Installing PM2"
                npm install -g pm2 > /dev/null 2>&1
            else
                echo -e "${GREEN}[ Info ] PM2 is already active & installed.${RESET}"
            fi

            echo -e "\n${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} 🌐 SETTING UP TUNNEL ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            show_progress "Fetching Cloudflare Tunnel Binary"
            
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

            echo -e "\n${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} 🔄 SETUP 24/7 BACKGROUND ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            show_progress "Starting PM2 Service Persistence"

            CMD_ARGS="--url ${TUNNEL_TARGET}"
            [ -n "$NOTLS_ARG" ] && CMD_ARGS="${CMD_ARGS} ${NOTLS_ARG}"
            [ -n "$REGION_ARG" ] && CMD_ARGS="${CMD_ARGS} ${REGION_ARG}"

            pm2 start /usr/local/bin/cloudflared --name "${PM2_NAME}" -- ${CMD_ARGS} > /dev/null 2>&1
            pm2 save > /dev/null 2>&1

            echo -e "${CYAN}[ Info ] Extracting Tunnel Connection Target...${RESET}"
            TUNNEL_LINK=""
            for i in {1..15}; do
                sleep 1
                if [ "$PROTOCOL_LOWER" = "tcp" ]; then
                    TUNNEL_LINK=$(pm2 logs "${PM2_NAME}" --lines 50 --nostream 2>/dev/null | grep -o 'tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
                else
                    TUNNEL_LINK=$(pm2 logs "${PM2_NAME}" --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
                fi
                if [ -n "$TUNNEL_LINK" ]; then
                    break
                fi
            done

            # Automatic Multi-Environment Clipboard Copy Logic
            AUTO_COPIED=""
            if [ -n "$TUNNEL_LINK" ]; then
                if command -v termux-clipboard-set &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | termux-clipboard-set
                    AUTO_COPIED="(Auto-copied to clipboard!)"
                elif command -v xclip &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | xclip -selection clipboard
                    AUTO_COPIED="(Auto-copied to clipboard!)"
                elif command -v xsel &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | xsel --clipboard --input
                    AUTO_COPIED="(Auto-copied to clipboard!)"
                elif command -v pbcopy &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | pbcopy
                    AUTO_COPIED="(Auto-copied to clipboard!)"
                fi
            fi

            echo -e "\n${GREEN}==========================================${RESET}"
            echo -e "${BOLD}${GREEN} ✅ SUCCESSFULLY COMPLETED! ${RESET}"
            echo -e "${GREEN}==========================================${RESET}"
            echo -e "${WHITE} PM2 Name     : ${CYAN}${BOLD}${PM2_NAME}${RESET}"
            echo -e "${WHITE} Protocol     : ${CYAN}${BOLD}${PROTOCOL_LOWER^^}${RESET}"

            if [ "$PROTOCOL_LOWER" = "tcp" ]; then
                echo -e "${WHITE} Local Port   : ${CYAN}${BOLD}${LOCAL_PORT}${RESET}"
                echo -e "${WHITE} TCP Target   : ${CYAN}${BOLD}${TUNNEL_TARGET}${RESET}"
                if [ -n "$TUNNEL_LINK" ]; then
                    echo -e "${WHITE} TCP Link     : ${GREEN}${BOLD}${TUNNEL_LINK} ${YELLOW}${AUTO_COPIED}${RESET}"
                else
                    echo -e "${YELLOW} TCP Status   : ${GREEN}${BOLD}Active 24/7 on port ${LOCAL_PORT}${RESET}"
                fi
            else
                echo -e "${WHITE} Target Port  : ${CYAN}${BOLD}${TUNNEL_PORT}${RESET}"
                if [ -n "$TUNNEL_LINK" ]; then
                    echo -e "${WHITE} Live Link    : ${CYAN}${BOLD}${TUNNEL_LINK} ${YELLOW}${AUTO_COPIED}${RESET}"
                else
                    echo -e "${YELLOW}[ Warning ] Check Option C for your live link.${RESET}"
                fi
            fi
            echo -e "${GREEN}==========================================${RESET}"
            read -p "Press [ Enter ] to return to menu"
            ;;
        b)
            clear
            echo -e "${RED}[ Warning ] Removing and Uninstalling Tunnel...${RESET}"
            read -p "Enter PM2 Name to delete [Default: cf-tunnel]: " DEL_NAME
            DEL_NAME=${DEL_NAME:-cf-tunnel}
            pm2 delete "$DEL_NAME" 2>/dev/null
            killall cloudflared 2>/dev/null
            rm -f /usr/local/bin/cloudflared
            pm2 save > /dev/null 2>&1
            echo -e "${GREEN}[ Info ] Successfully Uninstalled and Cleaned Up!${RESET}"
            read -p "Press [ Enter ] to return to menu"
            ;;
        c)
            clear
            echo -e "${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${BLUE} 📊 TUNNEL LOGS ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            pm2 status
            echo -e "\n${MAGENTA}Active connection / link:${RESET}"
            ACTIVE_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -oE 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com|tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
            if [ -n "$ACTIVE_LINK" ]; then
                echo -e "${WHITE} Connection ====> ${CYAN}${BOLD}${ACTIVE_LINK}${RESET}"
            else
                echo -e "${YELLOW}[ Warning ] No active connection found in recent logs.${RESET}"
            fi
            echo -e "${CYAN}==================================${RESET}"
            read -p "Press [ Enter ] anytime to exit"
            ;;
        e)
            exit_anim
            ;;
        *)
            echo -e "${RED}[ Error ] Invalid Option! Please choose A, B, C, or E.${RESET}"
            sleep 1.5
            ;;
    esac
done
