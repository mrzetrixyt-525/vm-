#!/usr/bin/env bash
# RGNODES™ IP-to-IP gateway / TCP+UDP port forwarder — v4.0.0
# Linux only. Requires root plus working kernel netfilter/CAP_NET_ADMIN access.
# This forwards traffic through VPS A to VPS B; it does not transfer A's IP to B.

set -Eeuo pipefail

readonly SCRIPT_NAME='RGNODES IP-to-IP'
readonly CONFIG_FILE='/etc/rgnodes-ip2ip.conf'
readonly SYSCTL_FILE='/etc/sysctl.d/99-rgnodes-ip2ip.conf'
readonly INSTALL_SCRIPT='/usr/local/sbin/rgnodes-ip2ip.sh'
readonly SYSTEMD_UNIT='/etc/systemd/system/rgnodes-ip2ip.service'
readonly NAT_CHAIN='RGNODES_IP2IP'
readonly POST_CHAIN='RGNODES_IP2IP_POST'
readonly FWD_CHAIN='RGNODES_IP2IP_FWD'
readonly NFT_TABLE='rgnodes_ip2ip'

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_CYAN=$'\033[1;36m'; C_BLUE=$'\033[1;34m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BLUE=''
fi

BACKEND=''
IPTABLES_BIN=''
NFT_BIN=''

log_info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_success() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error()   { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

on_error() {
  local rc=$?
  log_error "Command failed at line ${BASH_LINENO[0]:-unknown} (exit ${rc}). No universal script can bypass kernel/provider firewall restrictions."
  exit "$rc"
}
trap on_error ERR

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_error 'Run as root: sudo bash ./ip_to_ip.sh'
    exit 1
  fi
}

need_base_commands() {
  local cmd
  for cmd in bash ip awk grep cut tr sort paste install chmod mktemp sed sysctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Required command is missing: $cmd. Install the matching OS package (usually iproute2/iproute and coreutils)."
      exit 1
    fi
  done
}

