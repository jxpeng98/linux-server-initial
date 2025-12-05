#!/bin/bash
# setup_ssh_firewall.sh
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
    echo -e "${RED}Please run this script as root (sudo ./setup_ssh_firewall.sh)${NC}"
  else
    echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./setup_ssh_firewall.sh)${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "${GREEN}=== SSH Port and Firewall Configuration (Ubuntu/Debian) ===${NC}"
else
  echo -e "${GREEN}=== SSH 端口与防火墙配置 (Ubuntu/Debian) ===${NC}"
fi

if ! command -v apt &>/dev/null; then
  if is_en; then
    echo -e "${RED}This script currently supports only apt-based distros (Debian/Ubuntu, etc.).${NC}"
  else
    echo -e "${RED}当前脚本暂仅支持基于 apt 的发行版 (Debian/Ubuntu 等)。${NC}"
  fi
  exit 1
fi

# 1. 交互设置新端口
DEFAULT_SSH_PORT="2222"
SSH_22_DISABLED="no"
if is_en; then
  prompt_read "请输入要新增的 SSH 端口 (默认: ${DEFAULT_SSH_PORT}): " \
              "Enter the SSH port to add (default: ${DEFAULT_SSH_PORT}): " \
              "$DEFAULT_SSH_PORT" INPUT_PORT
else
  prompt_read "请输入要新增的 SSH 端口 (默认: ${DEFAULT_SSH_PORT}): " \
              "Enter the SSH port to add (default: ${DEFAULT_SSH_PORT}): " \
              "$DEFAULT_SSH_PORT" INPUT_PORT
fi
SSH_PORT="${INPUT_PORT:-$DEFAULT_SSH_PORT}"

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -le 0 ] || [ "$SSH_PORT" -gt 65535 ]; then
  if is_en; then
    echo -e "${RED}Invalid port: $SSH_PORT${NC}"
  else
    echo -e "${RED}无效端口号: $SSH_PORT${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "Configuring new SSH port: ${GREEN}${SSH_PORT}${NC} (keeping 22 as well)"
else
  echo -e "将配置新 SSH 端口: ${GREEN}${SSH_PORT}${NC} （同时保留 22）"
fi

SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_PATH="/etc/ssh/sshd_config.bak.$(date +%F-%H%M%S)"

# 2. 备份配置
cp "$SSH_CONFIG" "$BACKUP_PATH"
if is_en; then
  echo -e "${GREEN}sshd_config backed up to: ${BACKUP_PATH}${NC}"
else
  echo -e "${GREEN}已备份 sshd_config 到: ${BACKUP_PATH}${NC}"
fi

# 3. 修改端口 — 保留 22，仅追加新端口（幂等）
if ! grep -q "^Port 22" "$SSH_CONFIG"; then
  echo "Port 22" >> "$SSH_CONFIG"
fi
if ! grep -q "^Port $SSH_PORT" "$SSH_CONFIG"; then
  echo "Port $SSH_PORT" >> "$SSH_CONFIG"
fi

# 4. SSH 安全选项：禁止 root、启用公钥、禁用密码、禁止空密码和质询式认证
set_ssh_option() {
  local option="$1"
  local value="$2"
  if grep -q "^#\?${option}" "$SSH_CONFIG"; then
    sed -i "s/^#\?${option}.*/${option} ${value}/" "$SSH_CONFIG"
  else
    echo "${option} ${value}" >> "$SSH_CONFIG"
  fi
}

# 基础安全选项
set_ssh_option "PermitRootLogin" "no"
set_ssh_option "PubkeyAuthentication" "yes"
set_ssh_option "PasswordAuthentication" "no"
set_ssh_option "PermitEmptyPasswords" "no"
set_ssh_option "ChallengeResponseAuthentication" "no"
set_ssh_option "KbdInteractiveAuthentication" "no"

