#!/usr/bin/env bash
############################################################
#                                                          #
#                 RGNODES™ TUNNEL MANAGER                  #
#       Multi-Tunnel • TryCloudflare & Pinggy TCP          #
#                                                          #
#     All-In-One • Auto-Skip • 24/7 PM2 • Auto-Boot        #
#                                                          #
############################################################

############################
# 1. SHELL GUARD & SAFE ENV
############################
if [ -z "${BASH_VERSION:-}" ]; then
  printf "✖ Use bash: bash %s\n" "$0" >&2
  exit 1
fi
set -u
export DEBIAN_FRONTEND=noninteractive

############################
# 2. COLOR PALETTE & UI HELPERS
############################
ORANGE='\033[38;5;208m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
LPINK='\033[38;5;213m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
RESET='\033[0m'

if [[ ! -t 1 ]]; then
  ORANGE=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''
  LPINK=''; CYAN=''; WHITE=''; DIM=''; BOLD=''; UNDERLINE=''; RESET=''
fi

step() { printf "\n%b➜%b %b%s%b\n" "$ORANGE$BOLD" "$RESET" "$WHITE$BOLD" "$1" "$RESET"; }
ok()   { printf "%b✔%b %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%b⚠%b %s\n" "$YELLOW" "$RESET" "$1"; }
fail() { printf "%b✖%b %s\n" "$RED" "$RESET" "$1" >&2; }

tag_info() {
  printf "%b[%b %b%s%b %b]%b" "$LPINK$BOLD" "$RESET" "$WHITE$BOLD" "$1" "$RESET" "$LPINK$BOLD" "$RESET"
}

info_msg() {
  printf "%s %b∆%b %s\n" "$(tag_info "Info")" "$CYAN$BOLD" "$RESET" "$1"
}

clickable_link() {
  local url="$1"
  local label="${2:-$1}"
  if [[ -t 1 ]]; then
    printf "\e]8;;%s\a%b%s%b\e]8;;\a" "$url" "$CYAN$BOLD$UNDERLINE" "$label" "$RESET"
  else
    printf "%s" "$url"
  fi
}

copy_to_clipboard() {
  local text="$1"
  [[ -z "$text" ]] && return 1
  if command -v termux-clipboard-set >/dev/null 2>&1; then
    printf "%s" "$text" | termux-clipboard-set 2>/dev/null && return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf "%s" "$text" | xclip -selection clipboard 2>/dev/null && return 0
  fi
  if command -v xsel >/dev/null 2>&1; then
    printf "%s" "$text" | xsel --clipboard --input 2>/dev/null && return 0
  fi
  if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$text" | pbcopy 2>/dev/null && return 0
  fi
  return 1
}

############################
# 3. SMOOTH PROGRESS BAR
############################
show_progress() {
  local task_name="$1"
  local delay="${2:-0.006}"
  local i filled empty bar pad
  info_msg "Loading: ${task_name}"
  for ((i = 1; i <= 100; i++)); do
    filled=$((i / 5))
    empty=$((20 - filled))
    bar=""
    pad=""
    for ((j = 0; j < filled; j++)); do bar+="█"; done
    for ((j = 0; j < empty; j++)); do pad+="░"; done
    printf "\r%b[%b%s%b%s%b] %b%3d%%%b" \
      "$CYAN" "$GREEN" "$bar" "$WHITE" "$pad" "$CYAN" "$YELLOW" "$i" "$RESET"
    sleep "$delay"
  done
  printf "\n"
  ok "${task_name} done"
}

############################
# 4. 100% AUTO-SKIP SYSTEM INIT
############################
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v apk >/dev/null 2>&1; then echo "apk"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v pkg >/dev/null 2>&1; then echo "pkg"
  else echo "unknown"
  fi
}

has_pkg() {
  local pkg="$1"
  if command -v dpkg >/dev/null 2>&1; then
    dpkg -s "$pkg" >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk info -e "$pkg" >/dev/null 2>&1
  elif command -v rpm >/dev/null 2>&1; then
    rpm -q "$pkg" >/dev/null 2>&1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Qi "$pkg" >/dev/null 2>&1
  else
    command -v "$pkg" >/dev/null 2>&1
  fi
}

