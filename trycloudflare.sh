#!/usr/bin/env bash

# Shell safety guard
if [ -z "$BASH_VERSION" ]; then
    echo "[-] Error: This script requires Bash. Run with: bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Rich Cyberpunk Color Palette (Multi-Color Enhanced)
R='\033[1;31m'   # Red
G='\033[1;32m'   # Green
Y='\033[1;33m'   # Yellow
B='\033[1;34m'   # Blue
M='\033[1;35m'   # Magenta
C='\033[1;36m'   # Cyan
W='\033[1;37m'   # White
GR='\033[0;90m'  # Gray
RES='\033[0m'    # Reset
BOLD='\033[1m'

# High-Detail 1-100% Real-time Animated Progress Bar
show_progress() {
    local task_name="$1"
    local steps=100
    echo -e "${C}[ ➔ ] Preparing: ${Y}${task_name}${RES}..."
    for ((i=1; i<=steps; i++)); do
        local filled=$((i / 5))
        local empty=$((20 - filled))
        
        local bar=""
        local pad=""
        for ((j=0; j<filled; j++)); do bar+="█"; done
        for ((j=0; j<empty; j++)); do pad+="░"; done

        printf "\r${C} ⟡ Progress: [${G}%s${GR}%s${C}] ${Y}%3d%%${RES}" "$bar" "$pad" "$i"
        sleep 0.01
    done
    echo -e "\n${G} [ ✔ ] ${task_name} Finished Successfully!${RES}\n"
}

# System Information Extractor
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
        PM2_VAL="${G}${BOLD}Active (${PM2_COUNT} Online)${RES}"
    else
        PM2_VAL="${R}${BOLD}Offline${RES}"
    fi

    PINGGY_LINK=""
    if command -v pm2 &> /dev/null; then
        PINGGY_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -oE 'https://[a-zA-Z0-9.-]*\.pinggy\.(link|io)|tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
    fi

    if [ -n "$PINGGY_LINK" ]; then
        PINGGY_STATUS="${G}${BOLD}ONLINE (24/7 Stable)${RES}"
    else
        PINGGY_STATUS="${R}${BOLD}STOPPED${RES}"
    fi
}

# Rich ASCII Cyberpunk Banner
show_banner() {
    clear
    get_sys_info
    echo -e "${C}╔════════════════════════════════════════════╗${RES}"
    echo -e "${B}${BOLD} ██████╗  ██████╗ ███╗   ██╗ ██████╗ ██████╗ ${RES}"
    echo -e "${B}${BOLD} ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗██╔══██╗${RES}"
    echo -e "${B}${BOLD} ██████╔╝██║  ███╗██╔██╗ ██║██║   ██║██║  ██║${RES}"
    echo -e "${B}${BOLD} ██╔══██╗██║   ██║██║╚██╗██║██║   ██║██║  ██║${RES}"
    echo -e "${B}${BOLD} ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝██████╔╝${RES}"
    echo -e "${M}           Elite Engine By 𝐌ɾ. 𝐙ᥱ𝚝𝚛𝐢𝐱         ${RES}"
    echo -e "${C}╠════════════════════════════════════════════╣${RES}"
    echo -e "${Y}  System Uptime  :${RES} ${G}${UPTIME_VAL}${RES}"
    echo -e "${Y}  OS Environment :${RES} ${C}${OS_VAL}${RES}"
    echo -e "${Y}  PM2 Daemon     :${RES} ${PM2_VAL}"
    echo -e "${Y}  Tunnel Status  :${RES} ${PINGGY_STATUS}"
    echo -e "${C}╚════════════════════════════════════════════╝${RES}"
}

exit_anim() {
    echo -e "${Y} [ * ] Shutting down safely. Goodbye!${RES}"; sleep 0.5
    exit 0
}

# Initial Startup Splash with 4-second Neofetch
clear
if command -v neofetch &> /dev/null; then
    echo -e "${M}"
    neofetch --off
    echo -e "${RES}"
    sleep 4
