#!/bin/bash
# common.sh - 公共函数/变量

set -euo pipefail

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 当前脚本目录（入口引用时为仓库根）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 日志文件路径
LOG_FILE="${INIT_LOG_FILE:-/var/log/linux-initial.log}"

# ============================================
# 日志记录函数
# ============================================
log_init() {
  # 确保日志目录存在且可写
  local log_dir
  log_dir="$(dirname "$LOG_FILE")"
  if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir" 2>/dev/null || true
  fi
  
  # 初始化日志文件（如果不存在）
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null || {
      # 如果无法写入 /var/log，回退到当前目录
      LOG_FILE="${SCRIPT_DIR}/linux-initial.log"
      touch "$LOG_FILE"
    }
  fi
  
  log_info "========== Session started: $(date '+%Y-%m-%d %H:%M:%S') =========="
}

log_msg() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
  log_msg "INFO" "$1"
}

log_warn() {
  log_msg "WARN" "$1"
}

log_error() {
  log_msg "ERROR" "$1"
}

log_cmd() {
  # 记录将要执行的命令
  log_msg "CMD" "$1"
}

# ============================================
# 配置文件加载
# ============================================
load_config() {
  local config_file="${SCRIPT_DIR}/config.env"
  if [ -f "$config_file" ]; then
    # shellcheck source=/dev/null
    . "$config_file"
    if is_en 2>/dev/null; then
      echo -e "${BLUE}[Config] Loaded preset configuration from config.env${NC}"
    else
      echo -e "${BLUE}[配置] 已加载预设配置文件 config.env${NC}"
    fi
    log_info "Loaded configuration from $config_file"
    export INIT_CONFIG_LOADED="1"
  fi
}

# ============================================
# 非交互模式支持
# ============================================
is_non_interactive() {
  [ "${INIT_NON_INTERACTIVE:-0}" = "1" ]
}

# 初始化语言，只在 INIT_LANG 为空时询问
init_lang() {
  # 先尝试加载配置文件
  load_config
  
  INIT_LANG="${INIT_LANG:-}"
  if [ -z "${INIT_LANG}" ]; then
    if is_non_interactive; then
      INIT_LANG="zh"
    else
      echo -e "${GREEN}Select language / 选择语言:${NC}"
      echo -e "1) 简体中文"
      echo -e "2) English"
      read -rp "请输入选项 [1/2] (默认 1): " LANG_CHOICE
      case "$LANG_CHOICE" in
        2) INIT_LANG="en" ;;
        *) INIT_LANG="zh" ;;
      esac
    fi
  fi
  export INIT_LANG
  
  # 初始化日志
  log_init
}

is_en() {
  [ "${INIT_LANG:-zh}" = "en" ]
}

msg() {
  local zh="$1"
  local en="$2"
  if is_en; then
    echo -e "$en"
  else
    echo -e "$zh"
  fi
}

# 增强版 prompt_read：支持非交互模式
prompt_read() {
  local zh="$1"
  local en="$2"
  local default="$3"
  local __var="$4"
  local input
  
  # 检查变量是否已经通过配置文件设置
  local current_value
  current_value="${!__var:-}"
  if [ -n "$current_value" ]; then
    # 变量已设置，直接使用
    if is_non_interactive; then
      log_info "Using preset value for $__var: $current_value"
    else
      # 交互模式下显示预设值
      if is_en; then
        echo -e "${BLUE}[Preset] $__var = $current_value${NC}"
      else
        echo -e "${BLUE}[预设] $__var = $current_value${NC}"
      fi
    fi
    return 0
  fi
  
  # 非交互模式使用默认值
  if is_non_interactive; then
    printf -v "$__var" '%s' "$default"
    log_info "Using default value for $__var: $default"
    return 0
  fi
  
  # 交互模式
  if is_en; then
    read -rp "$en" input
  else
    read -rp "$zh" input
  fi
  if [ -z "$input" ] && [ -n "$default" ]; then
    input="$default"
  fi
  printf -v "$__var" '%s' "$input"
}

# ============================================
# 网络检查
# ============================================
check_network() {
  local test_hosts=("github.com" "download.docker.com" "deb.debian.org")
  local reachable=0
  
  msg "${GREEN}检查网络连接...${NC}" "${GREEN}Checking network connectivity...${NC}"
  log_info "Checking network connectivity"
  
  for host in "${test_hosts[@]}"; do
    if ping -c 1 -W 3 "$host" &>/dev/null || curl -s --connect-timeout 5 "https://$host" &>/dev/null; then
      reachable=1
      break
    fi
  done
  
  if [ "$reachable" -eq 0 ]; then
    log_warn "Network connectivity check failed"
    if is_en; then
      echo -e "${YELLOW}Warning: Network connectivity check failed.${NC}"
      echo -e "${YELLOW}Some features may not work properly without internet access.${NC}"
      read -rp "Continue anyway? [y/N]: " CONTINUE_OFFLINE
    else
      echo -e "${YELLOW}警告：网络连接检查失败。${NC}"
      echo -e "${YELLOW}没有网络连接，某些功能可能无法正常工作。${NC}"
      read -rp "是否继续？[y/N]: " CONTINUE_OFFLINE
    fi
    if [[ ! "$CONTINUE_OFFLINE" =~ ^[Yy]$ ]]; then
      log_error "User aborted due to network issues"
      exit 1
    fi
  else
    log_info "Network connectivity OK"
    msg "${GREEN}网络连接正常${NC}" "${GREEN}Network connectivity OK${NC}"
  fi
}

ensure_root() {
  if [ "$EUID" -ne 0 ]; then
    if is_en; then
      echo -e "${RED}Please run this script as root (use sudo).${NC}"
    else
      echo -e "${RED}请使用 root 权限运行本脚本（使用 sudo）。${NC}"
    fi
    log_error "Script not run as root"
    exit 1
  fi
}

ensure_apt() {
  if ! command -v apt &>/dev/null; then
    if is_en; then
      echo -e "${RED}This project currently supports only apt-based distros (Debian/Ubuntu, etc.).${NC}"
    else
      echo -e "${RED}当前项目仅支持基于 apt 的发行版 (Debian/Ubuntu 等)。${NC}"
    fi
    exit 1
  fi
}

# 完整性校验；设置 INIT_SKIP_CHECKSUM=1 可跳过（例如本地调试）
verify_checksums() {
  if [ "${INIT_SKIP_CHECKSUM:-0}" = "1" ]; then
    return 0
  fi

  if [ ! -f "${SCRIPT_DIR}/checksums.sha256" ]; then
    if is_en; then
      echo -e "${RED}Missing checksums.sha256; integrity check failed.${NC}"
    else
      echo -e "${RED}缺少 checksums.sha256，无法进行完整性校验。${NC}"
    fi
    exit 1
  fi

  if ! (cd "$SCRIPT_DIR" && sha256sum -c checksums.sha256 >/dev/null); then
    if is_en; then
      echo -e "${RED}Integrity check failed: scripts differ from repository version.${NC}"
    else
      echo -e "${RED}完整性校验失败：脚本与仓库版本不一致。${NC}"
    fi
    exit 1
  fi
}