# 增强安全选项：限制认证尝试和超时
set_ssh_option "MaxAuthTries" "3"
set_ssh_option "LoginGraceTime" "60"
set_ssh_option "MaxSessions" "10"
set_ssh_option "MaxStartups" "10:30:60"

# 会话保活和超时（防止僵尸连接）
set_ssh_option "ClientAliveInterval" "300"
set_ssh_option "ClientAliveCountMax" "2"

# 禁用不安全的功能
set_ssh_option "X11Forwarding" "no"
set_ssh_option "AllowTcpForwarding" "no"
set_ssh_option "AllowAgentForwarding" "no"
set_ssh_option "PermitUserEnvironment" "no"
set_ssh_option "PermitTunnel" "no"
set_ssh_option "GatewayPorts" "no"

# 日志级别（便于审计）
set_ssh_option "LogLevel" "VERBOSE"

# 禁用不安全的认证方式
set_ssh_option "HostbasedAuthentication" "no"
set_ssh_option "IgnoreRhosts" "yes"

# 使用现代加密算法（SSH 安全加固）
# 仅允许强密钥交换算法
if ! grep -q "^KexAlgorithms" "$SSH_CONFIG"; then
  echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256" >> "$SSH_CONFIG"
fi
# 仅允许强加密算法
if ! grep -q "^Ciphers" "$SSH_CONFIG"; then
  echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> "$SSH_CONFIG"
fi
# 仅允许强 MAC 算法
if ! grep -q "^MACs" "$SSH_CONFIG"; then
  echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256" >> "$SSH_CONFIG"
fi

# 5. 可选：配置 AllowUsers 白名单
if is_en; then
  prompt_read "是否配置 SSH 用户白名单 (AllowUsers)? 如需配置请输入允许登录的用户名(逗号分隔)，直接回车跳过: " \
              "Configure SSH user whitelist (AllowUsers)? Enter usernames separated by comma, or press Enter to skip: " \
              "" ALLOW_USERS
else
  prompt_read "是否配置 SSH 用户白名单 (AllowUsers)? 如需配置请输入允许登录的用户名(逗号分隔)，直接回车跳过: " \
              "Configure SSH user whitelist (AllowUsers)? Enter usernames separated by comma, or press Enter to skip: " \
              "" ALLOW_USERS
fi

if [ -n "$ALLOW_USERS" ]; then
  # 将逗号替换为空格
  ALLOW_USERS_FORMATTED=$(echo "$ALLOW_USERS" | tr ',' ' ')
  # 移除已有的 AllowUsers 配置
  sed -i '/^AllowUsers/d' "$SSH_CONFIG"
  echo "AllowUsers $ALLOW_USERS_FORMATTED" >> "$SSH_CONFIG"
  if is_en; then
    echo -e "${GREEN}AllowUsers configured: ${ALLOW_USERS_FORMATTED}${NC}"
  else
    echo -e "${GREEN}已配置 AllowUsers: ${ALLOW_USERS_FORMATTED}${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping AllowUsers configuration.${NC}"
  else
    echo -e "${YELLOW}跳过 AllowUsers 配置${NC}"
  fi
fi

# 5. 检查配置语法，否则回滚
if ! sshd -t 2>/tmp/sshd_check.log; then
  if is_en; then
    echo -e "${RED}sshd configuration check failed, rolling back to backup.${NC}"
  else
    echo -e "${RED}sshd 配置检查失败，自动回滚到备份${NC}"
  fi
  cat /tmp/sshd_check.log
  mv "$BACKUP_PATH" "$SSH_CONFIG"
  # 尝试重启原 SSH 服务
  if systemctl list-unit-files | grep -q "^ssh\.service"; then
    systemctl restart ssh
  elif systemctl list-unit-files | grep -q "^sshd\.service"; then
    systemctl restart sshd
  fi
  exit 1
fi