has_node22() {
  command -v node >/dev/null 2>&1 && [[ "$(node -v 2>/dev/null)" == v22* ]]
}

system_init() {
  clear
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
  printf "%b  🔍 AUTO-SKIP SYS CHECK%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"

  local missing=0 pkg pm
  for pkg in curl npm procps psmisc neofetch; do
    if ! has_pkg "$pkg"; then
      missing=1
      break
    fi
  done
  has_node22 || missing=1

  if [[ "$missing" -eq 0 ]]; then
    ok "All pkgs & Node 22 ready — 100% skipped."
    sleep 0.4
    return 0
  fi

  pm=$(detect_pkg_mgr)
  warn "Installing missing deps (${pm})..."

  case "$pm" in
    apt)
      show_progress "APT Update"
      apt-get update -y >/dev/null 2>&1 || true
      local pkgs=()
      for pkg in curl procps psmisc neofetch; do
        has_pkg "$pkg" || pkgs+=("$pkg")
      done
      if [[ "${#pkgs[@]}" -gt 0 ]]; then
        show_progress "Base Pkgs"
        apt-get install -y "${pkgs[@]}" >/dev/null 2>&1 || true
      fi
      if ! has_node22; then
        show_progress "Node.js 22"
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1 || true
        apt-get install -y nodejs >/dev/null 2>&1 || true
      fi
      ;;
    apk)
      show_progress "APK Update"
      apk update >/dev/null 2>&1 || true
      local pkgs=()
      for pkg in curl nodejs npm procps psmisc neofetch bash; do
        has_pkg "$pkg" || pkgs+=("$pkg")
      done
      if [[ "${#pkgs[@]}" -gt 0 ]]; then
        show_progress "APK Pkgs"
        apk add --no-cache "${pkgs[@]}" >/dev/null 2>&1 || true
      fi
      ;;
    dnf|yum)
      show_progress "RPM Update"
      "$pm" update -y >/dev/null 2>&1 || true
      local pkgs=()
      for pkg in curl nodejs npm procps-ng psmisc neofetch; do
        has_pkg "$pkg" || pkgs+=("$pkg")
      done
      if [[ "${#pkgs[@]}" -gt 0 ]]; then
        show_progress "RPM Pkgs"
        "$pm" install -y "${pkgs[@]}" >/dev/null 2>&1 || true
      fi
      ;;
    pacman)
      show_progress "Pacman Sync"
      pacman -Sy --noconfirm curl nodejs npm procps-ng psmisc neofetch >/dev/null 2>&1 || true
      ;;
    pkg)
      show_progress "PKG Update"
      pkg update -y >/dev/null 2>&1 || true
      pkg install -y curl nodejs npm procps psmisc neofetch >/dev/null 2>&1 || true
      ;;
    *)
      fail "Unsupported OS/pkg mgr."
      exit 1
      ;;
  esac

  if command -v neofetch >/dev/null 2>&1; then
    printf "%b" "$MAGENTA"
    neofetch --off 2>/dev/null || true
    printf "%b" "$RESET"
    sleep 1.2
  fi
}

############################
# 5. PM2 REBOOT PERSISTENCE
############################
detect_init_sys() {
  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    echo "systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    echo "openrc"
  elif [[ -d /etc/init.d ]]; then
    echo "sysvinit"
  elif [[ -d /data/data/com.termux ]]; then
    echo "termux"
  else
    echo "proot/shell"
  fi
}

