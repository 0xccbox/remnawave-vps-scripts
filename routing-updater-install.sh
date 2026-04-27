#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_TITLE="Remnawave Routing Updater"
WORK_DIR="${WORK_DIR:-$HOME/routing-updater}"
ENV_FILE="$WORK_DIR/.env"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"

DEFAULT_IMAGE="ghcr.io/lifeindarkside/remnawave-routing-update:latest"
DEFAULT_RAW_URL="https://raw.githubusercontent.com/hydraponique/roscomvpn-happ-routing/refs/heads/main/HAPP/DEFAULT.DEEPLINK"
DEFAULT_INTERVAL="300"
DEFAULT_NETWORK="remnawave-network"
DEFAULT_BASE_URL_HOST="http://host.docker.internal:3000/api"

CONTAINER_NAME="remna-routing-updater"

ACTION="install"
AUTO_START="ask"

if [[ -t 1 ]]; then
  C_RESET="\033[0m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_BOLD="\033[1m"
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_BOLD=""
fi

info() {
  echo -e "${C_BLUE}ℹ️  $*${C_RESET}"
}

ok() {
  echo -e "${C_GREEN}✅ $*${C_RESET}"
}

warn() {
  echo -e "${C_YELLOW}⚠️  $*${C_RESET}"
}

err() {
  echo -e "${C_RED}❌ $*${C_RESET}" >&2
}

die() {
  err "$*"
  exit 1
}

on_error() {
  local exit_code=$?
  err "Ошибка на строке $1. Код выхода: $exit_code"
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

usage() {
  cat << EOF
$APP_TITLE installer

Использование:
  bash install_routing_updater.sh              Интерактивная установка/настройка
  bash install_routing_updater.sh --prepare    Только подготовить файлы, не запускать контейнер
  bash install_routing_updater.sh --start      Настроить и запустить контейнер
  bash install_routing_updater.sh --restart    Перезапустить контейнер
  bash install_routing_updater.sh --stop       Остановить контейнер
  bash install_routing_updater.sh --logs       Смотреть логи
  bash install_routing_updater.sh --status     Проверить статус
  bash install_routing_updater.sh --pull       Обновить Docker-образ updater

Дополнительно:
  WORK_DIR=/root/routing-updater bash install_routing_updater.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare)
      ACTION="install"
      AUTO_START="no"
      shift
      ;;
    --start)
      ACTION="install"
      AUTO_START="yes"
      shift
      ;;
    --restart)
      ACTION="restart"
      shift
      ;;
    --stop)
      ACTION="stop"
      shift
      ;;
    --logs)
      ACTION="logs"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    --pull)
      ACTION="pull"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Неизвестный аргумент: $1"
      ;;
  esac
done

has_docker() {
  command -v docker >/dev/null 2>&1
}

has_compose() {
  has_docker && docker compose version >/dev/null 2>&1
}

need_docker_for_action() {
  if ! has_docker; then
    die "Docker не найден. Сначала установите Docker или установите панель Remnawave, если её installer сам ставит Docker."
  fi

  if ! has_compose; then
    die "Docker Compose plugin не найден. Команда 'docker compose' недоступна."
  fi
}

get_env_value() {
  local key="$1"
  if [[ -f "$ENV_FILE" ]]; then
    grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d '=' -f 2- || true
  fi
}

ask_default() {
  local prompt="$1"
  local default_value="$2"
  local answer=""

  if [[ -t 0 ]]; then
    read -r -p "$prompt [$default_value]: " answer || true
    if [[ -z "$answer" ]]; then
      echo "$default_value"
    else
      echo "$answer"
    fi
  else
    echo "$default_value"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local answer=""

  if [[ "$default_value" == "yes" ]]; then
    local hint="Y/n"
  else
    local hint="y/N"
  fi

  if [[ -t 0 ]]; then
    read -r -p "$prompt [$hint]: " answer || true
    answer="${answer,,}"

    if [[ -z "$answer" ]]; then
      [[ "$default_value" == "yes" ]]
      return
    fi

    [[ "$answer" == "y" || "$answer" == "yes" || "$answer" == "д" || "$answer" == "да" ]]
  else
    [[ "$default_value" == "yes" ]]
  fi
}