# 6. 重启 SSH 服务（兼容 systemd / service）
SSH_SERVICE=""
if command -v systemctl &>/dev/null; then
  if systemctl list-unit-files | grep -q "^ssh\.service"; then
    systemctl restart ssh
    SSH_SERVICE="ssh"
  elif systemctl list-unit-files | grep -q "^sshd\.service"; then
    systemctl restart sshd
    SSH_SERVICE="sshd"
  fi
fi

if [ -z "$SSH_SERVICE" ] && command -v service &>/dev/null; then
  if service ssh status >/dev/null 2>&1 || service sshd status >/dev/null 2>&1; then
    if service ssh status >/dev/null 2>&1; then
      service ssh restart
      SSH_SERVICE="ssh"
    elif service sshd status >/dev/null 2>&1; then
      service sshd restart
      SSH_SERVICE="sshd"
    fi
  fi
fi

if [ -z "$SSH_SERVICE" ]; then
  if is_en; then
    echo -e "${RED}ssh/sshd service not found via systemd or service. Please check manually (non-systemd system?).${NC}"
  else
    echo -e "${RED}未通过 systemd 或 service 找到 ssh/sshd 服务，请手动检查（可能是非 systemd 系统）。${NC}"
  fi
  exit 1
fi
if is_en; then
  echo -e "${GREEN}SSH service (${SSH_SERVICE}) restarted.${NC}"
else
  echo -e "${GREEN}SSH 服务 (${SSH_SERVICE}) 已重启${NC}"
fi

# 7. 配置 UFW 防火墙
if is_en; then
  echo -e "${GREEN}Configuring UFW firewall rules...${NC}"
else
  echo -e "${GREEN}开始配置 UFW 防火墙规则...${NC}"
fi

# 确保 UFW 已安装
if ! command -v ufw &>/dev/null; then
  apt update
  apt install -y ufw
fi

# 放行 22 和新端口（幂等，使用 limit 对 SSH 端口做简单暴力破解防护）
ufw limit 22/tcp || true
ufw limit "${SSH_PORT}"/tcp || true

# 默认策略
ufw default deny incoming
ufw default allow outgoing

UFW_STATUS=$(ufw status | head -n1 | awk '{print $2}')
if [ "$UFW_STATUS" = "inactive" ]; then
  if is_en; then
    prompt_read "UFW 目前未启用，是否现在启用? [Y/n]: " \
                "UFW is currently inactive, enable it now? [Y/n]: " \
                "y" ENABLE_UFW
  else
    prompt_read "UFW 目前未启用，是否现在启用? [Y/n]: " \
                "UFW is currently inactive, enable it now? [Y/n]: " \
                "y" ENABLE_UFW
  fi
  ENABLE_UFW="${ENABLE_UFW:-y}"
  if [[ "$ENABLE_UFW" =~ ^[Yy]$ ]]; then
    echo "y" | ufw enable
    if is_en; then
      echo -e "${GREEN}UFW enabled.${NC}"
    else
      echo -e "${GREEN}UFW 已启用${NC}"
    fi
  else
    if is_en; then
      echo -e "${YELLOW}Keep UFW inactive.${NC}"
    else
      echo -e "${YELLOW}保持 UFW 未启用状态${NC}"
    fi
  fi
else
  if is_en; then
    echo -e "${YELLOW}UFW already active, rules updated.${NC}"
  else
    echo -e "${YELLOW}UFW 已处于启用状态，仅更新了规则${NC}"
  fi
fi

# 8. 可选：安装并配置 fail2ban
if is_en; then
  prompt_read "是否安装 fail2ban 以进一步防御 SSH 暴力破解? [Y/n]: " \
              "Install fail2ban to further protect against SSH brute-force attacks? [Y/n]: " \
              "y" INSTALL_FAIL2BAN
else
  prompt_read "是否安装 fail2ban 以进一步防御 SSH 暴力破解? [Y/n]: " \
              "Install fail2ban to further protect against SSH brute-force attacks? [Y/n]: " \
              "y" INSTALL_FAIL2BAN
fi
INSTALL_FAIL2BAN="${INSTALL_FAIL2BAN:-y}"

