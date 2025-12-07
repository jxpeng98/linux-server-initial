#!/bin/bash
# install_optional_software.sh
# 交互式安装常用软件包，按需选择不同组合
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INIT_LANG="${INIT_LANG:-}"

if [ -z "$INIT_LANG" ]; then
  echo -e "${GREEN}Select language / 选择语言:${NC}"
  echo -e "1) 简体中文"
  echo -e "2) English"
  read -rp "请输入选项 [1/2] (默认 1): " LANG_CHOICE
  case "$LANG_CHOICE" in
    2)
      INIT_LANG="en"
      ;;
    *)
      INIT_LANG="zh"
      ;;
  esac
fi

is_en() {
  [ "$INIT_LANG" = "en" ]
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

verify_checksums() {
  if [ ! -f "${SCRIPT_DIR}/checksums.sha256" ]; then
    if is_en; then
      echo -e "${RED}Missing checksums.sha256; integrity check skipped.${NC}"
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

verify_checksums

if [ "$EUID" -ne 0 ]; then
  if is_en; then
    echo -e "${RED}Please run this script as root (sudo ./install_optional_software.sh)${NC}"
  else
    echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./install_optional_software.sh)${NC}"
  fi
  exit 1
fi

if ! command -v apt &>/dev/null; then
  if is_en; then
    echo -e "${RED}This script currently supports only apt-based distros (Debian/Ubuntu, etc.).${NC}"
  else
    echo -e "${RED}当前脚本暂仅支持基于 apt 的发行版 (Debian/Ubuntu 等)。${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "${GREEN}=== Optional Software Installer (Ubuntu/Debian) ===${NC}"
else
  echo -e "${GREEN}=== 可选软件批量安装 (Ubuntu/Debian) ===${NC}"
fi

show_options() {
  echo -e "${GREEN}----------------------------------------------${NC}"
  if is_en; then
    echo -e "1) Base CLI tools (htop, tmux, jq, ripgrep, etc.)"
    echo -e "2) Build toolchain (build-essential, cmake, clang, etc.)"
    echo -e "3) Language runtimes (Python/Go/Java)"
    echo -e "4) Networking and diagnostics (nmap, tcpdump, mtr, etc.)"
    echo -e "5) Database clients (psql, mysql, redis, sqlite)"
    echo -e "6) Container tools (Docker + Compose plugin)"
    echo -e "0) Exit"
    echo -e "all) Install all bundles"
  else
    echo -e "1) 基础命令行工具 (htop, tmux, jq, ripgrep 等)"
    echo -e "2) 编译/构建工具链 (build-essential, cmake, clang 等)"
    echo -e "3) 语言运行时 (Python/Go/Java)"
    echo -e "4) 网络与诊断工具 (nmap, tcpdump, mtr 等)"
    echo -e "5) 数据库客户端 (psql, mysql, redis, sqlite)"
    echo -e "6) 容器工具 (Docker + Compose 插件)"
    echo -e "0) 退出"
    echo -e "all) 安装全部组合"
  fi
  echo -e "${GREEN}----------------------------------------------${NC}"
}

APT_UPDATED=0
ensure_apt_update() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    apt update
    APT_UPDATED=1
  fi
}

install_packages() {
  local zh="$1"
  local en="$2"
  shift 2
  local packages=("$@")
  msg "开始安装：${zh}" "Installing: ${en}"
  ensure_apt_update
  if ! apt install -y "${packages[@]}"; then
    msg "${RED}安装失败：${zh}${NC}" "${RED}Failed to install ${en}${NC}"
    exit 1
  fi
  msg "${GREEN}${zh} 安装/更新完成${NC}" "${GREEN}${en} installed/updated${NC}"
}