ask_secret_optional() {
  local prompt="$1"
  local answer=""

  if [[ -t 0 ]]; then
    read -r -s -p "$prompt: " answer || true
    echo "" >&2
    echo "$answer"
  else
    echo ""
  fi
}

detect_remnawave_container() {
  if ! has_docker; then
    return 0
  fi

  docker ps --format '{{.Names}}|{{.Image}}|{{.Networks}}' \
    | grep -iE 'remna|remnawave' \
    | grep -vi "$CONTAINER_NAME" \
    | head -n 1 || true
}

extract_field() {
  local line="$1"
  local field="$2"

  echo "$line" | awk -F'|' -v n="$field" '{print $n}'
}

first_network_from_list() {
  local networks="$1"

  echo "$networks" | awk -F',' '{print $1}' | xargs
}

ensure_work_dir() {
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
}

write_env_file() {
  local remna_base_url="$1"
  local remna_token="$2"
  local github_raw_url="$3"
  local check_interval="$4"
  local docker_network="$5"
  local updater_image="$6"

  umask 077

  cat > "$ENV_FILE" << EOF
# Файл создан установщиком $APP_TITLE
# Если панель Remnawave ещё не установлена, можно оставить REMNA_TOKEN пустым.
# После установки панели запустите этот скрипт повторно и вставьте API token.

REMNA_BASE_URL=$remna_base_url
REMNA_TOKEN=$remna_token
GITHUB_RAW_URL=$github_raw_url
CHECK_INTERVAL=$check_interval

# Docker-сеть, через которую updater будет подключаться.
# Если используется REMNA_BASE_URL=http://host.docker.internal:3000/api,
# сеть всё равно нужна Docker Compose, но не обязана совпадать с сетью панели.
REMNA_DOCKER_NETWORK=$docker_network

# Docker image updater.
UPDATER_IMAGE=$updater_image
EOF

  chmod 600 "$ENV_FILE"
  ok "Файл .env создан/обновлён: $ENV_FILE"
  ok "Права на .env ограничены: chmod 600"
}

write_compose_file() {
  cat > "$COMPOSE_FILE" << 'EOF'
services:
  routing-updater:
    image: ${UPDATER_IMAGE:-ghcr.io/lifeindarkside/remnawave-routing-update:latest}
    container_name: remna-routing-updater
    restart: unless-stopped
    env_file:
      - .env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - remna_network

networks:
  remna_network:
    name: ${REMNA_DOCKER_NETWORK:-remnawave-network}
    external: true
EOF

  ok "Файл docker-compose.yml создан/обновлён: $COMPOSE_FILE"
}

ensure_network_exists() {
  local network_name="$1"

  need_docker_for_action

  if docker network inspect "$network_name" >/dev/null 2>&1; then
    ok "Docker-сеть найдена: $network_name"
  else
    warn "Docker-сеть не найдена: $network_name"
    info "Создаю сеть: $network_name"
    docker network create "$network_name" >/dev/null
    ok "Docker-сеть создана: $network_name"
  fi
}

compose_pull() {
  need_docker_for_action
  cd "$WORK_DIR"

  info "Скачиваю/обновляю Docker-образ..."
  docker compose pull
  ok "Образ обновлён."
}

compose_up() {
  local network_name="$1"
  local token="$2"

  need_docker_for_action

  if [[ -z "$token" ]]; then
    warn "REMNA_TOKEN пустой. Контейнер не будет запущен."
    warn "После установки панели Remnawave создайте API token и запустите скрипт повторно."
    return 0
  fi

  ensure_network_exists "$network_name"

  cd "$WORK_DIR"

  info "Удаляю старый контейнер, если он конфликтует..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  info "Запускаю Routing Updater..."
  docker compose up -d

  sleep 3

  if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
    ok "Контейнер запущен: $CONTAINER_NAME"
    echo ""
    info "Последние логи:"
    docker compose logs --tail=30
    echo ""
    ok "Для просмотра логов:"
    echo "cd $WORK_DIR && docker compose logs -f"
  else
    err "Контейнер не запустился или сразу остановился."
    docker compose logs --tail=60 || true
    exit 1
  fi
}