configure_pm2_startup() {
  command -v pm2 >/dev/null 2>&1 || return 0
  pm2 save --force >/dev/null 2>&1 || pm2 save >/dev/null 2>&1 || true

  local startup_cmd
  startup_cmd=$(pm2 startup 2>/dev/null | grep -E 'sudo |env PATH=' | tail -n 1 || true)
  if [[ -n "$startup_cmd" ]]; then
    [[ "${EUID:-1}" -eq 0 ]] && startup_cmd="${startup_cmd#sudo }"
    eval "$startup_cmd" >/dev/null 2>&1 || true
    pm2 save --force >/dev/null 2>&1 || pm2 save >/dev/null 2>&1 || true
  fi

  # Fallback resurrect hook for PRoot / Termux / non-systemd containers
  local init_sys
  init_sys=$(detect_init_sys)
  if [[ "$init_sys" != "systemd" ]]; then
    for rc_file in "${HOME}/.bashrc" "${HOME}/.profile"; do
      touch "$rc_file" 2>/dev/null || true
      if ! grep -q "pm2 resurrect" "$rc_file" 2>/dev/null; then
        printf '\n# RGNODES PM2 Resurrect\ncommand -v pm2 >/dev/null 2>&1 && pm2 resurrect >/dev/null 2>&1\n' >> "$rc_file"
      fi
    done
  fi
}

get_boot_badge() {
  if ! command -v pm2 >/dev/null 2>&1; then
    printf "%bOff%b" "$RED$BOLD" "$RESET"
    return 0
  fi
  if ls /etc/systemd/system/pm2-*.service >/dev/null 2>&1 \
     || ls /etc/init.d/pm2-* >/dev/null 2>&1 \
     || grep -q "pm2 resurrect" "${HOME}/.bashrc" 2>/dev/null; then
    printf "%bOn%b" "$GREEN$BOLD" "$RESET"
  else
    printf "%bSync%b" "$YELLOW$BOLD" "$RESET"
  fi
}

############################
# 6. MULTI-TUNNEL & LOG PARSERS
############################
get_pm2_tunnel_names() {
  command -v pm2 >/dev/null 2>&1 || return 0
  pm2 jlist 2>/dev/null | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      try {
        const list = JSON.parse(d);
        list.forEach(p => {
          const exec = (p.pm2_env && p.pm2_env.pm_exec_path) || "";
          const args = ((p.pm2_env && p.pm2_env.args) || []).join(" ");
          if (exec.includes("cloudflared") || args.includes("pinggy.io") || p.name.includes("tunnel")) {
            console.log(p.name);
          }
        });
      } catch (e) {}
    });
  ' 2>/dev/null || true
}

get_pm2_proc_status() {
  local name="$1"
  pm2 jlist 2>/dev/null | node -e '
    let d = "";
    const target = process.argv[1];
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      try {
        const list = JSON.parse(d);
        const found = list.find(p => p.name === target);
        console.log(found && found.pm2_env ? (found.pm2_env.status || "unknown") : "missing");
      } catch (e) { console.log("unknown"); }
    });
  ' "$name" 2>/dev/null || echo "unknown"
}

extract_link_for_process() {
  local pm_name="$1"
  command -v pm2 >/dev/null 2>&1 || return 0
  pm2 logs "$pm_name" --lines 100 --nostream 2>/dev/null \
    | grep -oE 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com|tcp://[a-zA-Z0-9.-]*:[0-9]*|https://[a-zA-Z0-9.-]*\.pinggy\.(link|io)' \
    | tail -n 1 || true
}

check_local_port() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -q ":${port} " && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | grep -q ":${port} " && return 0
  fi
  (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
}

