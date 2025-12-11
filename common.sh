#!/bin/bash
# common.sh - 公共函数/变量

set -euo pipefail

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 当前脚本目录（入口引用时为仓库根）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 初始化语言，只在 INIT_LANG 为空时询问
init_lang() {
  INIT_LANG="${INIT_LANG:-}"
  if [ -z "${INIT_LANG}" ]; then
    echo -e "${GREEN}Select language / 选择语言:${NC}"
    echo -e "1) 简体中文"
    echo -e "2) English"
    read -rp "请输入选项 [1/2] (默认 1): " LANG_CHOICE
    case "$LANG_CHOICE" in
      2) INIT_LANG="en" ;;
      *) INIT_LANG="zh" ;;
    esac
  fi
  export INIT_LANG
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

prompt_read() {
  local zh="$1"
  local en="$2"
  local default="$3"
  local __var="$4"
  local input
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

ensure_root() {
  if [ "$EUID" -ne 0 ]; then
    if is_en; then
      echo -e "${RED}Please run this script as root (use sudo).${NC}"
    else
      echo -e "${RED}请使用 root 权限运行本脚本（使用 sudo）。${NC}"
    fi
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