compose_restart() {
  need_docker_for_action
  cd "$WORK_DIR"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    die "Файл docker-compose.yml не найден в $WORK_DIR"
  fi

  docker compose restart
  ok "Контейнер перезапущен."
}

compose_stop() {
  need_docker_for_action
  cd "$WORK_DIR"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    die "Файл docker-compose.yml не найден в $WORK_DIR"
  fi

  docker compose down
  ok "Контейнер остановлен."
}

compose_logs() {
  need_docker_for_action
  cd "$WORK_DIR"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    die "Файл docker-compose.yml не найден в $WORK_DIR"
  fi

  docker compose logs -f --tail=100
}

compose_status() {
  need_docker_for_action

  echo ""
  info "Docker containers:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Networks}}' | grep -E "NAMES|$CONTAINER_NAME|remna|remnawave" || true

  echo ""
  info "Docker networks:"
  docker network ls | grep -E "NETWORK|remna|remnawave|routing" || true

  echo ""
  if [[ -f "$ENV_FILE" ]]; then
    info ".env найден: $ENV_FILE"
    echo "REMNA_BASE_URL=$(get_env_value REMNA_BASE_URL)"
    echo "GITHUB_RAW_URL=$(get_env_value GITHUB_RAW_URL)"
    echo "CHECK_INTERVAL=$(get_env_value CHECK_INTERVAL)"
    echo "REMNA_DOCKER_NETWORK=$(get_env_value REMNA_DOCKER_NETWORK)"

    local token_value
    token_value="$(get_env_value REMNA_TOKEN || true)"
    if [[ -n "$token_value" ]]; then
      echo "REMNA_TOKEN=***скрыт***"
    else
      echo "REMNA_TOKEN=пустой"
    fi
  else
    warn ".env не найден: $ENV_FILE"
  fi
}

