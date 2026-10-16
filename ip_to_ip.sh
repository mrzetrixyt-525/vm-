#!/usr/bin/env bash
# RGNODES™ IPv4 DNAT gateway / port-forwarder
# For a VPS you administer. This forwards TCP/UDP traffic arriving at this VPS
# to a second VPS. It does NOT assign the first VPS's IP address to the second.

set -Eeuo pipefail

readonly SCRIPT_NAME="RGNODES IP-to-IP"
readonly CONFIG_FILE="/etc/rgnodes-ip2ip.conf"
readonly SYSCTL_FILE="/etc/sysctl.d/99-rgnodes-ip2ip.conf"
readonly INSTALL_SCRIPT="/usr/local/sbin/rgnodes-ip2ip.sh"
readonly SYSTEMD_UNIT="/etc/systemd/system/rgnodes-ip2ip.service"
readonly NAT_CHAIN="RGNODES_IP2IP"
readonly POST_CHAIN="RGNODES_IP2IP_POST"
readonly FWD_CHAIN="RGNODES_IP2IP_FWD"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_CYAN=$'\033[1;36m'; C_BLUE=$'\033[1;34m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BLUE=''
fi

log_info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_success() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error()   { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

on_error() {
  local rc=$?
  log_error "Command failed at line ${BASH_LINENO[0]:-unknown} (exit ${rc}). Check the message above."
  exit "$rc"
}
trap on_error ERR

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_error "Run this script as root: sudo ./ip_to_ip.sh"
    exit 1
  fi
}

need_commands() {
  local cmd
  for cmd in ip iptables awk sed sort paste install cut grep tr mktemp chmod readlink systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      if [[ "$cmd" == "systemctl" ]]; then
        log_warn "systemctl was not found; automatic reboot persistence may not be available."
      else
        log_error "Required command not found: $cmd"
        exit 1
      fi
    fi
  done
  if ! iptables -w -L >/dev/null 2>&1; then
    log_error "iptables is not usable in this VPS/container. Check provider restrictions and kernel capabilities."
    exit 1
  fi
}

