#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_VERSION="1.0.0"

INSTALL_DOCKER="yes"
INSTALL_XANMOD="no"
ENABLE_UFW="yes"
CREATE_SWAP="auto"
VPN_PORTS=""
REBOOT_AFTER="ask"

SSH_PORT=""
OS_ID=""
OS_VERSION_ID=""
ARCH=""

log() {
  echo -e "\033[1;34m[INFO]\033[0m $*"
}

ok() {
  echo -e "\033[1;32m[OK]\033[0m $*"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $*"
}

err() {
  echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
}

die() {
  err "$*"
  exit 1
}

usage() {
  cat << EOF
Universal VPS VPN Prep for Remnawave Node

Использование:
  bash /root/vps-vpn-prep.sh [опции]

Опции:
  --no-docker              Не устанавливать Docker
  --xanmod                 Установить XanMod LTS kernel, НЕ рекомендуется по умолчанию
  --no-ufw                 Не включать UFW firewall
  --vpn-port PORT          Открыть дополнительный TCP/UDP порт для VPN-ноды
                           Можно указывать несколько раз: --vpn-port 8443 --vpn-port 2053
  --no-swap                Не создавать swap
  --reboot                 Перезагрузить автоматически после завершения
  --no-reboot              Не перезагружать автоматически
  -h, --help               Помощь

Примеры:
  bash /root/vps-vpn-prep.sh
  bash /root/vps-vpn-prep.sh --vpn-port 443
  bash /root/vps-vpn-prep.sh --no-docker --vpn-port 443
  bash /root/vps-vpn-prep.sh --xanmod --vpn-port 443 --reboot
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker)
      INSTALL_DOCKER="no"
      shift
      ;;
    --xanmod)
      INSTALL_XANMOD="yes"
      shift
      ;;
    --no-ufw)
      ENABLE_UFW="no"
      shift
      ;;
    --vpn-port)
      [[ $# -ge 2 ]] || die "После --vpn-port нужно указать порт"
      VPN_PORTS="$VPN_PORTS $2"
      shift 2
      ;;
    --no-swap)
      CREATE_SWAP="no"
      shift
      ;;
    --reboot)
      REBOOT_AFTER="yes"
      shift
      ;;
    --no-reboot)
      REBOOT_AFTER="no"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Неизвестная опция: $1"
      ;;
  esac
done

on_error() {
  err "Ошибка на строке $1"
  exit 1
}

trap 'on_error $LINENO' ERR

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Скрипт нужно запускать от root"
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
  else
    die "Не удалось определить ОС"
  fi

  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  log "ОС: $OS_ID $OS_VERSION_ID"
  log "Архитектура: $ARCH"

  if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    warn "Скрипт рассчитан на Ubuntu/Debian. На этой ОС возможны проблемы."
  fi
}

detect_ssh_port() {
  SSH_PORT="$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | head -n1 || true)"

  if [[ -z "$SSH_PORT" ]]; then
    SSH_PORT="$(grep -E '^\s*Port\s+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -n1 || true)"
  fi

  SSH_PORT="${SSH_PORT:-22}"

  ok "SSH порт обнаружен: $SSH_PORT"
}

print_banner() {
  clear 2>/dev/null || true
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        UNIVERSAL VPS VPN PREP FOR REMNAWAVE NODE     ║"
  echo "║                    version $SCRIPT_VERSION                  ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
}

configure_dns_safe() {
  log "Проверка DNS..."

  if command -v resolvectl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    mkdir -p /etc/systemd/resolved.conf.d

    cat > /etc/systemd/resolved.conf.d/99-vpn-dns.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8 9.9.9.9
FallbackDNS=1.0.0.1 8.8.4.4
DNSStubListener=yes
EOF

    systemctl restart systemd-resolved
    ok "DNS настроен через systemd-resolved"
  else
    cp -f /etc/resolv.conf "/etc/resolv.conf.backup.$(date +%s)" 2>/dev/null || true

    cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF

    ok "DNS временно записан в /etc/resolv.conf"
  fi
}