valid_ipv4() {
  local ipaddr=${1:-} octet first
  local -a octets=()
  [[ "$ipaddr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ipaddr"
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
  [[ "$ipaddr" != '0.0.0.0' && "$ipaddr" != '255.255.255.255' ]] || return 1
  first=$((10#${octets[0]}))
  (( first != 0 && first != 127 && first < 224 )) || return 1
  return 0
}

valid_port() {
  local p=${1:-}
  [[ "$p" =~ ^[0-9]{1,5}$ ]] || return 1
  (( 10#$p >= 1 && 10#$p <= 65535 ))
}

get_default_interface() {
  ip -4 route show default 2>/dev/null | awk 'NR == 1 { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }'
}

get_ssh_ports() {
  local ports='' bin item
  local -a ssh_arr=()
  bin=$(command -v sshd 2>/dev/null || true)
  [[ -n "$bin" ]] || [[ ! -x /usr/sbin/sshd ]] || bin=/usr/sbin/sshd
  if [[ -n "$bin" ]]; then
    ports=$("$bin" -T 2>/dev/null | awk '$1 == "port" && $2 ~ /^[0-9]+$/ {print $2}' | sort -un | paste -sd, - || true)
  fi
  [[ -n "$ports" ]] || ports='22'
  IFS=',' read -r -a ssh_arr <<< "$ports"
  for item in "${ssh_arr[@]}"; do
    valid_port "$item" || { ports='22'; break; }
  done
  printf '%s' "$ports"
}

iptables_can_write() {
  local bin=$1 nat_probe="RGP$$" filter_probe="RGQ$$"
  "$bin" -w -t nat -N "$nat_probe" >/dev/null 2>&1 || return 1
  "$bin" -w -t nat -X "$nat_probe" >/dev/null 2>&1 || return 1
  "$bin" -w -t filter -N "$filter_probe" >/dev/null 2>&1 || return 1
  "$bin" -w -t filter -X "$filter_probe" >/dev/null 2>&1 || return 1
  return 0
}

nft_can_write() {
  local bin=$1 probe="rgnodes_probe_$$"
  "$bin" list ruleset >/dev/null 2>&1 || return 1
  "$bin" add table ip "$probe" >/dev/null 2>&1 || return 1
  "$bin" delete table ip "$probe" >/dev/null 2>&1 || return 1
  return 0
}

has_backend_binary() {
  command -v iptables >/dev/null 2>&1 || command -v iptables-nft >/dev/null 2>&1 || \
    command -v iptables-legacy >/dev/null 2>&1 || command -v nft >/dev/null 2>&1
}

install_backend_tools() {
  log_info 'Trying to install firewall command packages using this OS package manager...'
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || log_warn 'Package index update failed; trying currently available package lists.'
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables nftables
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y iptables nftables
  elif command -v yum >/dev/null 2>&1; then
    yum install -y iptables nftables
  elif command -v apk >/dev/null 2>&1; then
    apk add iptables nftables
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install iptables nftables
  else
    log_error 'Automatic package installation is not supported for this package manager.'
    log_info 'Install either iptables or nftables with your OS package manager, then rerun the script.'
    return 1
  fi
}

select_backend() {
  local preferred=${1:-} candidate found=''
  local -a iptables_candidates=()
  if [[ -n "$preferred" ]]; then
    case "$preferred" in
      iptables)
        candidate=${SAVED_IPTABLES_BIN:-}
        if [[ -n "$candidate" && -x "$candidate" ]] && iptables_can_write "$candidate"; then
          BACKEND='iptables'; IPTABLES_BIN=$candidate; return 0
        fi
        log_error 'The saved iptables backend is no longer writable. Refusing to silently switch firewall backends.'
        return 1
        ;;
      nft)
        candidate=${SAVED_NFT_BIN:-}
        if [[ -z "$candidate" ]]; then candidate=$(command -v nft 2>/dev/null || true); fi
        if [[ -n "$candidate" && -x "$candidate" ]] && nft_can_write "$candidate"; then
          BACKEND='nft'; NFT_BIN=$candidate; return 0
        fi
        log_error 'The saved nftables backend is no longer writable. Refusing to silently switch firewall backends.'
        return 1
        ;;
      *) log_error "Unknown saved firewall backend: $preferred"; return 1 ;;
    esac
  fi

  for candidate in iptables iptables-nft iptables-legacy; do
    found=$(command -v "$candidate" 2>/dev/null || true)
    [[ -n "$found" ]] || continue
    if iptables_can_write "$found"; then
      BACKEND='iptables'; IPTABLES_BIN=$found
      return 0
    fi
  done

  found=$(command -v nft 2>/dev/null || true)
  if [[ -n "$found" ]] && nft_can_write "$found"; then
    BACKEND='nft'; NFT_BIN=$found
    return 0
  fi

  log_error 'No usable firewall backend found: iptables could not create/delete test NAT+filter chains, and nftables could not create/delete a test table.'
  log_error 'This often means an unprivileged LXC/OpenVZ/container, missing CAP_NET_ADMIN, blocked kernel netfilter modules, or provider policy. Installing a command alone cannot fix blocked kernel permissions.'
  log_info 'Check: command -v iptables nft; iptables -t nat -L; nft list ruleset; systemd-detect-virt --container 2>/dev/null || true'
  log_info 'Ask the provider to enable IPv4 NAT/netfilter and CAP_NET_ADMIN, or use a KVM/QEMU VPS. The forwarding rules must be applied on a Linux host that owns the public IP.'
  return 1
}

ensure_chain() {
  local table=$1 chain=$2
  if ! "$IPTABLES_BIN" -w -t "$table" -S "$chain" >/dev/null 2>&1; then
    "$IPTABLES_BIN" -w -t "$table" -N "$chain"
  fi
}

remove_chain_jumps() {
  local table=$1 parent=$2 chain=$3
  while "$IPTABLES_BIN" -w -t "$table" -C "$parent" -j "$chain" >/dev/null 2>&1; do
    "$IPTABLES_BIN" -w -t "$table" -D "$parent" -j "$chain"
  done
}

attach_chain_once() {
  local table=$1 parent=$2 chain=$3
  remove_chain_jumps "$table" "$parent" "$chain"
  "$IPTABLES_BIN" -w -t "$table" -I "$parent" 1 -j "$chain"
}

cleanup_iptables() {
  log_info 'Removing only RGNODES-managed iptables rules...'
  remove_chain_jumps nat PREROUTING "$NAT_CHAIN" || true
  remove_chain_jumps nat POSTROUTING "$POST_CHAIN" || true
  remove_chain_jumps filter FORWARD "$FWD_CHAIN" || true
  local spec table chain
  for spec in "nat:$NAT_CHAIN" "nat:$POST_CHAIN" "filter:$FWD_CHAIN"; do
    table=${spec%%:*}; chain=${spec#*:}
    if "$IPTABLES_BIN" -w -t "$table" -S "$chain" >/dev/null 2>&1; then
      "$IPTABLES_BIN" -w -t "$table" -F "$chain" || true
    fi
  done
  log_success 'RGNODES iptables rules detached. Other firewall rules were not flushed.'
}

apply_iptables() {
  local port ssh_port
  local -a port_arr=() ssh_arr=()
  ensure_chain nat "$NAT_CHAIN"
  ensure_chain nat "$POST_CHAIN"
  ensure_chain filter "$FWD_CHAIN"
  remove_chain_jumps nat PREROUTING "$NAT_CHAIN"
  remove_chain_jumps nat POSTROUTING "$POST_CHAIN"
  remove_chain_jumps filter FORWARD "$FWD_CHAIN"
  "$IPTABLES_BIN" -w -t nat -F "$NAT_CHAIN"
  "$IPTABLES_BIN" -w -t nat -F "$POST_CHAIN"
  "$IPTABLES_BIN" -w -t filter -F "$FWD_CHAIN"

  if [[ "$MODE" == 'all' ]]; then
    [[ -n "${SSH_PORTS:-}" ]] || SSH_PORTS='22'
    IFS=',' read -r -a ssh_arr <<< "$SSH_PORTS"
    # Return only from our own NAT chain for each SSH port; avoid multiport extension limits.
    for ssh_port in "${ssh_arr[@]}"; do
      valid_port "$ssh_port" || { log_error "Invalid SSH port detected: $ssh_port"; return 1; }
      "$IPTABLES_BIN" -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p tcp --dport "$ssh_port" -j RETURN
    done
    "$IPTABLES_BIN" -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p tcp \
      -m comment --comment 'RGNODES IP2IP all TCP except SSH' -j DNAT --to-destination "$TARGET_IP"
    "$IPTABLES_BIN" -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p udp \
      -m comment --comment 'RGNODES IP2IP all UDP' -j DNAT --to-destination "$TARGET_IP"
    "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -i "$WAN_IF" -d "$TARGET_IP" -p tcp -m conntrack --ctstatus DNAT -j ACCEPT
    "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -i "$WAN_IF" -d "$TARGET_IP" -p udp -m conntrack --ctstatus DNAT -j ACCEPT
    "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  elif [[ "$MODE" == 'ports' ]]; then
    [[ -n "${PORTS_CSV:-}" ]] || { log_error 'PORTS_CSV is missing from config.'; return 1; }
    IFS=',' read -r -a port_arr <<< "$PORTS_CSV"
    for port in "${port_arr[@]}"; do
      valid_port "$port" || { log_error "Invalid configured port: $port"; return 1; }
      "$IPTABLES_BIN" -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p tcp --dport "$port" \
        -m comment --comment "RGNODES IP2IP TCP $port" -j DNAT --to-destination "$TARGET_IP:$port"
      "$IPTABLES_BIN" -w -t nat -A "$NAT_CHAIN" -i "$WAN_IF" -p udp --dport "$port" \
        -m comment --comment "RGNODES IP2IP UDP $port" -j DNAT --to-destination "$TARGET_IP:$port"
      "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -i "$WAN_IF" -d "$TARGET_IP" -p tcp --dport "$port" -m conntrack --ctstatus DNAT -j ACCEPT
      "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -i "$WAN_IF" -d "$TARGET_IP" -p udp --dport "$port" -m conntrack --ctstatus DNAT -j ACCEPT
    done
    "$IPTABLES_BIN" -w -t filter -A "$FWD_CHAIN" -s "$TARGET_IP" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  else
    log_error "Unsupported MODE: ${MODE:-unset}"; return 1
  fi

  "$IPTABLES_BIN" -w -t nat -A "$POST_CHAIN" -d "$TARGET_IP" -m conntrack --ctstatus DNAT \
    -m comment --comment 'RGNODES IP2IP return path' -j MASQUERADE
  attach_chain_once nat PREROUTING "$NAT_CHAIN"
  attach_chain_once nat POSTROUTING "$POST_CHAIN"
  attach_chain_once filter FORWARD "$FWD_CHAIN"
}

nft_cleanup() {
  if "$NFT_BIN" list table ip "$NFT_TABLE" >/dev/null 2>&1; then
    "$NFT_BIN" delete table ip "$NFT_TABLE"
  fi
  log_success 'RGNODES-managed nftables table removed. Other tables were not changed.'
}

apply_nft() {
  local port ssh_port rules_file
  local -a port_arr=() ssh_arr=()
  [[ -n "${SSH_PORTS:-}" ]] || SSH_PORTS='22'
  rules_file=$(mktemp /tmp/rgnodes-ip2ip-nft.XXXXXX)

  # Replace only our own dedicated table. The rest of the host's nftables ruleset is untouched.
  local table_exists=0
  if "$NFT_BIN" list table ip "$NFT_TABLE" >/dev/null 2>&1; then
    if "$NFT_BIN" list chain ip "$NFT_TABLE" prerouting >/dev/null 2>&1 && \
       "$NFT_BIN" list chain ip "$NFT_TABLE" postrouting >/dev/null 2>&1 && \
       "$NFT_BIN" list chain ip "$NFT_TABLE" forward >/dev/null 2>&1; then
      table_exists=1
    else
      # A partial table from an interrupted previous setup is ours by reserved name; recreate it.
      "$NFT_BIN" delete table ip "$NFT_TABLE"
    fi
  fi
  {
    if (( table_exists )); then
      printf 'flush chain ip %s prerouting\n' "$NFT_TABLE"
      printf 'flush chain ip %s postrouting\n' "$NFT_TABLE"
      printf 'flush chain ip %s forward\n' "$NFT_TABLE"
    else
      printf 'add table ip %s\n' "$NFT_TABLE"
      printf 'add chain ip %s prerouting { type nat hook prerouting priority -100; }\n' "$NFT_TABLE"
      printf 'add chain ip %s postrouting { type nat hook postrouting priority 100; }\n' "$NFT_TABLE"
      printf 'add chain ip %s forward { type filter hook forward priority -5; policy accept; }\n' "$NFT_TABLE"
    fi

    if [[ "$MODE" == 'all' ]]; then
      IFS=',' read -r -a ssh_arr <<< "$SSH_PORTS"
      # Return before DNAT for every detected SSH port so admin access stays on VPS A.
      for ssh_port in "${ssh_arr[@]}"; do
        valid_port "$ssh_port" || { rm -f "$rules_file"; log_error "Invalid SSH port detected: $ssh_port"; return 1; }
        printf 'add rule ip %s prerouting iifname "%s" tcp dport %s return\n' "$NFT_TABLE" "$WAN_IF" "$ssh_port"
      done
      printf 'add rule ip %s prerouting iifname "%s" tcp dnat to %s\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP"
      printf 'add rule ip %s prerouting iifname "%s" udp dnat to %s\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP"
      printf 'add rule ip %s forward iifname "%s" ip daddr %s tcp accept\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP"
      printf 'add rule ip %s forward iifname "%s" ip daddr %s udp accept\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP"
    elif [[ "$MODE" == 'ports' ]]; then
      [[ -n "${PORTS_CSV:-}" ]] || { rm -f "$rules_file"; log_error 'PORTS_CSV is missing from config.'; return 1; }
      IFS=',' read -r -a port_arr <<< "$PORTS_CSV"
      for port in "${port_arr[@]}"; do
        valid_port "$port" || { rm -f "$rules_file"; log_error "Invalid configured port: $port"; return 1; }
        printf 'add rule ip %s prerouting iifname "%s" tcp dport %s dnat to %s:%s\n' "$NFT_TABLE" "$WAN_IF" "$port" "$TARGET_IP" "$port"
        printf 'add rule ip %s prerouting iifname "%s" udp dport %s dnat to %s:%s\n' "$NFT_TABLE" "$WAN_IF" "$port" "$TARGET_IP" "$port"
        printf 'add rule ip %s forward iifname "%s" ip daddr %s tcp dport %s accept\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP" "$port"
        printf 'add rule ip %s forward iifname "%s" ip daddr %s udp dport %s accept\n' "$NFT_TABLE" "$WAN_IF" "$TARGET_IP" "$port"
      done
    else
      rm -f "$rules_file"
      log_error "Unsupported MODE: ${MODE:-unset}"
      return 1
    fi

    printf 'add rule ip %s postrouting ip daddr %s ct status dnat masquerade\n' "$NFT_TABLE" "$TARGET_IP"
    printf 'add rule ip %s forward ip saddr %s ct state established,related accept\n' "$NFT_TABLE" "$TARGET_IP"
  } > "$rules_file"

  if ! "$NFT_BIN" -f "$rules_file"; then
    rm -f "$rules_file"
    log_error "nftables rejected the generated rules. Run 'nft -a list ruleset' and inspect the provider/kernel firewall support."
    return 1
  fi
  rm -f "$rules_file"
}
apply_rules() {
  [[ -n "${TARGET_IP:-}" ]] || { log_error 'TARGET_IP is missing from config.'; return 1; }
  valid_ipv4 "$TARGET_IP" || { log_error "Invalid target IPv4: $TARGET_IP"; return 1; }
  [[ -n "${WAN_IF:-}" ]] || WAN_IF=$(get_default_interface)
  [[ -n "$WAN_IF" ]] || { log_error "Cannot detect the incoming interface. Set WAN_IF in $CONFIG_FILE."; return 1; }
  [[ "$WAN_IF" =~ ^[[:alnum:]_.:-]{1,15}$ ]] || { log_error "Unsafe/invalid interface name: $WAN_IF"; return 1; }
  ip link show dev "$WAN_IF" >/dev/null 2>&1 || { log_error "Interface does not exist: $WAN_IF"; return 1; }
  if ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TARGET_IP"; then
    log_error 'Target IP is assigned to this VPS; refusing a routing loop.'; return 1
  fi
  if ! ip -4 route get "$TARGET_IP" >/dev/null 2>&1; then
    log_error "No IPv4 route to target $TARGET_IP. Check target IP/routing."; return 1
  fi

  install -d -m 0755 /etc/sysctl.d
  printf '%s\n' 'net.ipv4.ip_forward = 1' > "$SYSCTL_FILE"
  chmod 0644 "$SYSCTL_FILE"
  if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null; then
    log_error 'Kernel refused net.ipv4.ip_forward=1. This container/provider may not allow changing network sysctls.'
    return 1
  fi

  if [[ "$BACKEND" == 'iptables' ]]; then
    apply_iptables
  elif [[ "$BACKEND" == 'nft' ]]; then
    apply_nft
  else
    log_error "Unsupported backend: $BACKEND"; return 1
  fi

  log_success "Forwarding rules applied using $BACKEND: $WAN_IF -> $TARGET_IP"
  if [[ "$MODE" == 'all' ]]; then
    log_warn "ALL mode forwards TCP except SSH port(s) ${SSH_PORTS:-22}, plus all UDP. It does not forward ICMP or every IP protocol."
  else
    log_info "Forwarded TCP + UDP port(s): $PORTS_CSV"
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
    printf 'BACKEND=%q\n' "$BACKEND"
    printf 'IPTABLES_BIN=%q\n' "$IPTABLES_BIN"
    printf 'NFT_BIN=%q\n' "$NFT_BIN"
  } > "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$CONFIG_FILE"
}

setup_persistence() {
  # The script must be a real file before it can be installed for boot-time restores.
  if [[ ! -f "${BASH_SOURCE[0]:-}" || ! -r "${BASH_SOURCE[0]:-}" ]]; then
    log_warn 'The script was piped to bash/process substitution; it cannot safely copy itself for reboot persistence.'
    log_warn "Rules are active now and config is saved at $CONFIG_FILE. Download to a real file and rerun to enable persistence."
    return 0
  fi
  install -D -m 0750 -- "${BASH_SOURCE[0]}" "$INSTALL_SCRIPT"

  if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
    # OpenRC (commonly Alpine/Gentoo) supports local boot scripts.
    if command -v rc-update >/dev/null 2>&1 && [[ -d /etc/local.d ]]; then
      install -D -m 0750 /dev/null /etc/local.d/rgnodes-ip2ip.start
      cat > /etc/local.d/rgnodes-ip2ip.start <<'OPENRC'
#!/bin/sh
/usr/local/sbin/rgnodes-ip2ip.sh --restore
OPENRC
      chmod 0750 /etc/local.d/rgnodes-ip2ip.start
      rc-update add local default >/dev/null 2>&1 || true
      log_success 'OpenRC local boot persistence configured.'
      return 0
    fi
    log_warn 'systemd/OpenRC boot service was not found; rules are active now, but automatic reboot persistence was not configured.'
    log_warn "Saved config: $CONFIG_FILE. Configure your OS boot manager to run $INSTALL_SCRIPT --restore."
    return 0
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
  if systemctl restart rgnodes-ip2ip.service >/dev/null 2>&1 || systemctl start rgnodes-ip2ip.service >/dev/null 2>&1; then
    log_success 'Reboot persistence enabled: rgnodes-ip2ip.service'
  else
    log_error 'Rules may be active now, but systemd could not start the persistence service.'
    log_error 'Inspect: journalctl -u rgnodes-ip2ip.service -n 50 --no-pager'
    return 1
  fi
}

show_banner() {
  printf '\n%s==============================================================%s\n' "$C_CYAN" "$C_RESET"
  printf '%s    RGNODES™ IP-to-IP Gateway / Port Forwarding%s\n' "$C_CYAN" "$C_RESET"
  printf '%s==============================================================%s\n\n' "$C_CYAN" "$C_RESET"
  printf "Linux only: this forwards traffic through VPS A to VPS B; it does not move the public IP to B.\n\n"
}

show_diagnostics() {
  printf 'OS: '; . /etc/os-release 2>/dev/null && printf '%s %s\n' "${PRETTY_NAME:-Linux}" "${VERSION_ID:-}"
  printf 'Kernel: '; uname -r 2>/dev/null || true
  printf 'Virtualization: '; if command -v systemd-detect-virt >/dev/null 2>&1; then systemd-detect-virt 2>/dev/null || printf 'unknown\n'; else printf 'unknown (systemd-detect-virt unavailable)\n'; fi
  printf 'iptables binaries: '; for x in iptables iptables-nft iptables-legacy; do command -v "$x" 2>/dev/null || true; done; printf '\n'
  printf 'nft binary: ' command -v nft 2>/dev/null || printf 'not installed\n'
  if select_backend >/dev/null 2>&1; then
    printf 'Writable backend: %s\n' "$BACKEND"
  else
    printf 'Writable backend: NONE (kernel/provider capability issue or missing packages)\n'
    printf 'Try: iptables -t nat -L; nft list ruleset\n'
  fi
}

self_test() {
  local failures=0
  local value
  for value in 1.2.3.4 192.168.1.1 10.0.0.1; do
    if ! valid_ipv4 "$value"; then log_error "IPv4 self-test unexpectedly rejected $value"; failures=$((failures+1)); fi
  done
  for value in invalid 999.1.1.1 192.168.1 127.0.0.1 0.1.2.3 224.0.0.1 255.255.255.255; do
    if valid_ipv4 "$value"; then log_error "IPv4 self-test unexpectedly accepted $value"; failures=$((failures+1)); fi
  done
  for value in 1 22 443 25565 65535; do
    if ! valid_port "$value"; then log_error "Port self-test unexpectedly rejected $value"; failures=$((failures+1)); fi
  done
  for value in 0 65536 -1 abc 999999; do
    if valid_port "$value"; then log_error "Port self-test unexpectedly accepted $value"; failures=$((failures+1)); fi
  done
  if (( failures == 0 )); then
    log_success 'Input validation self-tests passed.'
    return 0
  fi
  log_error "$failures input validation self-test(s) failed."
  return 1
}

main() {
  need_root
  need_base_commands
  case "${1:-}" in
    --help|-h)
      cat <<'HELP'
Usage:
  sudo bash ./ip_to_ip.sh       Interactive setup
  sudo ./ip_to_ip.sh --diagnose Check OS/backend access
  sudo ./ip_to_ip.sh --self-test Input validation checks (no firewall changes)
  sudo /usr/local/sbin/rgnodes-ip2ip.sh --restore  Restore saved rules
  sudo /usr/local/sbin/rgnodes-ip2ip.sh --stop     Remove RGNODES-managed rules

Supported: Linux with writable iptables OR nftables and CAP_NET_ADMIN/root netfilter access.
Not supported: Windows PowerShell/cmd, or providers that block guest NAT/netfilter.
HELP
      return 0
      ;;
    --diagnose)
      show_diagnostics
      return 0
      ;;
    --self-test)
      self_test
      return $?
      ;;
    --restore)
      [[ -r "$CONFIG_FILE" ]] || { log_error "Missing config: $CONFIG_FILE"; exit 1; }
      # Config is root-owned mode 0600 and written by this script.
      # shellcheck disable=SC1090
      source "$CONFIG_FILE"
      SAVED_IPTABLES_BIN=${IPTABLES_BIN:-}
      SAVED_NFT_BIN=${NFT_BIN:-}
      select_backend "${BACKEND:-}" || exit 1
      apply_rules
      ;;
    --stop)
      if [[ -r "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        SAVED_IPTABLES_BIN=${IPTABLES_BIN:-}
        SAVED_NFT_BIN=${NFT_BIN:-}
        select_backend "${BACKEND:-}" || exit 1
      else
        select_backend || exit 1
      fi
      if [[ "$BACKEND" == 'iptables' ]]; then cleanup_iptables; else nft_cleanup; fi
      ;;
    '')
      show_banner
      if ! select_backend; then
        if [[ -t 0 ]] && { ! has_backend_binary || ! command -v nft >/dev/null 2>&1; }; then
          log_warn 'No writable firewall backend was found; an nftables fallback package may be missing.'
          read -r -p 'Install/reinstall iptables+nftables packages with the detected package manager and retry? [y/N]: ' INSTALL_CONFIRM
          case "$INSTALL_CONFIRM" in
            y|Y|yes|YES)
              install_backend_tools || { log_error 'Package installation failed. Install a firewall package manually and retry.'; exit 1; }
              select_backend || exit 1
              ;;
            *) log_error 'No firewall tools installed. Install iptables or nftables and rerun.'; exit 1 ;;
          esac
        else
          exit 1
        fi
      fi
      log_success "Writable firewall backend detected: $BACKEND"
      local TARGET_INPUT PORTS_INPUT DEFAULT_IF CONFIRM
      read -r -p '[?] Target VPS IPv4 address: ' TARGET_INPUT
      if ! valid_ipv4 "$TARGET_INPUT"; then log_error 'Invalid IPv4 address.'; exit 1; fi
      if ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TARGET_INPUT"; then
        log_error 'Target IP is assigned to this VPS. Enter the other VPS address.'; exit 1
      fi
      if ! ip -4 route get "$TARGET_INPUT" >/dev/null 2>&1; then
        log_error "No route to target $TARGET_INPUT. Check IP/network/provider routing."; exit 1
      fi
      DEFAULT_IF=$(get_default_interface)
      if [[ -z "$DEFAULT_IF" ]]; then DEFAULT_IF=$(ip -4 route get "$TARGET_INPUT" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'); fi
      [[ -n "$DEFAULT_IF" ]] || { log_error 'Could not detect the public-facing interface.'; exit 1; }
      read -r -p "[?] Incoming/public interface [$DEFAULT_IF]: " WAN_IF
      WAN_IF=${WAN_IF:-$DEFAULT_IF}
      ip link show dev "$WAN_IF" >/dev/null 2>&1 || { log_error "Interface not found: $WAN_IF"; exit 1; }

      read -r -p "[?] Ports to forward (e.g. 80,443,25565) or 'all': " PORTS_INPUT
      PORTS_INPUT=$(printf '%s' "$PORTS_INPUT" | tr -d '[:space:]')
      if [[ "$PORTS_INPUT" == 'all' ]]; then
        MODE='all'; PORTS_CSV=''; SSH_PORTS=$(get_ssh_ports)
        log_warn "ALL mode is broad. TCP SSH port(s) $SSH_PORTS remain on this VPS."
        read -r -p 'Type FORWARD-ALL to continue: ' CONFIRM
        [[ "$CONFIRM" == 'FORWARD-ALL' ]] || { log_info 'Cancelled.'; exit 0; }
      else
        MODE='ports'
        if [[ -z "$PORTS_INPUT" || ! "$PORTS_INPUT" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
          log_error "Enter comma-separated ports, e.g. 80,443,25565, or 'all'."; exit 1
        fi
        local -a raw_ports=() unique_ports=() ssh_arr=() selected_arr=() matched_ssh=()
        local p selected_port ssh_port matched_csv
        declare -A seen_ports=()
        IFS=',' read -r -a raw_ports <<< "$PORTS_INPUT"
        for p in "${raw_ports[@]}"; do
          valid_port "$p" || { log_error "Invalid port: $p (allowed 1-65535)."; exit 1; }
          p=$((10#$p))
          if [[ -z "${seen_ports[$p]+x}" ]]; then seen_ports[$p]=1; unique_ports+=("$p"); fi
        done
        ((${#unique_ports[@]} > 0)) || { log_error 'No valid ports supplied.'; exit 1; }
        PORTS_CSV=$(IFS=,; printf '%s' "${unique_ports[*]}")
        SSH_PORTS=$(get_ssh_ports)
        log_info "Will forward TCP + UDP: $PORTS_CSV"
        IFS=',' read -r -a ssh_arr <<< "$SSH_PORTS"
        IFS=',' read -r -a selected_arr <<< "$PORTS_CSV"
        for selected_port in "${selected_arr[@]}"; do
          for ssh_port in "${ssh_arr[@]}"; do
            [[ "$selected_port" == "$ssh_port" ]] && matched_ssh+=("$ssh_port")
          done
        done
        if ((${#matched_ssh[@]} > 0)); then
          matched_csv=$(IFS=,; printf '%s' "${matched_ssh[*]}")
          log_warn "Selected port(s) include detected SSH port(s): $matched_csv. New SSH connections may be sent to the target VPS."
          read -r -p 'Type CONTINUE to apply anyway: ' CONFIRM
          [[ "$CONFIRM" == 'CONTINUE' ]] || { log_info 'Cancelled.'; exit 0; }
        fi
      fi
      TARGET_IP=$TARGET_INPUT
      save_config
      apply_rules
      setup_persistence
      printf '\n'
      log_success "Setup finished. Public entry IP remains this VPS; target is $TARGET_IP."
      log_info 'Allow the same service ports in VPS B and the cloud/provider firewall/security group for VPS A.'
      log_info 'Because return-path MASQUERADE is enabled, target services usually see the gateway VPS IP as the source.'
      ;;
    *) log_error "Unknown option: $1"; printf 'Use --help for usage.\n' >&2; exit 2 ;;
  esac
}

main "$@"