if [[ "$INSTALL_FAIL2BAN" =~ ^[Yy]$ ]]; then
  if ! command -v fail2ban-client &>/dev/null; then
    apt update
    apt install -y fail2ban
  fi

  install -d -m 0755 /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/ssh-hardening.conf <<EOF
[sshd]
enabled = true
port = 22,${SSH_PORT}
logpath = %(sshd_log)s
backend = systemd
maxretry = 5
findtime = 600
bantime = 3600
EOF

  systemctl enable --now fail2ban

  if is_en; then
    echo -e "${GREEN}fail2ban installed and configured for SSH (ports 22 and ${SSH_PORT}).${NC}"
  else
    echo -e "${GREEN}已安装并配置 fail2ban 保护 SSH（端口 22 和 ${SSH_PORT}）。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping fail2ban installation/configuration.${NC}"
  else
    echo -e "${YELLOW}跳过 fail2ban 安装与配置。${NC}"
  fi
fi

# 9. 可选：关闭 SSH 端口 22（高风险操作）
if is_en; then
  prompt_read "确认已经在另一条会话中成功使用新端口 ${SSH_PORT} 登录了吗？现在禁用 SSH 端口 22? [y/N]: " \
              "Have you already successfully logged in using the new SSH port ${SSH_PORT} from another session? Disable SSH port 22 now? [y/N]: " \
              "n" DISABLE_22
else
  prompt_read "确认已经在另一条会话中成功使用新端口 ${SSH_PORT} 登录了吗？现在禁用 SSH 端口 22? [y/N]: " \
              "Have you already successfully logged in using the new SSH port ${SSH_PORT} from another session? Disable SSH port 22 now? [y/N]: " \
              "n" DISABLE_22
fi
DISABLE_22="${DISABLE_22:-n}"

if [[ "$DISABLE_22" =~ ^[Yy]$ ]]; then
  DISABLE_BACKUP="/etc/ssh/sshd_config.bak.disable22.$(date +%F-%H%M%S)"
  cp "$SSH_CONFIG" "$DISABLE_BACKUP"

  # 注释掉 Port 22 行，保留新端口配置
  if grep -q "^Port 22" "$SSH_CONFIG"; then
    sed -i 's/^Port 22/#Port 22 (disabled by linux-server-initial)/' "$SSH_CONFIG"
  fi

  # 再次检查配置语法
  if ! sshd -t 2>/tmp/sshd_disable22_check.log; then
    if is_en; then
      echo -e "${RED}Disabling port 22 caused sshd config check to fail. Rolling back this change.${NC}"
    else
      echo -e "${RED}关闭 22 端口后 sshd 配置检查失败，正在回滚此变更。${NC}"
    fi
    cat /tmp/sshd_disable22_check.log
    mv "$DISABLE_BACKUP" "$SSH_CONFIG"
  else
    # 更新 UFW 规则，删除 22 端口的规则（若存在）
    ufw --force delete limit 22/tcp >/dev/null 2>&1 || ufw --force delete allow 22/tcp >/dev/null 2>&1 || true

    # 重启 SSH 服务
    if systemctl list-unit-files | grep -q "^ssh\.service"; then
      systemctl restart ssh
      SSH_SERVICE="ssh"
    elif systemctl list-unit-files | grep -q "^sshd\.service"; then
      systemctl restart sshd
      SSH_SERVICE="sshd"
    fi

    SSH_22_DISABLED="yes"

    if is_en; then
      echo -e "${GREEN}SSH port 22 disabled in sshd_config and UFW. SSH is now expected to listen only on port ${SSH_PORT}.${NC}"
    else
      echo -e "${GREEN}已在 sshd_config 和 UFW 中关闭 22 端口，SSH 现在预计仅在端口 ${SSH_PORT} 上监听。${NC}"
    fi
  fi
else
  if is_en; then
    echo -e "${YELLOW}Port 22 kept enabled. You can disable it later manually after confirming the new port works.${NC}"
  else
    echo -e "${YELLOW}保留 22 端口开启状态，你可以在确认新端口稳定后再手动关闭。${NC}"
  fi