############################
# 7. TELEMETRY & SHORT DASHBOARD
############################
get_sys_info() {
  UPTIME_VAL=$(uptime -p 2>/dev/null | sed 's/^up //; s/ minutes*/m/g; s/ hours*/h/g; s/ days*/d/g; s/,//g' || echo "N/A")
  if [[ -f /etc/os-release ]]; then
    OS_VAL=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d' ' -f1-3 || echo "Linux")
  else
    OS_VAL=$(uname -s 2>/dev/null || echo "Linux")
  fi

  LOAD_VAL=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")
  RAM_VAL=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%d/%dMB", $3, $2}' || echo "N/A")
  INIT_VAL=$(detect_init_sys)
  BOOT_VAL=$(get_boot_badge)

  PM2_COUNT=0
  if command -v pm2 >/dev/null 2>&1; then
    PM2_RAW=$(pm2 jlist 2>/dev/null | grep -o '"status":"online"' | wc -l || echo "0")
    PM2_COUNT=$(printf "%s" "$PM2_RAW" | tr -d '[:space:]')
    [[ "$PM2_COUNT" =~ ^[0-9]+$ ]] || PM2_COUNT=0
  fi

  if [[ "$PM2_COUNT" -gt 0 ]]; then
    PM2_VAL="${GREEN}${BOLD}${PM2_COUNT} online${RESET}"
  else
    PM2_VAL="${RED}${BOLD}0 online${RESET}"
  fi
}

show_banner() {
  clear
  get_sys_info
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
  printf "%b ██████╗  ██████╗ ███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗™%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b ██████╔╝██║  ███╗██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b ██╔══██╗██║   ██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝██████╔╝███████╗███████║%b\n" "$BLUE$BOLD" "$RESET"
  printf "%b  ∆ RGNODES™ • 𝐌ɾ. 𝐙ᥱ𝚝𝚛𝐢xs%b\n" "$MAGENTA$BOLD" "$RESET"
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
  printf " %bOS%b   : %b%s%b | %bUp%b : %b%s%b\n" "$YELLOW" "$RESET" "$CYAN" "$OS_VAL" "$RESET" "$YELLOW" "$RESET" "$GREEN" "$UPTIME_VAL" "$RESET"
  printf " %bRAM%b  : %b%s%b | %bLd%b : %b%s%b\n" "$YELLOW" "$RESET" "$WHITE" "$RAM_VAL" "$RESET" "$YELLOW" "$RESET" "$WHITE" "$LOAD_VAL" "$RESET"
  printf " %bPM2%b  : %b | %bBoot%b : %b | %bInit%b : %b%s%b\n" "$YELLOW" "$RESET" "$PM2_VAL" "$YELLOW" "$RESET" "$BOOT_VAL" "$YELLOW" "$RESET" "$DIM" "$INIT_VAL" "$RESET"

  local tunnels=() t_name t_link t_st dot_c
  while IFS= read -r t_name; do
    [[ -n "$t_name" ]] && tunnels+=("$t_name")
  done < <(get_pm2_tunnel_names)

  if [[ "${#tunnels[@]}" -gt 0 ]]; then
    printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
    for t_name in "${tunnels[@]}"; do
      t_st=$(get_pm2_proc_status "$t_name")
      t_link=$(extract_link_for_process "$t_name")
      dot_c="$GREEN"
      [[ "$t_st" != "online" ]] && dot_c="$RED"
      if [[ -n "$t_link" ]]; then
        printf " %b●%b %b%-10s%b " "$dot_c" "$RESET" "$WHITE$BOLD" "$t_name" "$RESET"
        clickable_link "$t_link"
        printf "\n"
      else
        printf " %b●%b %b%-10s%b [%b%s%b]\n" "$dot_c" "$RESET" "$WHITE$BOLD" "$t_name" "$RESET" "$YELLOW" "$t_st" "$RESET"
      fi
    done
  fi
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
}

exit_anim() {
  ok "Bye! ∆"
  sleep 0.3
  exit 0
}