apt_update_upgrade() {
  log "Обновление системы..."

  apt-get update

  apt-get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    upgrade

  ok "Система обновлена"
}

install_base_packages() {
  log "Установка базовых пакетов..."

  apt-get install -y \
    curl \
    wget \
    git \
    htop \
    tmux \
    nano \
    vim \
    ufw \
    fail2ban \
    socat \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    sudo \
    unzip \
    tar \
    cron \
    net-tools \
    iproute2 \
    dnsutils \
    openssl

  ok "Базовые пакеты установлены"
}

safe_cleanup() {
  log "Безопасная очистка системы..."

  apt-get autoremove --purge -y || true
  apt-get autoclean -y || true
  apt-get clean || true

  ok "Очистка завершена"
}

configure_sysctl() {
  log "Настройка сетевых параметров ядра..."

  cat > /etc/sysctl.d/99-vpn-tuning.conf << 'EOF'
# Safe VPN network tuning

# BBR + fq
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Forwarding
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

# Connection handling
net.core.somaxconn=4096
net.core.netdev_max_backlog=8192
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.tcp_keepalive_probes=5

# TCP buffers, moderate and safe
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Ports
net.ipv4.ip_local_port_range=1024 65535

# File limits
fs.file-max=1000000

# Memory
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  sysctl --system >/dev/null || warn "Некоторые sysctl параметры могли не примениться"

  local bbr_status
  bbr_status="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

  if [[ "$bbr_status" == "bbr" ]]; then
    ok "BBR включён"
  else
    warn "BBR не включился. Текущий congestion control: ${bbr_status:-unknown}"
  fi

  ok "Сетевой тюнинг применён"
}

configure_limits() {
  log "Настройка лимитов файлов..."

  cat > /etc/security/limits.d/99-vpn-nofile.conf << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF

  mkdir -p /etc/systemd/system.conf.d
  mkdir -p /etc/systemd/user.conf.d

  cat > /etc/systemd/system.conf.d/99-vpn-limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1000000
EOF

  cat > /etc/systemd/user.conf.d/99-vpn-limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1000000
EOF

  systemctl daemon-reexec || true

  ok "Лимиты настроены"
}

configure_journald() {
  log "Ограничение размера системных логов..."

  mkdir -p /etc/systemd/journald.conf.d

  cat > /etc/systemd/journald.conf.d/99-vpn-logs.conf << 'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
MaxRetentionSec=7day
Compress=yes
EOF

  systemctl restart systemd-journald || true

  ok "Логи journald ограничены"
}

configure_fail2ban() {
  log "Настройка fail2ban для SSH..."

  mkdir -p /etc/fail2ban/jail.d

  cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = %(sshd_log)s
maxretry = 5
findtime = 10m
bantime = 1h
EOF

  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl restart fail2ban || true

  ok "fail2ban настроен"
}

configure_ufw() {
  if [[ "$ENABLE_UFW" != "yes" ]]; then
    warn "UFW пропущен по опции --no-ufw"
    return
  fi

  log "Настройка UFW firewall..."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "$SSH_PORT/tcp" comment "SSH"

  ufw allow 80/tcp comment "HTTP"
  ufw allow 443/tcp comment "HTTPS/TLS"

  for port in $VPN_PORTS; do
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
      ufw allow "$port/tcp" comment "VPN TCP $port"
      ufw allow "$port/udp" comment "VPN UDP $port"
      ok "Открыт VPN порт TCP/UDP: $port"
    else
      warn "Некорректный порт пропущен: $port"
    fi
  done

  ufw --force enable

  ok "UFW включён. SSH порт $SSH_PORT открыт."
}

install_docker() {
  if [[ "$INSTALL_DOCKER" != "yes" ]]; then
    warn "Docker пропущен по опции --no-docker"
    return
  fi

  log "Установка Docker..."

  if command -v docker >/dev/null 2>&1; then
    ok "Docker уже установлен"
  else
    curl -fsSL https://get.docker.com | sh
  fi

  systemctl enable --now docker

  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose plugin доступен"
  else
    warn "Docker Compose plugin не найден после установки Docker"
  fi

  ok "Docker установлен и запущен"
}