fi

# 10. 状态输出与排查提示
echo -e "${GREEN}----------------------------------------------${NC}"
if is_en; then
  echo -e "${GREEN}UFW status (verbose):${NC}"
else
  echo -e "${GREEN}UFW 状态 (verbose):${NC}"
fi
ufw status verbose || true

if command -v ss &>/dev/null; then
  if is_en; then
    echo -e "${GREEN}Current sshd listening sockets (ss -tnlp | grep sshd):${NC}"
  else
    echo -e "${GREEN}当前 sshd 监听信息 (ss -tnlp | grep sshd):${NC}"
  fi
  ss -tnlp | grep sshd || true
fi

if command -v fail2ban-client &>/dev/null; then
  if is_en; then
    echo -e "${GREEN}fail2ban status for sshd:${NC}"
  else
    echo -e "${GREEN}fail2ban sshd 状态:${NC}"
  fi
  fail2ban-client status sshd 2>/dev/null || fail2ban-client status 2>/dev/null || true
else
  if is_en; then
    echo -e "${YELLOW}fail2ban not installed or not enabled; skipped status check.${NC}"
  else
    echo -e "${YELLOW}未安装/未启用 fail2ban，跳过状态检查。${NC}"
  fi
fi

echo -e "${GREEN}=====================================================${NC}"
if is_en; then
  echo -e "${GREEN}✅ SSH / firewall configuration completed.${NC}"
  if [ "$SSH_22_DISABLED" = "yes" ]; then
    echo -e "SSH port 22 has been disabled. Current intended SSH port: ${GREEN}${SSH_PORT}${NC}"
    echo -e "Make sure you can log in via:"
    echo -e "  ssh -p ${SSH_PORT} <your-user>@<your-server-ip>"
  else
    echo -e "Current listening ports (expected): ${GREEN}22, ${SSH_PORT}${NC}"
    echo -e "Next step: with this session kept open, test login with the new port:"
    echo -e "  ssh -p ${SSH_PORT} <your-user>@<your-server-ip>"
    echo -e ""
    echo -e "After confirming the new port works reliably, you may disable 22 (either via this script next time or manually in ${SSH_CONFIG} and UFW)."
  fi
  echo -e "Troubleshooting tips: check auth logs via 'journalctl -u ssh' or '/var/log/auth.log'; for fail2ban 'journalctl -u fail2ban' or 'fail2ban-client status'."
  echo -e "If something goes wrong, you can use rollback_ssh.sh to roll back."
else
  echo -e "${GREEN}✅ SSH / 防火墙配置完成${NC}"
  if [ "$SSH_22_DISABLED" = "yes" ]; then
    echo -e "SSH 22 端口已关闭，当前预期监听端口为: ${GREEN}${SSH_PORT}${NC}"
    echo -e "请务必确认可以通过以下方式正常连接："
    echo -e "  ssh -p ${SSH_PORT} <你的用户名>@<你的服务器IP>"
  else
    echo -e "当前监听端口（预期）: ${GREEN}22, ${SSH_PORT}${NC}"
    echo -e "下一步建议：在当前会话保持开启的前提下，用新端口测试登录："
    echo -e "  ssh -p ${SSH_PORT} <你的用户名>@<你的服务器IP>"
    echo -e ""
    echo -e "当你确认新端口连接稳定后，可以通过本脚本（重新运行并选择关闭 22）或手动修改 ${SSH_CONFIG} 和 UFW 规则关闭 22。"
  fi
  echo -e "排查提示：查看 ssh 日志可用 'journalctl -u ssh' 或 '/var/log/auth.log'；fail2ban 可用 'journalctl -u fail2ban' 或 'fail2ban-client status'。"
  echo -e "如出现问题，可使用 rollback_ssh.sh 回滚。"
fi
echo -e "${GREEN}=====================================================${NC}"