############################
# 8. [A] ADD / DEPLOY TUNNEL
############################
install_tunnel() {
  clear
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
  printf "%b 🚀 ADD TUNNEL (CF / PINGGY)%b\n" "$GREEN$BOLD" "$RESET"
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"

  local default_name="tunnel-1" idx=1
  if command -v pm2 >/dev/null 2>&1; then
    while pm2 describe "$default_name" >/dev/null 2>&1; do
      idx=$((idx + 1))
      default_name="tunnel-${idx}"
    done
  fi

  read -r -p "Name [${default_name}]: " PM2_NAME
  PM2_NAME="${PM2_NAME:-$default_name}"

  read -r -p "Proto (http/https/tcp) [http]: " PROTOCOL
  PROTOCOL="${PROTOCOL:-http}"
  PROTOCOL_LOWER=$(printf "%s" "$PROTOCOL" | tr '[:upper:]' '[:lower:]')

  NOTLS_ARG=""
  TUNNEL_TARGET=""
  IS_PINGGY=false
  TARGET_PORT_DISP=""

  if [[ "$PROTOCOL_LOWER" == "tcp" ]]; then
    IS_PINGGY=true
    read -r -p "Local port [3000]: " LOCAL_PORT
    LOCAL_PORT="${LOCAL_PORT:-3000}"
    TARGET_PORT_DISP="$LOCAL_PORT"
  else
    read -r -p "Local port [3000]: " TUNNEL_PORT
    TUNNEL_PORT="${TUNNEL_PORT:-3000}"
    TARGET_PORT_DISP="$TUNNEL_PORT"
    TUNNEL_TARGET="${PROTOCOL_LOWER}://localhost:${TUNNEL_PORT}"
    if [[ "$PROTOCOL_LOWER" == "https" ]]; then
      read -r -p "NoTLSVerify [T/F] [T]: " NOTLS_CHOICE
      NOTLS_CHOICE="${NOTLS_CHOICE:-T}"
      [[ "${NOTLS_CHOICE,,}" == "t" ]] && NOTLS_ARG="--no-tls-verify"
    fi
  fi

  if check_local_port "$TARGET_PORT_DISP"; then
    ok "Port ${TARGET_PORT_DISP} listening."
  else
    warn "Port ${TARGET_PORT_DISP} not listening yet."
  fi

  step "Deps Check (Auto-Skip)"
  if command -v pm2 >/dev/null 2>&1; then
    ok "PM2 ready — skipped."
  else
    show_progress "Install PM2"
    npm install -g pm2 >/dev/null 2>&1 || true
  fi

  if [[ "$IS_PINGGY" == true ]]; then
    if command -v ssh >/dev/null 2>&1; then
      ok "SSH ready — skipped."
    else
      show_progress "Install SSH"
      local pm
      pm=$(detect_pkg_mgr)
      case "$pm" in
        apt) apt-get update -y >/dev/null 2>&1 && apt-get install -y openssh-client >/dev/null 2>&1 || true ;;
        apk) apk add --no-cache openssh-client >/dev/null 2>&1 || true ;;
        dnf|yum) "$pm" install -y openssh-clients >/dev/null 2>&1 || true ;;
        pacman) pacman -Sy --noconfirm openssh >/dev/null 2>&1 || true ;;
      esac
    fi
  else
    if [[ -x /usr/local/bin/cloudflared ]]; then
      ok "cloudflared ready — skipped."
    else
      show_progress "Fetch cloudflared"
      local arch cf_url
      arch="$(uname -m)"
      if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
      else
        cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
      fi
      curl -fsSL --output /usr/local/bin/cloudflared "$cf_url"
      chmod +x /usr/local/bin/cloudflared
      ok "cloudflared installed."
    fi
  fi

  step "Start '${PM2_NAME}' & Sync Boot"
  pm2 delete "$PM2_NAME" >/dev/null 2>&1 || true

  if [[ "$IS_PINGGY" == true ]]; then
    pm2 start ssh --name "$PM2_NAME" \
      --restart-delay=3000 --max-restarts=999999 -- \
      -p 443 -o StrictHostKeyChecking=no \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=5 \
      -R0:localhost:"$LOCAL_PORT" tcp@free.pinggy.io >/dev/null 2>&1
  else
    local cmd_args="--url ${TUNNEL_TARGET}"
    [[ -n "$NOTLS_ARG" ]] && cmd_args="${cmd_args} ${NOTLS_ARG}"
    pm2 start /usr/local/bin/cloudflared --name "$PM2_NAME" \
      --restart-delay=3000 --max-restarts=999999 -- \
      ${cmd_args} >/dev/null 2>&1
  fi

  configure_pm2_startup
  info_msg "Waiting for tunnel URL..."

  local TUNNEL_LINK="" i
  for ((i = 1; i <= 15; i++)); do
    sleep 1
    TUNNEL_LINK=$(extract_link_for_process "$PM2_NAME")
    [[ -n "$TUNNEL_LINK" ]] && break
  done

  local COPIED_TAG=""
  if [[ -n "$TUNNEL_LINK" ]] && copy_to_clipboard "$TUNNEL_LINK"; then
    COPIED_TAG="[Copied]"
  fi

  printf "\n%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$GREEN" "$RESET"
  ok "ONLINE: ${PM2_NAME}"
  printf " %bProto%b : %b%s%b | %bPort%b : %b%s%b\n" "$WHITE" "$RESET" "$CYAN$BOLD" "${PROTOCOL_LOWER^^}" "$RESET" "$WHITE" "$RESET" "$CYAN$BOLD" "$TARGET_PORT_DISP" "$RESET"
  if [[ -n "$TUNNEL_LINK" ]]; then
    printf " %bLink%b  : " "$WHITE" "$RESET"
    clickable_link "$TUNNEL_LINK"
    [[ -n "$COPIED_TAG" ]] && printf " %b%s%b" "$YELLOW" "$COPIED_TAG" "$RESET"
    printf "\n"
  else
    warn "URL pending — press [C]."
  fi
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$GREEN" "$RESET"
  read -r -p "[Enter] menu..."
}