create_swap_if_needed() {
  if [[ "$CREATE_SWAP" == "no" ]]; then
    warn "Swap пропущен по опции --no-swap"
    return
  fi

  if swapon --show | grep -q '^'; then
    ok "Swap уже существует"
    return
  fi

  local mem_mb
  mem_mb="$(free -m | awk '/^Mem:/ {print $2}')"

  if [[ "$mem_mb" -ge 2000 ]]; then
    ok "RAM ${mem_mb}MB, swap не создаётся"
    return
  fi

  log "RAM ${mem_mb}MB. Создаю swap 1G для защиты от OOM..."

  fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  if ! grep -q '^/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  ok "Swap 1G создан"
}

install_xanmod_optional() {
  if [[ "$INSTALL_XANMOD" != "yes" ]]; then
    warn "XanMod не устанавливается. Это правильный вариант по умолчанию для стабильной VPS."
    return
  fi

  if [[ "$ARCH" != "amd64" ]]; then
    warn "XanMod пропущен: архитектура не amd64"
    return
  fi

  log "Установка XanMod LTS kernel..."

  mkdir -p /etc/apt/keyrings

  wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org release main" > /etc/apt/sources.list.d/xanmod-release.list

  apt-get update

  local psabi
  psabi="$(wget -qO - https://dl.xanmod.org/check_x86-64_psabi.sh | bash 2>/dev/null | grep -oE 'x86-64-v[0-9]' | head -n1 || true)"
  psabi="${psabi:-x86-64-v2}"

  log "Определён PSABI: $psabi"

  apt-get install -y "linux-xanmod-lts-$psabi"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub || true
  fi

  ok "XanMod установлен. Требуется перезагрузка."
}

show_summary() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║                     ГОТОВО                           ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  echo "Сводка:"
  echo "  OS:              $OS_ID $OS_VERSION_ID"
  echo "  ARCH:            $ARCH"
  echo "  SSH port:        $SSH_PORT"
  echo "  Docker:          $INSTALL_DOCKER"
  echo "  UFW:             $ENABLE_UFW"
  echo "  VPN ports:       ${VPN_PORTS:-80 443 only}"
  echo "  XanMod:          $INSTALL_XANMOD"
  echo "  Kernel now:      $(uname -r)"
  echo "  TCP CC:          $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo ""
  echo "Проверка после перезагрузки:"
  echo "  uname -r"
  echo "  sysctl net.ipv4.tcp_congestion_control"
  echo "  docker --version"
  echo "  ufw status"
  echo ""
}

ask_reboot() {
  if [[ "$REBOOT_AFTER" == "yes" ]]; then
    log "Перезагрузка через 5 секунд..."
    sleep 5
    reboot
    return
  fi

  if [[ "$REBOOT_AFTER" == "no" ]]; then
    warn "Автоперезагрузка отключена. Рекомендуется перезагрузить VPS вручную:"
    echo "  reboot"
    return
  fi

  echo ""
  read -r -p "Перезагрузить VPS сейчас? [y/N]: " answer || true
  answer="${answer,,}"

  if [[ "$answer" == "y" || "$answer" == "yes" || "$answer" == "д" || "$answer" == "да" ]]; then
    reboot
  else
    warn "Перезагрузка пропущена. Рекомендуется выполнить позже:"
    echo "  reboot"
  fi
}

main() {
  require_root
  print_banner
  detect_os
  detect_ssh_port

  configure_dns_safe
  apt_update_upgrade
  install_base_packages
  safe_cleanup

  configure_sysctl
  configure_limits
  configure_journald
  configure_fail2ban
  create_swap_if_needed
  configure_ufw
  install_docker
  install_xanmod_optional

  show_summary
  ask_reboot
}

main "$@"