install_choice() {
  local choice="$1"
  case "$choice" in
    1)
      install_packages \
        "基础命令行工具 (htop/tmux/jq/ripgrep 等)" \
        "Base CLI tools (htop/tmux/jq/ripgrep, etc.)" \
        htop tmux unzip zip tree jq ripgrep fd-find curl wget ca-certificates
      ;;
    2)
      install_packages \
        "编译/构建工具链 (build-essential/cmake/clang 等)" \
        "Build toolchain (build-essential/cmake/clang, etc.)" \
        build-essential cmake pkg-config ninja-build clang llvm lld make automake autoconf libtool-bin
      ;;
    3)
      install_packages \
        "语言运行时 (Python/Go/Java)" \
        "Language runtimes (Python/Go/Java)" \
        python3-full python3-pip python3-venv python3-dev openjdk-17-jdk golang-go
      ;;
    4)
      install_packages \
        "网络与诊断工具 (net-tools/nmap/tcpdump/mtr 等)" \
        "Networking and diagnostics (net-tools/nmap/tcpdump/mtr, etc.)" \
        net-tools dnsutils traceroute mtr-tiny nmap tcpdump iperf3 lsof strace iftop iotop
      ;;
    5)
      install_packages \
        "数据库客户端工具 (psql/mysql/redis/sqlite)" \
        "Database clients (psql/mysql/redis/sqlite)" \
        postgresql-client mysql-client redis-tools sqlite3
      ;;
    6)
      install_packages \
        "容器工具 (Docker + Compose 插件)" \
        "Container tools (Docker + Compose plugin)" \
        docker.io docker-compose-plugin containerd runc
      if command -v docker &>/dev/null; then
        local docker_user=""
        prompt_read \
          "可选：输入要加入 docker 组的用户名 (留空跳过): " \
          "Optional: enter a username to add into docker group (leave empty to skip): " \
          "" docker_user
        if [ -n "$docker_user" ]; then
          if id "$docker_user" &>/dev/null; then
            usermod -aG docker "$docker_user"
            msg "${GREEN}已将 ${docker_user} 加入 docker 组${NC}" \
                "${GREEN}Added ${docker_user} to docker group${NC}"
          else
            msg "${YELLOW}用户 ${docker_user} 不存在，跳过添加 docker 组${NC}" \
                "${YELLOW}User ${docker_user} not found, skipping docker group update${NC}"
          fi
        fi
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

show_options
if is_en; then
  prompt_read "请选择要安装的序号（可用逗号分隔），输入 0 退出: " \
              "Select bundle numbers to install (comma separated), or 0 to exit: " \
              "0" SELECTION
else
  prompt_read "请选择要安装的序号（可用逗号分隔），输入 0 退出: " \
              "Select bundle numbers to install (comma separated), or 0 to exit: " \
              "0" SELECTION
fi

if [[ "$SELECTION" =~ ^0$ ]]; then
  msg "${YELLOW}已退出，未执行任何安装。${NC}" "${YELLOW}Exited without installing anything.${NC}"
  exit 0
fi

choices=()
if [[ "$SELECTION" =~ ^([Aa][Ll][Ll])$ ]]; then
  choices=(1 2 3 4 5 6)
else
  # 将逗号分隔转换为空格，再逐个验证
  SELECTION="${SELECTION//,/ }"
  for item in $SELECTION; do
    item="${item//[[:space:]]/}"
    if [[ "$item" =~ ^[1-6]$ ]]; then
      choices+=("$item")
    else
      msg "${YELLOW}忽略无效选项: ${item}${NC}" "${YELLOW}Ignored invalid option: ${item}${NC}"
    fi
  done
fi

if [ ${#choices[@]} -eq 0 ]; then
  msg "${YELLOW}未包含有效选项，退出。${NC}" "${YELLOW}No valid options selected, exiting.${NC}"
  exit 0
fi

# 去重
declare -A seen
unique_choices=()
for ch in "${choices[@]}"; do
  if [ -z "${seen[$ch]:-}" ]; then
    unique_choices+=("$ch")
    seen[$ch]=1
  fi
done

for ch in "${unique_choices[@]}"; do
  if ! install_choice "$ch"; then
    msg "${YELLOW}跳过无效选项: ${ch}${NC}" "${YELLOW}Skipped invalid option: ${ch}${NC}"
  fi
done

msg "${GREEN}全部选定的安装任务已完成。${NC}" "${GREEN}All selected installation tasks completed.${NC}"
