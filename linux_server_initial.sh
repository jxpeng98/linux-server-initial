#!/bin/bash
# linux_server_initial.sh
# 统一的交互入口：创建用户 / 加固 SSH+防火墙 / 初始化开发环境
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

verify_checksums() {
  if [ ! -f "${SCRIPT_DIR}/checksums.sha256" ]; then
    echo -e "${RED}Missing checksums.sha256; integrity check skipped.${NC}"
    exit 1
  fi
  if ! (cd "$SCRIPT_DIR" && sha256sum -c checksums.sha256 >/dev/null); then
    echo -e "${RED}Integrity check failed: scripts differ from repository version.${NC}"
    exit 1
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./linux_server_initial.sh)${NC}"
  echo -e "${RED}Please run this script as root (sudo ./linux_server_initial.sh)${NC}"
  exit 1
fi

if ! command -v apt &>/dev/null; then
  echo -e "${RED}当前项目暂仅支持基于 apt 的发行版 (Debian/Ubuntu 等)。${NC}"
  echo -e "${RED}This project currently supports only apt-based distros (Debian/Ubuntu, etc.).${NC}"
  exit 1
fi

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

export INIT_LANG

verify_checksums

is_en() {
  [ "$INIT_LANG" = "en" ]
}

run_setup_env() {
  if [ ! -x "${SCRIPT_DIR}/setup_env.sh" ]; then
    if is_en; then
      echo -e "${RED}setup_env.sh not found, please check the project files.${NC}"
    else
      echo -e "${RED}未找到 setup_env.sh，请确认项目完整性${NC}"
    fi
    return 1
  fi
  bash "${SCRIPT_DIR}/setup_env.sh"
}

run_setup_ssh_firewall() {
  if [ ! -x "${SCRIPT_DIR}/setup_ssh_firewall.sh" ]; then
    if is_en; then
      echo -e "${RED}setup_ssh_firewall.sh not found, please check the project files.${NC}"
    else
      echo -e "${RED}未找到 setup_ssh_firewall.sh，请确认项目完整性${NC}"
    fi
    return 1
  fi
  bash "${SCRIPT_DIR}/setup_ssh_firewall.sh"
}

run_rollback_ssh() {
  if [ ! -x "${SCRIPT_DIR}/rollback_ssh.sh" ]; then
    if is_en; then
      echo -e "${RED}rollback_ssh.sh not found, please check the project files.${NC}"
    else
      echo -e "${RED}未找到 rollback_ssh.sh，请确认项目完整性${NC}"
    fi
    return 1
  fi
  bash "${SCRIPT_DIR}/rollback_ssh.sh"
}

run_security_hardening() {
  if [ ! -x "${SCRIPT_DIR}/setup_security_hardening.sh" ]; then
    if is_en; then
      echo -e "${RED}setup_security_hardening.sh not found, please check the project files.${NC}"
    else
      echo -e "${RED}未找到 setup_security_hardening.sh，请确认项目完整性${NC}"
    fi
    return 1
  fi
  bash "${SCRIPT_DIR}/setup_security_hardening.sh"
}

run_optional_software() {
  if [ ! -x "${SCRIPT_DIR}/install_optional_software.sh" ]; then
    if is_en; then
      echo -e "${RED}install_optional_software.sh not found, please check the project files.${NC}"
    else
      echo -e "${RED}未找到 install_optional_software.sh，请确认项目完整性${NC}"
    fi
    return 1
  fi
  bash "${SCRIPT_DIR}/install_optional_software.sh"
}

show_menu() {
  echo -e "${GREEN}==============================================${NC}"
  if is_en; then
    echo -e "${GREEN}      Linux Server Initialization Wizard      ${NC}"
  else
    echo -e "${GREEN}          Linux 服务器初始化向导            ${NC}"
  fi
  echo -e "${GREEN}==============================================${NC}"
  if is_en; then
    echo -e "1) Create new user and initialize dev environment"
    echo -e "2) Harden SSH and configure firewall"
    echo -e "3) System security hardening (sysctl, auditd, auto-updates)"
    echo -e "4) Roll back SSH configuration (from backup)"
    echo -e "5) Recommended full flow (1 + 2 + 3)"
    echo -e "6) Install optional software bundles"
    echo -e "0) Exit"
  else
    echo -e "1) 创建新用户并初始化开发环境"
    echo -e "2) 增强 SSH 安全并配置防火墙"
    echo -e "3) 系统安全加固 (sysctl、auditd、自动更新)"
    echo -e "4) 回滚 SSH 配置（使用备份恢复）"
    echo -e "5) 一键执行推荐流程 (1 + 2 + 3)"
    echo -e "6) 安装常用软件组合（可多选）"
    echo -e "0) 退出"
  fi
  echo -e "${GREEN}----------------------------------------------${NC}"
}

while true; do
  show_menu
  if is_en; then
    read -rp "Select an option [0-6]: " choice
  else
    read -rp "请选择要执行的操作 [0-6]: " choice
  fi
  case "$choice" in
    1)
      if is_en; then
        echo -e "${GREEN}>>> Running: create new user and initialize dev environment${NC}"
      else
        echo -e "${GREEN}>>> 执行：创建新用户并初始化开发环境${NC}"
      fi
      run_setup_env
      ;;
    2)
      if is_en; then
        echo -e "${GREEN}>>> Running: harden SSH and configure firewall${NC}"
      else
        echo -e "${GREEN}>>> 执行：增强 SSH 安全并配置防火墙${NC}"
      fi
      run_setup_ssh_firewall
      ;;
    3)
      if is_en; then
        echo -e "${GREEN}>>> Running: system security hardening${NC}"
      else
        echo -e "${GREEN}>>> 执行：系统安全加固${NC}"
      fi
      run_security_hardening
      ;;
    4)
      if is_en; then
        echo -e "${GREEN}>>> Running: roll back SSH configuration${NC}"
      else
        echo -e "${GREEN}>>> 执行：回滚 SSH 配置${NC}"
      fi
      run_rollback_ssh
      ;;
    5)
      if is_en; then
        echo -e "${GREEN}>>> Running: recommended full flow (1 + 2 + 3)${NC}"
      else
        echo -e "${GREEN}>>> 执行：一键推荐流程 (1 + 2 + 3)${NC}"
      fi
      run_setup_env
      run_setup_ssh_firewall
      run_security_hardening
      ;;
    6)
      if is_en; then
        echo -e "${GREEN}>>> Running: install optional software bundles${NC}"
      else
        echo -e "${GREEN}>>> 执行：安装常用软件组合${NC}"
      fi
      run_optional_software
      ;;
    0)
      if is_en; then
        echo -e "${GREEN}Exited Linux initialization wizard${NC}"
      else
        echo -e "${GREEN}已退出 Linux 初始化向导${NC}"
      fi
      break
      ;;
    *)
      if is_en; then
        echo -e "${YELLOW}Invalid option, please enter a number between 0 and 6.${NC}"
      else
        echo -e "${YELLOW}无效选项，请输入 0-6 之间的数字${NC}"
      fi
      ;;
  esac
done
