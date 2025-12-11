#!/bin/bash
# linux_server_initial.sh
# 统一的交互入口：创建用户 / 加固 SSH+防火墙 / 安全加固

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 引入公共函数
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/common.sh"

init_lang
verify_checksums
ensure_root
ensure_apt

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

show_menu() {
  echo -e "${GREEN}==============================================${NC}"
  if is_en; then
    echo -e "${GREEN}   Linux Server Initialization Wizard   ${NC}"
  else
    echo -e "${GREEN}      Linux 服务器初始化向导      ${NC}"
  fi
  echo -e "${GREEN}==============================================${NC}"
  if is_en; then
    echo -e "1) Create new user and initialize dev environment"
    echo -e "2) Harden SSH and configure firewall"
    echo -e "3) System security hardening (sysctl, auditd, auto-updates)"
    echo -e "4) Roll back SSH configuration (from backup)"
    echo -e "5) Recommended full flow (1 + 2 + 3)"
    echo -e "0) Exit"
  else
    echo -e "1) 创建新用户并初始化开发环境"
    echo -e "2) 增强 SSH 安全并配置防火墙"
    echo -e "3) 系统安全加固 (sysctl、auditd、自动更新)"
    echo -e "4) 回滚 SSH 配置（使用备份恢复）"
    echo -e "5) 一键执行推荐流程 (1 + 2 + 3)"
    echo -e "0) 退出"
  fi
  echo -e "${GREEN}----------------------------------------------${NC}"
}

while true; do
  show_menu
  if is_en; then
    read -rp "Select an option [0-5]: " choice
  else
    read -rp "请选择要执行的操作 [0-5]: " choice
  fi
  case "$choice" in
    1)
      msg "${GREEN}>>> 执行：创建新用户并初始化开发环境${NC}" \
          "${GREEN}>>> Running: create new user and initialize dev environment${NC}"
      run_setup_env
      ;;
    2)
      msg "${GREEN}>>> 执行：增强 SSH 安全并配置防火墙${NC}" \
          "${GREEN}>>> Running: harden SSH and configure firewall${NC}"
      run_setup_ssh_firewall
      ;;
    3)
      msg "${GREEN}>>> 执行：系统安全加固${NC}" \
          "${GREEN}>>> Running: system security hardening${NC}"
      run_security_hardening
      ;;
    4)
      msg "${GREEN}>>> 执行：回滚 SSH 配置${NC}" \
          "${GREEN}>>> Running: roll back SSH configuration${NC}"
      run_rollback_ssh
      ;;
    5)
      msg "${GREEN}>>> 执行：一键推荐流程 (1 + 2 + 3)${NC}" \
          "${GREEN}>>> Running: recommended full flow (1 + 2 + 3)${NC}"
      run_setup_env
      run_setup_ssh_firewall
      run_security_hardening
      ;;
    0)
      msg "${GREEN}已退出 Linux 初始化向导${NC}" \
          "${GREEN}Exited Linux initialization wizard${NC}"
      break
      ;;
    *)
      msg "${YELLOW}无效选项，请输入 0-5 之间的数字${NC}" \
          "${YELLOW}Invalid option, please enter a number between 0 and 5.${NC}"
      ;;
  esac
done