main_install() {
  clear 2>/dev/null || true

  echo -e "${C_BOLD}🚀 $APP_TITLE installer${C_RESET}"
  echo ""
  info "Рабочая директория: $WORK_DIR"

  ensure_work_dir

  local detected_line=""
  local detected_name=""
  local detected_image=""
  local detected_networks=""
  local detected_network=""

  if has_docker; then
    detected_line="$(detect_remnawave_container || true)"

    if [[ -n "$detected_line" ]]; then
      detected_name="$(extract_field "$detected_line" 1)"
      detected_image="$(extract_field "$detected_line" 2)"
      detected_networks="$(extract_field "$detected_line" 3)"
      detected_network="$(first_network_from_list "$detected_networks")"

      ok "Похоже, панель Remnawave уже запущена:"
      echo "   container: $detected_name"
      echo "   image:     $detected_image"
      echo "   networks:  $detected_networks"
    else
      warn "Контейнер Remnawave сейчас не найден."
      warn "Это нормально, если панель ещё не установлена."
    fi
  else
    warn "Docker не найден. Скрипт сможет только подготовить файлы."
    warn "Запуск контейнера будет возможен после установки Docker."
  fi

  echo ""

  local old_base_url
  local old_token
  local old_raw_url
  local old_interval
  local old_network
  local old_image

  old_base_url="$(get_env_value REMNA_BASE_URL || true)"
  old_token="$(get_env_value REMNA_TOKEN || true)"
  old_raw_url="$(get_env_value GITHUB_RAW_URL || true)"
  old_interval="$(get_env_value CHECK_INTERVAL || true)"
  old_network="$(get_env_value REMNA_DOCKER_NETWORK || true)"
  old_image="$(get_env_value UPDATER_IMAGE || true)"

  local suggested_base_url=""

  if [[ -n "$old_base_url" ]]; then
    suggested_base_url="$old_base_url"
  elif [[ -n "$detected_name" ]]; then
    suggested_base_url="http://${detected_name}:3000/api"
  else
    suggested_base_url="$DEFAULT_BASE_URL_HOST"
  fi

  local suggested_network=""

  if [[ -n "$old_network" ]]; then
    suggested_network="$old_network"
  elif [[ -n "$detected_network" ]]; then
    suggested_network="$detected_network"
  else
    suggested_network="$DEFAULT_NETWORK"
  fi

  local suggested_raw_url="${old_raw_url:-$DEFAULT_RAW_URL}"
  local suggested_interval="${old_interval:-$DEFAULT_INTERVAL}"
  local suggested_image="${old_image:-$DEFAULT_IMAGE}"

  echo -e "${C_BOLD}Настройка подключения к Remnawave${C_RESET}"
  echo ""
  echo "Варианты REMNA_BASE_URL:"
  echo "  1) Если updater в одной Docker-сети с панелью:"
  echo "     http://ИМЯ_КОНТЕЙНЕРА:3000/api"
  echo ""
  echo "  2) Если панель публикует порт 3000 на VPS:"
  echo "     http://host.docker.internal:3000/api"
  echo ""

  local remna_base_url
  remna_base_url="$(ask_default "REMNA_BASE_URL" "$suggested_base_url")"

  echo ""

  local remna_token="$old_token"

  if [[ -n "$old_token" ]]; then
    if ask_yes_no "В .env уже есть REMNA_TOKEN. Оставить старый токен?" "yes"; then
      remna_token="$old_token"
    else
      remna_token="$(ask_secret_optional "Вставьте новый API token из Remnawave Settings → API Tokens. Можно оставить пустым, если панели ещё нет")"
    fi
  else
    remna_token="$(ask_secret_optional "Вставьте API token из Remnawave Settings → API Tokens. Можно оставить пустым, если панели ещё нет")"
  fi

  echo ""

  local github_raw_url
  github_raw_url="$(ask_default "GITHUB_RAW_URL" "$suggested_raw_url")"

  local check_interval
  check_interval="$(ask_default "CHECK_INTERVAL в секундах" "$suggested_interval")"

  if ! [[ "$check_interval" =~ ^[0-9]+$ ]]; then
    die "CHECK_INTERVAL должен быть числом."
  fi

  if [[ "$check_interval" -lt 60 ]]; then
    warn "CHECK_INTERVAL меньше 60 секунд. Это может быть слишком часто."
  fi

  local docker_network
  docker_network="$(ask_default "Docker-сеть для updater" "$suggested_network")"

  local updater_image
  updater_image="$(ask_default "Docker image updater" "$suggested_image")"

  echo ""

  write_env_file "$remna_base_url" "$remna_token" "$github_raw_url" "$check_interval" "$docker_network" "$updater_image"
  write_compose_file

  echo ""

  local should_start="no"

  case "$AUTO_START" in
    yes)
      should_start="yes"
      ;;
    no)
      should_start="no"
      ;;
    ask)
      if [[ -z "$remna_token" ]]; then
        warn "Токен пустой, поэтому запуск сейчас пропущен."
        should_start="no"
      elif ask_yes_no "Запустить Routing Updater сейчас?" "yes"; then
        should_start="yes"
      else
        should_start="no"
      fi
      ;;
  esac

  if [[ "$should_start" == "yes" ]]; then
    compose_up "$docker_network" "$remna_token"
  else
    ok "Файлы подготовлены."
    echo ""
    info "После установки панели Remnawave запустите скрипт повторно:"
    echo "bash $(realpath "$0" 2>/dev/null || echo install_routing_updater.sh) --start"
    echo ""
    info "Или вручную:"
    echo "cd $WORK_DIR && docker compose up -d"
  fi
}

case "$ACTION" in
  install)
    main_install
    ;;
  restart)
    compose_restart
    ;;
  stop)
    compose_stop
    ;;
  logs)
    compose_logs
    ;;
  status)
    compose_status
    ;;
  pull)
    compose_pull
    ;;
  *)
    die "Неизвестное действие: $ACTION"
    ;;
esac