############################
# 9. [B] MULTI-TUNNEL CONTROL
############################
manage_tunnels() {
  clear
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
  printf "%b 🛠️  MULTI-TUNNEL CTRL%b\n" "$YELLOW$BOLD" "$RESET"
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"

  if ! command -v pm2 >/dev/null 2>&1; then
    warn "PM2 missing."
    read -r -p "[Enter] menu..."
    return 0
  fi

  local tunnels=() t_name idx=1
  while IFS= read -r t_name; do
    [[ -n "$t_name" ]] && tunnels+=("$t_name")
  done < <(get_pm2_tunnel_names)

  if [[ "${#tunnels[@]}" -eq 0 ]]; then
    info_msg "No tunnels found."
    read -r -p "[Enter] menu..."
    return 0
  fi

  for t_name in "${tunnels[@]}"; do
    printf " %b[%d]%b %b%s%b (%s)\n" "$WHITE$BOLD" "$idx" "$RESET" "$CYAN$BOLD" "$t_name" "$RESET" "$(get_pm2_proc_status "$t_name")"
    idx=$((idx + 1))
  done
  printf " %b[RA]%b Restart ALL\n" "$GREEN$BOLD" "$RESET"
  printf " %b[DA]%b Delete ALL + binary\n" "$RED$BOLD" "$RESET"
  printf " %b[0]%b  Back\n" "$DIM" "$RESET"
  printf "%b━━━━━━━━━━━━ ∆ ━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"

  read -r -p "Pick: " SEL
  [[ -z "$SEL" || "$SEL" == "0" ]] && return 0

  case "${SEL^^}" in
    RA)
      for t_name in "${tunnels[@]}"; do pm2 restart "$t_name" >/dev/null 2>&1 || true; done
      configure_pm2_startup
      ok "All tunnels restarted."
      read -r -p "[Enter] menu..."
      return 0
      ;;
    DA)
      for t_name in "${tunnels[@]}"; do pm2 delete "$t_name" >/dev/null 2>&1 || true; done
      pkill -f cloudflared >/dev/null 2>&1 || true
      rm -f /usr/local/bin/cloudflared
      configure_pm2_startup
      ok "All tunnels removed."
      read -r -p "[Enter] menu..."
      return 0
      ;;
  esac

  local TARGET_NAME="$SEL"
  if [[ "$SEL" =~ ^[0-9]+$ ]] && [[ "$SEL" -ge 1 && "$SEL" -le "${#tunnels[@]}" ]]; then
    TARGET_NAME="${tunnels[$((SEL - 1))]}"
 
