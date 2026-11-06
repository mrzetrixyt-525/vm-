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

# 1-100% Animated Progress Bar
show_progress() {
    local task_name="$1"
    local steps=100
    echo -e "${CYAN}[ Info ] Starting: ${task_name}...${RESET}"
    for ((i=1; i<=steps; i++)); do
        local filled=$((i / 5))
        local empty=$((20 - filled))
        
        local bar=""
        local pad=""
        for ((j=0; j<filled; j++)); do bar+="█"; done
        for ((j=0; j<empty; j++)); do pad+="░"; done

        printf "\r${CYAN}Progress: [${GREEN}%s${WHITE}%s${CYAN}] ${YELLOW}%3d%%${RESET}" "$bar" "$pad" "$i"
        sleep 0.015
    done
    echo -e "\n${GREEN}[ Info ] ${task_name} Completed Successfully!${RESET}\n"
}

# Auto OS Detection & Dynamic Package Setup
system_init() {
    clear
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${BOLD}${BLUE} 🔍 AUTO OS DETECTION & SYSTEM PREPARATION ${RESET}"
    echo -e "${CYAN}========= • =========${RESET}"

    if command -v apt-get &> /dev/null; then
        echo -e "${GREEN}[ OS Detected ] Debian / Ubuntu Based System${RESET}"
        
        show_progress "System Repository Update & Upgrade"
        apt-get update -y || true
        apt-get upgrade -y || true

        NEEDED_PKGS=()
        for pkg in curl nodejs npm procps psmisc neofetch base64; do
            if ! dpkg -s "$pkg" &> /dev/null && ! command -v "$pkg" &> /dev/null; then
                NEEDED_PKGS+=("$pkg")
            fi
        done

        if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
            echo -e "${YELLOW}[ Info ] Installing missing packages: ${NEEDED_PKGS[*]}${RESET}"
            show_progress "Installing Required Packages"
            apt-get install -y "${NEEDED_PKGS[@]}"
        else
            echo -e "${GREEN}[ Info ] All required system packages are already installed!${RESET}"
        fi

        if ! command -v node &> /dev/null || [[ "$(node -v 2>/dev/null)" != v22* ]]; then
            echo -e "${YELLOW}[ Info ] Node.js 22 missing. Upgrading to Node.js 22...${RESET}"
            show_progress "Node.js 22 Environment Setup"
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y nodejs
        fi

    elif command -v apk &> /dev/null; then
        echo -e "${GREEN}[ OS Detected ] Alpine Linux Based System${RESET}"
        show_progress "System Repository Update & Upgrade"
        apk update || true
        apk upgrade || true

        NEEDED_PKGS=()
        for pkg in curl nodejs npm procps psmisc neofetch bash coreutils; do
            if ! apk info -e "$pkg" &> /dev/null; then
                NEEDED_PKGS+=("$pkg")
            fi
        done

        if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
            echo -e "${YELLOW}[ Info ] Installing missing packages: ${NEEDED_PKGS[*]}${RESET}"
            show_progress "Installing Required Packages"
            apk add --no-cache "${NEEDED_PKGS[@]}"
        else
            echo -e "${GREEN}[ Info ] All required system packages are already installed!${RESET}"
        fi

    elif command -v dnf &> /dev/null || command -v yum &> /dev/null; then
        PKG_MGR="yum"
        command -v dnf &> /dev/null && PKG_MGR="dnf"
        echo -e "${GREEN}[ OS Detected ] RedHat / CentOS / Fedora (${PKG_MGR})${RESET}"
        
        show_progress "System Repository Update & Upgrade"
        $PKG_MGR update -y || true

        NEEDED_PKGS=()
        for pkg in curl nodejs npm procps-ng psmisc neofetch coreutils; do
            if ! rpm -q "$pkg" &> /dev/null && ! command -v "$pkg" &> /dev/null; then
                NEEDED_PKGS+=("$pkg")
            fi
        done

        if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
            echo -e "${YELLOW}[ Info ] Installing missing packages: ${NEEDED_PKGS[*]}${RESET}"
            show_progress "Installing Required Packages"
            $PKG_MGR install -y "${NEEDED_PKGS[@]}"
        else
            echo -e "${GREEN}[ Info ] All required system packages are already installed!${RESET}"
        fi
    fi

    if command -v neofetch &> /dev/null; then
        echo -e "${MAGENTA}"
        neofetch --off
        echo -e "${RESET}"
        sleep 2
    fi
}