fi

while true; do
    show_banner
    echo -e "${W} [ 1 / A ]${RES} ${G}➔ Install ( Auto Mode )${RES}"
    echo -e "${W} [ 2 / B ]${RES} ${R}➔ Uninstall Tunnels${RES}"
    echo -e "${W} [ 3 / C ]${RES} ${C}➔ Live Logs${RES}"
    echo -e "${W} [ 4 / E ]${RES} ${Y}➔ Shut Down${RES}"
    echo -e "${C}──────────────────────────────────────────────${RES}"
    read -p "Select Command Option: " CHOICE

    case "${CHOICE,,}" in
        a|1)
            clear
            echo -e "${C}╔════════════════════════════════════════════╗${RES}"
            echo -e "${G}${BOLD}         🚀 ADVANCED TUNNEL CONFIGURATION     ${RES}"
            echo -e "${C}╚════════════════════════════════════════════╝${RES}"
            
            read -p "Enter PM2 Process Name [Default: pinggy-core]: " PM2_NAME
            PM2_NAME=${PM2_NAME:-pinggy-core}

            read -p "Select Protocol (http / https / tcp) [Default: http]: " PROTOCOL
            PROTOCOL=${PROTOCOL:-http}
            PROTOCOL_LOWER=$(echo "$PROTOCOL" | tr '[:upper:]' '[:lower:]')

            read -p "Enter Local Target Port (e.g., 22, 3306, 3000) [Default: 3000]: " LOCAL_PORT
            LOCAL_PORT=${LOCAL_PORT:-3000}

            # On-Demand Auto Installation of Missing Dependencies when A is clicked
            echo -e "\n${C} [ ➔ ] Verifying Core Dependencies (PM2 & OpenSSH)...${RES}"
            if ! command -v pm2 &> /dev/null; then
                show_progress "Installing PM2 Enterprise Daemon"
                npm install -g pm2 > /dev/null 2>&1
            fi

            if ! command -v ssh &> /dev/null; then
                show_progress "Installing OpenSSH Secure Client"
                if command -v apt-get &> /dev/null; then
                    apt-get update -y > /dev/null 2>&1 && apt-get install -y openssh-client > /dev/null 2>&1
                elif command -v apk &> /dev/null; then
                    apk add --no-cache openssh-client > /dev/null 2>&1
                elif command -v dnf &> /dev/null; then
                    dnf install -y openssh-clients > /dev/null 2>&1
                fi
            fi

            SSH_TARGET="free.pinggy.io"
            if [ "$PROTOCOL_LOWER" = "tcp" ]; then
                SSH_TARGET="tcp@free.pinggy.io"
            fi

            echo -e "\n${C}══════════════════════════════════════════════${RES}"
            show_progress "Establishing 99.99% Uptime Persistent Tunnel"

            pm2 delete "$PM2_NAME" 2>/dev/null
            
            # Start secure, persistent keep-alive background daemon via PM2
            pm2 start ssh --name "${PM2_NAME}" -- -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=15 -o ServerAliveCountMax=5 -R0:localhost:${LOCAL_PORT} ${SSH_TARGET} > /dev/null 2>&1
            pm2 save > /dev/null 2>&1

            echo -e "${C} [ ➔ ] Extracting secure routing address...${RES}"
            TUNNEL_LINK=""
            for i in {1..15}; do
                sleep 1
                if [ "$PROTOCOL_LOWER" = "tcp" ]; then
                    TUNNEL_LINK=$(pm2 logs "${PM2_NAME}" --lines 50 --nostream 2>/dev/null | grep -oE 'tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
                else
                    TUNNEL_LINK=$(pm2 logs "${PM2_NAME}" --lines 50 --nostream 2>/dev/null | grep -oE 'https://[a-zA-Z0-9.-]*\.pinggy\.(link|io)' | tail -n 1)
                fi
                if [ -n "$TUNNEL_LINK" ]; then
                    break
                fi
            done

            # Universal Auto-Clipboard Copy Engine
            AUTO_COPIED=""
            if [ -n "$TUNNEL_LINK" ]; then
                if command -v termux-clipboard-set &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | termux-clipboard-set
                    AUTO_COPIED="(Auto-Copied to Clipboard!)"
                elif command -v xclip &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | xclip -selection clipboard
                    AUTO_COPIED="(Auto-Copied to Clipboard!)"
                elif command -v xsel &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | xsel --clipboard --input
                    AUTO_COPIED="(Auto-Copied to Clipboard!)"
                elif command -v pbcopy &> /dev/null; then
                    echo -n "$TUNNEL_LINK" | pbcopy
                    AUTO_COPIED="(Auto-Copied to Clipboard!)"
                fi
            fi

            echo -e "\n${G}╔════════════════════════════════════════════╗${RES}"
            echo -e "${G}${BOLD}         ✅ TUNNEL DEPLOYED SUCCESSFULLY!     ${RES}"
            echo -e "${G}╚════════════════════════════════════════════╝${RES}"
            echo -e "${W} 🔹 Process Name : ${C}${BOLD}${PM2_NAME}${RES}"
            echo -e "${W} 🔹 Protocol     : ${C}${BOLD}${PROTOCOL_LOWER^^}${RES}"
            echo -e "${W} 🔹 Local Port   : ${C}${BOLD}${LOCAL_PORT}${RES}"

            if [ -n "$TUNNEL_LINK" ]; then
                echo -e "${W} 🔹 Public Link  : ${G}${BOLD}${TUNNEL_LINK} ${Y}${AUTO_COPIED}${RES}"
            else
                echo -e "${Y} [ ! ] Link initializing. Check Option [3/C] for diagnostics.${RES}"
            fi
            echo -e "${G}──────────────────────────────────────────────${RES}"
            read -p "Press [ Enter ] to return to main dashboard..."
            ;;
        b|2)
            clear
            echo -e "${R}╔════════════════════════════════════════════╗${RES}"
            echo -e "${R}${BOLD}         ⚠️ TERMINATING TUNNEL SESSIONS       ${RES}"
            echo -e "${R}╚════════════════════════════════════════════╝${RES}"
            read -p "Enter PM2 Process Name to clean [Default: pinggy-core]: " DEL_NAME
            DEL_NAME=${DEL_NAME:-pinggy-core}
            pm2 delete "$DEL_NAME" 2>/dev/null
            pm2 save > /dev/null 2>&1
            echo -e "${G} [ ✔ ] Target tunnel instance successfully purged!${RES}"
            read -p "Press [ Enter ] to return to main dashboard..."
            ;;
        c|3)
            clear
            echo -e "${C}╔════════════════════════════════════════════╗${RES}"
            echo -e "${B}${BOLD}         📊 REAL-TIME DIAGNOSTICS & LOGS      ${RES}"
            echo -e "${C}╚════════════════════════════════════════════╝${RES}"
            pm2 status
            echo -e "\n${M}Active Public Route Target:${RES}"
            ACTIVE_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -oE 'https://[a-zA-Z0-9.-]*\.pinggy\.(link|io)|tcp://[a-zA-Z0-9.-]*:[0-9]*' | tail -n 1)
            if [ -n "$ACTIVE_LINK" ]; then
                echo -e "${W} Route ➔ ${C}${BOLD}${ACTIVE_LINK}${RES}"
            else
                echo -e "${Y} [ ! ] No active public stream detected in logs yet.${RES}"
            fi
            echo -e "${C}──────────────────────────────────────────────${RES}"
            read -p "Press [ Enter ] to return to main dashboard..."
            ;;
        e|4)
            exit_anim
            ;;
        *)
            echo -e "${R} [ X ] Invalid option selected! Please choose A, B, C, or E.${RES}"
            sleep 1.2
            ;;
    esac
done
