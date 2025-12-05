#!/bin/bash
# rollback_ssh.sh
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

verify_checksums

if [ "$EUID" -ne 0 ]; then
  if is_en; then
    echo -e "${RED}Please run this script as root (sudo ./rollback_ssh.sh)${NC}"
  else
    echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./rollback_ssh.sh)${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "${GREEN}=== Roll Back SSH Configuration ===${NC}"
else
  echo -e "${GREEN}=== 回滚 SSH 配置 ===${NC}"
fi

SSH_CONFIG="/etc/ssh/sshd_config"
BACKUPS=(/etc/ssh/sshd_config.bak.*)

if [ ${#BACKUPS[@]} -eq 0 ]; then
  if is_en; then
    echo -e "${RED}No backup files found (/etc/ssh/sshd_config.bak.*), cannot roll back automatically.${NC}"
  else
    echo -e "${RED}未找到任何备份文件 (/etc/ssh/sshd_config.bak.*)，无法自动回滚${NC}"
  fi
  exit 1
fi

# 找到最新的备份文件
LATEST_BACKUP=$(ls -t /etc/ssh/sshd_config.bak.* | head -n1)

if is_en; then
  echo -e "Using backup file: ${GREEN}${LATEST_BACKUP}${NC} for rollback"
else
  echo -e "将使用备份文件: ${GREEN}${LATEST_BACKUP}${NC} 进行回滚"
fi

if is_en; then
  prompt_read "确认回滚 SSH 配置? [y/N]: " \
              "Confirm rolling back SSH configuration? [y/N]: " \
              "n" CONFIRM
else
  prompt_read "确认回滚 SSH 配置? [y/N]: " \
              "Confirm rolling back SSH configuration? [y/N]: " \
              "n" CONFIRM
fi
CONFIRM="${CONFIRM:-n}"
if ! [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${YELLOW}Rollback cancelled by user.${NC}"
  else
    echo -e "${YELLOW}用户取消回滚${NC}"
  fi
  exit 0
fi

cp "$LATEST_BACKUP" "$SSH_CONFIG"

# 检查配置
if ! sshd -t 2>/tmp/sshd_check.log; then
  if is_en; then
    echo -e "${RED}Syntax check failed for rolled back sshd_config, please check manually:${NC}"
  else
    echo -e "${RED}回滚后的 sshd_config 语法检查失败，请手动检查：${NC}"
  fi
  cat /tmp/sshd_check.log
  exit 1
fi

# 重启 SSH
if systemctl list-unit-files | grep -q "^ssh\.service"; then
  systemctl restart ssh
  SSH_SERVICE="ssh"
elif systemctl list-unit-files | grep -q "^sshd\.service"; then
  systemctl restart sshd
  SSH_SERVICE="sshd"
else
  if is_en; then
    echo -e "${RED}ssh/sshd systemd service not found, please restart the service manually.${NC}"
  else
    echo -e "${RED}未找到 ssh / sshd systemd 服务，请手动重启服务${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "${GREEN}SSH service (${SSH_SERVICE}) restarted.${NC}"
else
  echo -e "${GREEN}SSH 服务 (${SSH_SERVICE}) 已重启${NC}"
fi

# UFW 放行 22
if command -v ufw &>/dev/null; then
  ufw allow 22/tcp || true
  if is_en; then
    echo -e "${GREEN}Ensured UFW allows port 22.${NC}"
  else
    echo -e "${GREEN}已确保 UFW 放行 22 端口${NC}"
  fi
fi

echo -e "${GREEN}=====================================================${NC}"
if is_en; then
  echo -e "${GREEN}✅ SSH rollback completed.${NC}"
  echo -e "You should now be able to test connection via default port 22:"
  echo -e "  ssh -p 22 <your-user>@<your-server-ip>"
else
  echo -e "${GREEN}✅ SSH 回滚完成${NC}"
  echo -e "现在应可以通过默认端口 22 测试连接："
  echo -e "  ssh -p 22 <你的用户名>@<你的服务器IP>"
fi
echo -e "${GREEN}=====================================================${NC}"