get_sys_info() {
    UPTIME_VAL=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    
    if [ -f /etc/os-release ]; then
        OS_VAL=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_VAL=$(uname -s 2>/dev/null || echo "Linux")
    fi

    if command -v pm2 &> /dev/null; then
        PM2_COUNT=$(pm2 list --no-color 2>/dev/null | grep -c "online" || echo "0")
        if [ "$PM2_COUNT" -gt 0 ]; then
            PM2_VAL="${GREEN}${BOLD}Active (${PM2_COUNT} Process Online)${RESET}"
        else
            PM2_VAL="${RED}${BOLD}Inactive${RESET}"
        fi
    else
        PM2_VAL="${RED}${BOLD}Inactive (Not Installed)${RESET}"
    fi

    CF_LINK=""
    if command -v pm2 &> /dev/null; then
        CF_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
    fi

    if [ -n "$CF_LINK" ]; then
        CF_STATUS="${GREEN}${BOLD}Running${RESET} ${CYAN}( ${CF_LINK} )${RESET}"
    else
        CF_STATUS="${RED}${BOLD}Stopped${RESET}"
    fi
}

show_banner() {
    clear
    get_sys_info
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${BOLD}${BLUE} ██████╗  ██████╗ ███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗™${RESET}"
    echo -e "${BOLD}${BLUE} ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝ ${RESET}"
    echo -e "${BOLD}${BLUE} ██████╔╝██║  ███╗██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗ ${RESET}"
    echo -e "${BOLD}${BLUE} ██╔══██╗██║   ██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║ ${RESET}"
    echo -e "${BOLD}${BLUE} ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝██████╔╝███████╗███████║ ${RESET}"
    echo -e "${MAGENTA}           Made By 𝐌ɾ. 𝐙ᥱ𝚝𝚛𝐢𝐱                 ${RESET}"
    echo -e "${CYAN}========= • =========${RESET}"
    echo -e "${YELLOW}  Uptime        :${RESET} ${GREEN}${UPTIME_VAL}${RESET}"
    echo -e "${YELLOW}  OS            :${RESET} ${CYAN}${OS_VAL}${RESET}"
    echo -e "${YELLOW}  PM2           :${RESET} ${PM2_VAL}"
    echo -e "${YELLOW}  TryCloudflare :${RESET} ${CF_STATUS}"
    echo -e "${CYAN}========= • =========${RESET}"
}

exit_anim() {
    echo -e "${YELLOW}[ Info ] Good Bye Bye.${RESET}"; sleep 0.6
    echo -e "${YELLOW}[ Info ] Good Bye Bye .${RESET}"; sleep 0.6
    echo -e "${YELLOW}[ Info ] Good Bye Bye   .${RESET}"; sleep 0.6
    exit 0
}

# Run Auto OS Setup On Startup
system_init

while true; do
    show_banner
    echo -e "${WHITE}[ A ]${RESET} Host Secured Code Snippet ( Cmd.io Style + Password )"
    echo -e "${WHITE}[ B ]${RESET} Uninstall ( Auto Remove )"
    echo -e "${WHITE}[ C ]${RESET} Tunnel Status & Logs"
    echo -e "${WHITE}[ E ]${RESET} Exit"
    echo -e "${CYAN}========= • =========${RESET}"
    read -p "Choose: " CHOICE

    case "${CHOICE,,}" in
        a)
            clear
            echo -e "${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} 🚀 CONFIGURE SECURED CODE SNIPPET ( 1/4 )${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            
            read -p "Tunnel Name [Default: cf-code-tunnel]: " TUNNEL_NAME
            TUNNEL_NAME=${TUNNEL_NAME:-cf-code-tunnel}
            
            echo -e "${YELLOW}Enter or Paste the Code/Script you want to share securely:${RESET}"
            echo -e "${CYAN}(Type 'END' on a new line and press Enter when you are finished)${RESET}"
            
            USER_CODE=""
            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                USER_CODE+="$line"$'\n'
            done

            if [ -z "$USER_CODE" ]; then
                USER_CODE="#!/bin/bash\necho \"Hello from protected cmd.io style tunnel!\""
            fi

            # Robust portable Base64 encoding for any OS
            if base64 --help 2>&1 | grep -q -- "-w"; then
                ENCODED_CODE=$(echo -n "$USER_CODE" | base64 -w 0)
            else
                ENCODED_CODE=$(echo -n "$USER_CODE" | base64 | tr -d '\n')
            fi

            DEFAULT_PASS="এটিকে টেক্সট বক্সে পেস্ট করতে ক্লিপে ট্যাপ করুন।"
            read -p "Set Access Password [Default: ${DEFAULT_PASS}]: " ACCESS_PASS
            ACCESS_PASS=${ACCESS_PASS:-$DEFAULT_PASS}
            
            echo -e "${YELLOW}[ Info ] Creating secure Cmd.io style code viewer...${RESET}"
            
            # Create Node.js Cmd.io Viewer script safely embedding base64 code and password
            cat << EOF > /tmp/cmd_io_viewer.js