valid_ipv4() {
  local ipaddr=$1 octet
  local -a octets=()
  [[ "$ipaddr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ipaddr"
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
  [[ "$ipaddr" != "0.0.0.0" && "$ipaddr" != "255.255.255.255" ]] || return 1
  # Reject loopback and multicast ranges; ordinary private IPs are allowed.
  local first_octet=$((10#${octets[0]}))
  (( first_octet != 127 && first_octet < 224 )) || return 1
  return 0
}

valid_port() {
  local p=$1
  [[ "$p" =~ ^[0-9]{1,5}$ ]] || return 1
  (( 10#$p >= 1 && 10#$p <= 65535 ))
}

get_default_interface() {
  ip -4 route show default 2>/dev/null | awk '
    NR == 1 { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }
  '
}

get_ssh_ports() {
  local ports=''
  local -a _ssh_arr=()
  if command -v sshd >/dev/null 2>&1; then
    ports=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -un | paste -sd, - || true)
  elif [[ -x /usr/sbin/sshd ]]; then
    ports=$(/usr/sbin/sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -un | paste -sd, - || true)
  fi
  [[ -n "$ports" ]] || ports='22'
  # Validate sshd output before using it in iptables arguments.
  local item
  IFS=',' read -r -a _ssh_arr <<< "$ports"
  for item in "${_ssh_arr[@]}"; do
    valid_port "$item" || { ports='22'; break; }
  done
  printf '%s' "$ports"
}

ensure_chain() {
  local table=$1 chain=$2
  if ! iptables -w -t "$table" -S "$chain" >/dev/null 2>&1; then
    iptables -w -t "$table" -N "$chain"
  fi
}

remove_chain_jumps() {
  local table=$1 parent=$2 chain=$3
  while iptables -w -t "$table" -C "$parent" -j "$chain" >/dev/null 2>&1; do
    iptables -w -t "$table" -D "$parent" -j "$chain"
  done
}

attach_chain_once() {
  local table=$1 parent=$2 chain=$3
  remove_chain_jumps "$table" "$parent" "$chain"
  iptables -w -t "$table" -I "$parent" 1 -j "$chain"
}

cleanup_rules() {
  log_info "Removing only RGNODES-managed iptables jumps and rules..."
  remove_chain_jumps nat PREROUTING "$NAT_CHAIN" || true
  remove_chain_jumps nat POSTROUTING "$POST_CHAIN" || true
  remove_chain_jumps filter FORWARD "$FWD_CHAIN" || true
  for spec in "nat:$NAT_CHAIN" "nat:$POST_CHAIN" "filter:$FWD_CHAIN"; do
    local table=${spec%%:*} chain=${spec#*:}
    if iptables -w -t "$table" -S "$chain" >/dev/null 2>&1; then
      iptables -w -t "$table" -F "$chain" || true
    fi
  done
  log_success "RGNODES forwarding rules have been detached. IPv4 forwarding was left unchanged."
}

apply_rules() {
  local port
  local -a port_arr=()

  [[ -n "${TARGET_IP:-}" ]] || { log_error "TARGET_IP is missing from config."; return 1; }
  valid_ipv4 "$TARGET_IP" || { log_error "Invalid target IPv4 in config: $TARGET_IP"; return 1; }
  [[ -n "${WAN_IF:-}" ]] || WAN_IF=$(get_default_interface)
  [[ -n "$WAN_IF" ]] || { log_error "Cannot detect the public-facing interface. Set WAN_IF in $CONFIG_FILE."; return 1; }
  ip link show dev "$WAN_IF" >/dev/null 2>&1 || { log_error "Interface does not exist: $WAN_IF"; return 1; }

  if ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TARGET_IP"; then
    log_error "Target IP $TARGET_IP is assigned locally to this VPS; refusing a routing loop."
    return 1
  fi
  if ! ip -4 route get "$TARGET_IP" >/dev/null 2>&1; then
    log_error "No IPv4 route to target $TARGET_IP. Check the IP and VPS routing."
    return 1
  fi

  # Turn on forwarding for this boot and persist the one required sysctl only.
  install -d -m 0755 /etc/sysctl.d
  printf '%s\n' 'net.ipv4.ip_forward = 1' > "$SYSCTL_FILE"
  chmod 0644 "$SYSCTL_FILE"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  # Detach our own jumps before refreshing chains. Never flush global NAT/FORWARD chains.
  ensure_chain nat "$NAT_CHAIN"
  ensure_chain nat "$POST_CHAIN"
  ensure_chain filter "$FWD_CHAIN"
  remove_chain_jumps nat PREROUTING "$NAT_CHAIN"
  remove_chain_jumps nat POSTROUTING "$POST_CHAIN"
  remove_chain_jumps filter FORWARD "$FWD_CHAIN"
  iptables -w -t nat -F "$NAT_CHAIN"
  iptables -w -t nat -F "$POST_CHAIN"
  iptables -w -t filter -F "$FWD_CHAIN"

  if [[ "$MODE" == "all" ]]; then
    [[ -n "${SSH_PORTS:-}" ]] || SSH_PORTS='22'
    # Intentionally keep SSH port(s) on the entry VPS to avoid locking out its admin.
    iptables -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p tcp -m multiport ! --dports "$SSH_PORTS" \
      -m comment --comment 'RGNODES IP2IP all TCP except SSH' -j DNAT --to-destination "$TARGET_IP"
    iptables -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p udp \
      -m comment --comment 'RGNODES IP2IP all UDP' -j DNAT --to-destination "$TARGET_IP"

    iptables -w -t filter -A "$FWD_CHAIN" -d "$TARGET_IP" -p tcp -m conntrack --ctstate DNAT \
      -m multiport ! --dports "$SSH_PORTS" -j ACCEPT
    iptables -w -t filter -A "$FWD_CHAIN" -d "$TARGET_IP" -p udp -m conntrack --ctstate DNAT -j ACCEPT
    iptables -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -p tcp \
      -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m multiport ! --sports "$SSH_PORTS" -j ACCEPT
    iptables -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -p udp \
      -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j ACCEPT
  elif [[ "$MODE" == "ports" ]]; then
    [[ -n "${PORTS_CSV:-}" ]] || { log_error "PORTS_CSV is missing from config."; return 1; }
    IFS=',' read -r -a port_arr <<< "$PORTS_CSV"
    for port in "${port_arr[@]}"; do
      valid_port "$port" || { log_error "Invalid port in config: $port"; return 1; }
      iptables -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p tcp --dport "$port" \
        -m comment --comment "RGNODES IP2IP TCP $port" -j DNAT --to-destination "$TARGET_IP:$port"
      iptables -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p udp --dport "$port" \
        -m comment --comment "RGNODES IP2IP UDP $port" -j DNAT --to-destination "$TARGET_IP:$port"

      iptables -w -t filter -A "$FWD_CHAIN" -d "$TARGET_IP" -p tcp --dport "$port" \
        -m conntrack --ctstate DNAT -j ACCEPT
      iptables -w -t filter -A "$FWD_CHAIN" -d "$TARGET_IP" -p udp --dport "$port" \
        -m conntrack --ctstate DNAT -j ACCEPT
      iptables -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -p tcp --sport "$port" \
        -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j ACCEPT
      iptables -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -p udp --sport "$port" \
        -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j ACCEPT
    done
  else
    log_error "Unsupported MODE in config: ${MODE:-unset}"
    return 1
  fi

  # Make replies return through this gateway so conntrack can reverse the DNAT.
  iptables -w -t nat -A "$POST_CHAIN" -d "$TARGET_IP" -m conntrack --ctstate DNAT \
    -m comment --comment 'RGNODES IP2IP return path' -j MASQUERADE

  # Attach only after the managed chains are fully populated.
  attach_chain_once nat PREROUTING "$NAT_CHAIN"
  attach_chain_once nat POSTROUTING "$POST_CHAIN"
  attach_chain_once filter FORWARD "$FWD_CHAIN"

  log_success "Rules applied on interface $WAN_IF -> $TARGET_IP"
  if [[ "$MODE" == "all" ]]; then
    log_warn "ALL mode forwards TCP except SSH port(s) $SSH_PORTS, plus all UDP. ICMP and other IP protocols are not forwarded."
  else
    log_info "Forwarded TCP + UDP ports: $PORTS_CSV"
  fi
}

save_config() {
  local tmp
  tmp=$(mktemp /etc/rgnodes-ip2ip.conf.XXXXXX)
  umask 077
  {
    printf 'TARGET_IP=%q\n' "$TARGET_IP"
    printf 'MODE=%q\n' "$MODE"
    printf 'PORTS_CSV=%q\n' "${PORTS_CSV:-}"
    printf 'SSH_PORTS=%q\n' "${SSH_PORTS:-22}"
    printf 'WAN_IF=%q\n' "$WAN_IF"
  } > "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$CONFIG_FILE"
}

setup_persistence() {
  if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
    log_warn "systemd is not running; forwarding works now, but automatic reboot persistence was not configured."
    log_warn "Use a systemd-based VPS or configure this script to run with your OS's firewall persistence manager."
    return 0
  fi

  local self_real installed_real
  self_real=$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")
  installed_real=$(readlink -f -- "$INSTALL_SCRIPT" 2>/dev/null || true)
  if [[ "$self_real" != "$installed_real" ]]; then
    install -D -m 0750 -- "$0" "$INSTALL_SCRIPT"
  fi

  cat > "$SYSTEMD_UNIT" <<'UNIT'
[Unit]
Description=RGNODES IPv4 IP-to-IP forwarding
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rgnodes-ip2ip.sh --restore
ExecStop=/usr/local/sbin/rgnodes-ip2ip.sh --stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  chmod 0644 "$SYSTEMD_UNIT"
  systemctl daemon-reload
  systemctl enable rgnodes-ip2ip.service >/dev/null
  if systemctl restart rgnodes-ip2ip.service >/dev/null 2>&1; then
    log_success "Reboot persistence enabled: rgnodes-ip2ip.service"
  else
    # On first install restart may report inactive; start it and capture actual failure.
    if systemctl start rgnodes-ip2ip.service >/dev/null 2>&1; then
      log_success "Reboot persistence enabled: rgnodes-ip2ip.service"
    else
      log_error "Rules are active now, but systemd could not start the persistence service."
      log_error "Inspect: journalctl -u rgnodes-ip2ip.service -n 50 --no-pager"
      return 1
    fi
  fi
}

show_banner() {
  printf '\n%s==============================================================%s\n' "$C_CYAN" "$C_RESET"
  printf '%s    RGNODES™ IPv4 IP-to-IP NAT / Port Forwarding%s\n' "$C_CYAN" "$C_RESET"
  printf '%s==============================================================%s\n\n' "$C_CYAN" "$C_RESET"
  printf 'This makes the first VPS a gateway; it does not move/assign its IP to the target VPS.\n\n'
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage:
  sudo ./ip_to_ip.sh          Interactive setup
  sudo /usr/local/sbin/rgnodes-ip2ip.sh --restore   Apply saved config
  sudo /usr/local/sbin/rgnodes-ip2ip.sh --stop      Detach managed rules

The script only forwards IPv4 TCP/UDP. In all mode, detected SSH TCP ports are excluded.
HELP
    return 0
  fi

  need_root
  need_commands

  case "${1:-}" in
    --restore)
      [[ -r "$CONFIG_FILE" ]] || { log_error "Missing saved config: $CONFIG_FILE"; exit 1; }
      # Root-owned 0600 config generated only by this script.
      # shellcheck disable=SC1090
      source "$CONFIG_FILE"
      apply_rules
      ;;
    --stop)
      cleanup_rules
      ;;
    '')
      show_banner
      local TARGET_INPUT PORTS_INPUT DEFAULT_IF
      read -r -p '[?] Target VPS IPv4 address: ' TARGET_INPUT
      if ! valid_ipv4 "$TARGET_INPUT"; then
        log_error "Invalid IPv4 address. Example: 203.0.113.10"
        exit 1
      fi
      if ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TARGET_INPUT"; then
        log_error "Target IP is assigned to this VPS. Enter the other VPS address."
        exit 1
      fi
      if ! ip -4 route get "$TARGET_INPUT" >/dev/null 2>&1; then
        log_error "No route to target VPS IP $TARGET_INPUT. Verify the IP/network."
        exit 1
      fi

      DEFAULT_IF=$(get_default_interface)
      if [[ -z "$DEFAULT_IF" ]]; then
        DEFAULT_IF=$(ip -4 route get "$TARGET_INPUT" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
      fi
      [[ -n "$DEFAULT_IF" ]] || { log_error "Could not detect a public-facing interface."; exit 1; }
      read -r -p "[?] Incoming/public interface [$DEFAULT_IF]: " WAN_IF
      WAN_IF=${WAN_IF:-$DEFAULT_IF}
      if ! ip link show dev "$WAN_IF" >/dev/null 2>&1; then
        log_error "Interface not found: $WAN_IF"
        exit 1
      fi

      read -r -p "[?] Ports to forward (e.g. 80,443,25565) or 'all': " PORTS_INPUT
      PORTS_INPUT=$(printf '%s' "$PORTS_INPUT" | tr -d '[:space:]')
      if [[ "$PORTS_INPUT" == "all" ]]; then
        MODE='all'
        PORTS_CSV=''
        SSH_PORTS=$(get_ssh_ports)
        log_warn "ALL mode is intentionally broad. TCP SSH port(s) $SSH_PORTS will remain on this VPS."
        read -r -p "Type FORWARD-ALL to continue: " CONFIRM
        [[ "$CONFIRM" == 'FORWARD-ALL' ]] || { log_info "Cancelled."; exit 0; }
      else
        MODE='ports'
        if [[ -z "$PORTS_INPUT" || ! "$PORTS_INPUT" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
          log_error "Use comma-separated port numbers, e.g. 80,443,25565, or type all."
          exit 1
        fi
        local -a raw_ports=() unique_ports=()
        local p
        declare -A seen_ports=()
        IFS=',' read -r -a raw_ports <<< "$PORTS_INPUT"
        for p in "${raw_ports[@]}"; do
          if ! valid_port "$p"; then
            log_error "Invalid port number: $p (valid range: 1-65535)."
            exit 1
          fi
          # Canonicalize leading zeroes, then deduplicate.
          p=$((10#$p))
          if [[ -z "${seen_ports[$p]+x}" ]]; then
            seen_ports[$p]=1
            unique_ports+=("$p")
          fi
        done
        ((${#unique_ports[@]} > 0)) || { log_error "No valid ports supplied."; exit 1; }
        PORTS_CSV=$(IFS=,; printf '%s' "${unique_ports[*]}")
        SSH_PORTS=$(get_ssh_ports)
        log_info "Will forward TCP + UDP port(s): $PORTS_CSV"
        local -a ssh_arr=() selected_arr=() matched_ssh=()
        IFS=',' read -r -a ssh_arr <<< "$SSH_PORTS"
        IFS=',' read -r -a selected_arr <<< "$PORTS_CSV"
        local selected_port ssh_port
        for selected_port in "${selected_arr[@]}"; do
          for ssh_port in "${ssh_arr[@]}"; do
            if [[ "$selected_port" == "$ssh_port" ]]; then matched_ssh+=("$ssh_port"); fi
          done
        done
        if ((${#matched_ssh[@]} > 0)); then
          local matched_csv
          matched_csv=$(IFS=,; printf '%s' "${matched_ssh[*]}")
          log_warn "Your selected list includes detected SSH port(s): $matched_csv. New SSH connections may go to the target instead of this VPS."
          read -r -p "Type CONTINUE to apply these ports anyway: " CONFIRM
          [[ "$CONFIRM" == 'CONTINUE' ]] || { log_info "Cancelled."; exit 0; }
        fi
      fi

      TARGET_IP=$TARGET_INPUT
      save_config
      apply_rules
      setup_persistence
      printf '\n'
      log_success "Setup finished. Entry VPS IP is still the public endpoint; target is $TARGET_IP."
      log_info "Test from an external network, and ensure the target VPS/provider firewall permits the forwarded ports."
      log_info "Target services will usually see the gateway VPS as the source IP because return-path MASQUERADE is enabled."
      ;;
    *)
      log_error "Unknown option: $1"
      printf 'Use --help for usage.\n' >&2
      exit 2
      ;;
  esac
}

main "$@"