const http = require('http');
const url = require('url');

const PASSWORD = \`${ACCESS_PASS}\`;
const PORT = 3939;
const ENCODED_CONTENT = \`${ENCODED_CODE}\`;
const SECURE_CODE = Buffer.from(ENCODED_CONTENT, 'base64').toString('utf8');

const server = http.createServer((req, res) => {
    const parsedUrl = url.parse(req.url, true);
    const cookies = req.headers.cookie || '';
    const isAuthenticated = cookies.includes('auth_granted=true') || parsedUrl.query.pass === PASSWORD;

    if (parsedUrl.query.pass === PASSWORD) {
        res.setHeader('Set-Cookie', 'auth_granted=true; Path=/; HttpOnly');
        res.writeHead(302, { 'Location': '/' });
        res.end();
        return;
    }

    if (!isAuthenticated) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(\`
            <html>
            <head>
                <title>Secured Code Access</title>
                <meta charset="utf-8">
                <style>
                    body { background: #0f172a; color: #38bdf8; font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                    .card { background: #1e293b; padding: 35px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.6); text-align: center; border: 1px solid #334155; width: 380px; }
                    input { width: 100%; padding: 12px; margin: 15px 0; background: #0f172a; border: 1px solid #475569; color: #fff; border-radius: 6px; box-sizing: border-box; font-size: 13px; }
                    button { background: #22c55e; color: #000; border: none; padding: 12px 20px; font-weight: bold; border-radius: 6px; cursor: pointer; width: 100%; font-size: 14px; }
                    button:hover { background: #16a34a; }
                    h2 { margin-top: 0; color: #f8fafc; }
                </style>
            </head>
            <body>
                <div class="card">
                    <h2>🔒 Cmd.io Locked</h2>
                    <p style="color: #94a3b8; font-size: 13px;">পাসওয়ার্ড দিয়ে কোড এক্সেস করুন</p>
                    <form method="GET">
                        <input type="text" name="pass" placeholder="পাসওয়ার্ড এখানে পেস্ট করুন..." required />
                        <button type="submit">Unlock Code</button>
                    </form>
                </div>
            </body>
            </html>
        \`);
        return;
    }

    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(\`
        <html>
        <head>
            <title>Cmd.io - Secure Code Viewer</title>
            <meta charset="utf-8">
            <style>
                body { background: #0b0f19; color: #e2e8f0; font-family: 'Courier New', Courier, monospace; margin: 0; padding: 25px; }
                .container { max-width: 950px; margin: auto; background: #131c2e; border-radius: 10px; border: 1px solid #1e293b; overflow: hidden; box-shadow: 0 15px 35px rgba(0,0,0,0.7); }
                .header { background: #0f172a; padding: 18px 25px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #1e293b; }
                .header h3 { margin: 0; color: #38bdf8; font-size: 18px; }
                button { background: #22c55e; color: #000; border: none; padding: 10px 20px; font-weight: bold; border-radius: 6px; cursor: pointer; font-family: monospace; font-size: 13px; transition: 0.2s; }
                button:hover { background: #16a34a; }
                pre { margin: 0; padding: 25px; overflow-x: auto; color: #a5f3fc; font-size: 14px; line-height: 1.6; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h3>⚡ Protected Code Snippet</h3>
                    <button onclick="copyCode()" id="copyBtn">📋 Copy Code</button>
                </div>
                <pre><code id="code-content"></code></pre>
            </div>
            <script>
                const rawCode = \`\${SECURE_CODE}\`;
                document.getElementById('code-content').textContent = rawCode;

                function copyCode() {
                    navigator.clipboard.writeText(rawCode).then(() => {
                        const btn = document.getElementById('copyBtn');
                        btn.innerText = '✅ Copied!';
                        setTimeout(() => { btn.innerText = '📋 Copy Code'; }, 2000);
                    });
                }
            </script>
        </body>
        </html>
    \`);
});

server.listen(PORT, '127.0.0.1', () => {
    console.log('Cmd.io Viewer running on port ' + PORT);
});
EOF

            echo -e "\n${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} ⚙️ INSTALLING PM2 MANAGER ( 2/4 )${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            
            if ! command -v pm2 &> /dev/null; then
                show_progress "Installing PM2 Global Manager"
                npm install -g pm2 > /dev/null 2>&1
            else
                echo -e "${GREEN}[ Info ] PM2 is already active & installed.${RESET}"
            fi

            echo -e "\n${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${GREEN} 🌐 SETUP TUNNEL ( 3/4 )${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            show_progress "Fetching Cloudflare Tunnel Binary"
            
            pm2 delete "$TUNNEL_NAME" 2>/dev/null
            pm2 delete "${TUNNEL_NAME}-viewer" 2>/dev/null
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
            echo -e "${BOLD}${GREEN} 🔄 SETUP 24/7 BACKGROUND ( 4/4 )${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            show_progress "Starting PM2 Service Persistence"

            # Start Secure Code Viewer via PM2 directly pointing to generated file
            pm2 start /tmp/cmd_io_viewer.js --name "${TUNNEL_NAME}-viewer" > /dev/null 2>&1

            # Start Cloudflare Tunnel pointing to local code viewer port 3939
            pm2 start /usr/local/bin/cloudflared --name "$TUNNEL_NAME" -- tunnel --url http://localhost:3939 --no-tls-verify > /dev/null 2>&1
            pm2 save > /dev/null 2>&1

            echo -e "${CYAN}[ Info ] Extracting Cloudflare Tunnel Link...${RESET}"
            TUNNEL_LINK=""
            for i in {1..10}; do
                sleep 1
                TUNNEL_LINK=$(pm2 logs "$TUNNEL_NAME" --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
                if [ -n "$TUNNEL_LINK" ]; then
                    break
                fi
            done

            echo -e "\n${GREEN}==========================================${RESET}"
            echo -e "${BOLD}${GREEN} ✅ SUCCESSFULLY COMPLETED! ${RESET}"
            echo -e "${GREEN}==========================================${RESET}"
            if [ -n "$TUNNEL_LINK" ]; then
                echo -e "${WHITE} Link     ====> ${CYAN}${BOLD}${TUNNEL_LINK}${RESET}"
                echo -e "${WHITE} Password ====> ${GREEN}${BOLD}${ACCESS_PASS}${RESET}"
            else
                echo -e "${YELLOW}[ Warning ] Take Your Link from Option C${RESET}"
            fi
            echo -e "${GREEN}==========================================${RESET}"
            read -p "Press [ Enter ] To Menu"
            ;;
        b)
            clear
            echo -e "${RED}[ Warning ] Removing and Uninstalling Tunnel & Viewer...${RESET}"
            read -p "Enter Tunnel Name to delete [Default: cf-code-tunnel]: " DEL_NAME
            DEL_NAME=${DEL_NAME:-cf-code-tunnel}
            pm2 delete "$DEL_NAME" 2>/dev/null
            pm2 delete "${DEL_NAME}-viewer" 2>/dev/null
            killall cloudflared 2>/dev/null
            rm -f /usr/local/bin/cloudflared
            rm -f /tmp/cmd_io_viewer.js
            pm2 save > /dev/null 2>&1
            echo -e "${GREEN}[ Info ] Successfully Uninstalled and Cleaned Up!${RESET}"
            read -p "Press [ Enter ] To Menu"
            ;;
        c)
            clear
            echo -e "${CYAN}========= • =========${RESET}"
            echo -e "${BOLD}${BLUE} 📊 TUNNEL STATUS & LOGS ${RESET}"
            echo -e "${CYAN}========= • =========${RESET}"
            pm2 status
            echo -e "\n${MAGENTA}Active trycloudflare link:${RESET}"
            ACTIVE_LINK=$(pm2 logs --lines 50 --nostream 2>/dev/null | grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' | tail -n 1)
            if [ -n "$ACTIVE_LINK" ]; then
                echo -e "${WHITE} Link ====> ${CYAN}${BOLD}${ACTIVE_LINK}${RESET}"
            else
                echo -e "${YELLOW}[ Warning ] No active link found in recent logs.${RESET}"
            fi
            echo -e "${CYAN}==================================${RESET}"
            read -p "Press [ Enter ] anytime to exit"
            ;;
        e)
            exit_anim
            ;;
        *)
            echo -e "${RED}[ Error ] Invalid Option! Please choose A, B, C or E.${RESET}"
            sleep 1.5
            ;;
    esac
done
