#!/bin/bash
# setup_security_hardening.sh
# 系统级安全加固脚本
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入公共函数
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

# 如果从主入口调用，语言已初始化；否则初始化语言
init_lang
ensure_root
ensure_apt

if is_en; then
  echo -e "${GREEN}=== System Security Hardening (Ubuntu/Debian) ===${NC}"
else
  echo -e "${GREEN}=== 系统安全加固 (Ubuntu/Debian) ===${NC}"
fi

# ============================================
# 1. 配置内核安全参数 (sysctl)
# ============================================
if is_en; then
  prompt_read "是否配置内核安全参数 (sysctl)? [Y/n]: " \
              "Configure kernel security parameters (sysctl)? [Y/n]: " \
              "y" SETUP_SYSCTL
else
  prompt_read "是否配置内核安全参数 (sysctl)? [Y/n]: " \
              "Configure kernel security parameters (sysctl)? [Y/n]: " \
              "y" SETUP_SYSCTL
fi
SETUP_SYSCTL="${SETUP_SYSCTL:-y}"

if [[ "$SETUP_SYSCTL" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}1. Configuring kernel security parameters...${NC}"
  else
    echo -e "${GREEN}1. 配置内核安全参数...${NC}"
  fi

  SYSCTL_CONF="/etc/sysctl.d/99-security-hardening.conf"
  
  cat > "$SYSCTL_CONF" << 'EOF'
# ============================================
# 网络安全加固
# ============================================

# 禁用 IP 转发（除非你需要作为路由器）
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 禁止 ICMP 重定向（防止中间人攻击）
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 启用 IP 欺骗防护
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 忽略 ICMP 广播请求（防止 Smurf 攻击）
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 忽略伪造的 ICMP 错误消息
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 启用 SYN Cookie（防止 SYN 洪水攻击）
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# 禁止源路由包（防止 IP 欺骗）
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 记录可疑数据包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 禁用 IPv6（如果不需要的话）
# 取消注释以下行来禁用 IPv6
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1

# TCP 时间戳（防止某些攻击，但有助于连接可靠性）
net.ipv4.tcp_timestamps = 1

# ============================================
# 内存保护
# ============================================

# 限制 core dump
fs.suid_dumpable = 0

# 随机化虚拟地址空间 (ASLR)
kernel.randomize_va_space = 2

# 限制内核指针暴露
kernel.kptr_restrict = 2

# 限制 dmesg 访问
kernel.dmesg_restrict = 1

# 禁用 SysRq 键（或仅允许安全操作）
kernel.sysrq = 0

# 限制 ptrace 范围（仅允许父进程调试子进程）
kernel.yama.ptrace_scope = 1

# ============================================
# 文件系统安全
# ============================================

# 限制硬链接和符号链接的创建
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# 限制 FIFO 和 regular 文件
fs.protected_fifos = 2
fs.protected_regular = 2

EOF

  # 应用配置
  sysctl --system > /dev/null 2>&1

  if is_en; then
    echo -e "${GREEN}Kernel security parameters configured and applied.${NC}"
  else
    echo -e "${GREEN}内核安全参数已配置并应用。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping sysctl configuration.${NC}"
  else
    echo -e "${YELLOW}跳过 sysctl 配置。${NC}"
  fi
fi

# ============================================
# 2. 可选：禁用 IPv6
# ============================================
if is_en; then
  prompt_read "是否禁用 IPv6? (如果你不使用 IPv6) [y/N]: " \
              "Disable IPv6? (if you don't use IPv6) [y/N]: " \
              "n" DISABLE_IPV6
else
  prompt_read "是否禁用 IPv6? (如果你不使用 IPv6) [y/N]: " \
              "Disable IPv6? (if you don't use IPv6) [y/N]: " \
              "n" DISABLE_IPV6
fi
DISABLE_IPV6="${DISABLE_IPV6:-n}"

if [[ "$DISABLE_IPV6" =~ ^[Yy]$ ]]; then
  SYSCTL_IPV6="/etc/sysctl.d/99-disable-ipv6.conf"
  cat > "$SYSCTL_IPV6" << 'EOF'
# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  sysctl --system > /dev/null 2>&1
  if is_en; then
    echo -e "${GREEN}IPv6 disabled.${NC}"
  else
    echo -e "${GREEN}已禁用 IPv6。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Keeping IPv6 enabled.${NC}"
  else
    echo -e "${YELLOW}保持 IPv6 启用状态。${NC}"
  fi
fi

# ============================================
# 3. 配置自动安全更新
# ============================================
if is_en; then
  prompt_read "是否配置自动安全更新 (unattended-upgrades)? [Y/n]: " \
              "Configure automatic security updates (unattended-upgrades)? [Y/n]: " \
              "y" SETUP_AUTO_UPDATE
else
  prompt_read "是否配置自动安全更新 (unattended-upgrades)? [Y/n]: " \
              "Configure automatic security updates (unattended-upgrades)? [Y/n]: " \
              "y" SETUP_AUTO_UPDATE
fi
SETUP_AUTO_UPDATE="${SETUP_AUTO_UPDATE:-y}"

if [[ "$SETUP_AUTO_UPDATE" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}2. Installing and configuring unattended-upgrades...${NC}"
  else
    echo -e "${GREEN}2. 安装并配置自动安全更新...${NC}"
  fi

  apt update
  apt install -y unattended-upgrades apt-listchanges

  # 配置自动更新
  cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

  # 配置 unattended-upgrades
  cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// 自动修复被打断的 dpkg
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// 移除未使用的内核包
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// 移除未使用的依赖
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// 如果需要重启，自动重启（可选，默认禁用）
// Unattended-Upgrade::Automatic-Reboot "true";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// 启用邮件通知（需要配置邮件）
// Unattended-Upgrade::Mail "root";
// Unattended-Upgrade::MailReport "on-change";

// 仅在错误时发送邮件
// Unattended-Upgrade::MailOnlyOnError "true";

// 日志
Unattended-Upgrade::SyslogEnable "true";
EOF

  # 启用服务
  systemctl enable --now unattended-upgrades

  if is_en; then
    echo -e "${GREEN}Automatic security updates configured.${NC}"
  else
    echo -e "${GREEN}自动安全更新已配置。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping automatic updates configuration.${NC}"
  else
    echo -e "${YELLOW}跳过自动更新配置。${NC}"
  fi
fi

# ============================================
# 4. 安装并配置 auditd (审计)
# ============================================
if is_en; then
  prompt_read "是否安装并配置 auditd (系统审计)? [Y/n]: " \
              "Install and configure auditd (system auditing)? [Y/n]: " \
              "y" SETUP_AUDITD
else
  prompt_read "是否安装并配置 auditd (系统审计)? [Y/n]: " \
              "Install and configure auditd (system auditing)? [Y/n]: " \
              "y" SETUP_AUDITD
fi
SETUP_AUDITD="${SETUP_AUDITD:-y}"

if [[ "$SETUP_AUDITD" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}3. Installing and configuring auditd...${NC}"
  else
    echo -e "${GREEN}3. 安装并配置 auditd...${NC}"
  fi

  apt update
  apt install -y auditd audispd-plugins

  # 配置审计规则
  AUDIT_RULES="/etc/audit/rules.d/hardening.rules"
  cat > "$AUDIT_RULES" << 'EOF'
# 删除所有现有规则
-D

# 设置缓冲区大小
-b 8192

# 设置失败模式 (1=printk, 2=panic)
-f 1

# ============================================
# 用户和认证相关
# ============================================

# 监控用户/组更改
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# 监控登录相关文件
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# ============================================
# 系统配置更改
# ============================================

# 监控网络配置
-w /etc/hosts -p wa -k network
-w /etc/network/ -p wa -k network
-w /etc/netplan/ -p wa -k network

# 监控 SSH 配置
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d/ -p wa -k sshd

# 监控 cron 任务
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# 监控 systemd 服务
-w /etc/systemd/ -p wa -k systemd
-w /lib/systemd/ -p wa -k systemd

# ============================================
# 权限提升
# ============================================

# 监控 su 和 sudo 使用
-w /bin/su -p x -k privileged
-w /usr/bin/sudo -p x -k privileged
-w /usr/bin/passwd -p x -k privileged
-w /usr/sbin/usermod -p x -k privileged
-w /usr/sbin/useradd -p x -k privileged
-w /usr/sbin/userdel -p x -k privileged
-w /usr/sbin/groupadd -p x -k privileged
-w /usr/sbin/groupdel -p x -k privileged
-w /usr/sbin/groupmod -p x -k privileged

# ============================================
# 内核模块
# ============================================

# 监控内核模块加载
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# ============================================
# 可执行文件更改
# ============================================

# 监控关键可执行文件目录
-w /usr/bin/ -p wa -k binaries
-w /usr/sbin/ -p wa -k binaries

# 使规则不可变（需要重启才能更改）
# -e 2
EOF

  # 重新加载审计规则
  augenrules --load > /dev/null 2>&1 || true
  systemctl enable --now auditd

  if is_en; then
    echo -e "${GREEN}auditd installed and configured.${NC}"
    echo -e "${YELLOW}Use 'ausearch -k <key>' to search audit logs, e.g., 'ausearch -k sshd'${NC}"
  else
    echo -e "${GREEN}auditd 已安装并配置。${NC}"
    echo -e "${YELLOW}使用 'ausearch -k <关键字>' 搜索审计日志，例如 'ausearch -k sshd'${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping auditd installation.${NC}"
  else
    echo -e "${YELLOW}跳过 auditd 安装。${NC}"
  fi
fi

# ============================================
# 5. 配置登录安全
# ============================================
if is_en; then
  prompt_read "是否配置登录安全限制 (登录失败锁定等)? [Y/n]: " \
              "Configure login security restrictions (account lockout, etc.)? [Y/n]: " \
              "y" SETUP_LOGIN_SECURITY
else
  prompt_read "是否配置登录安全限制 (登录失败锁定等)? [Y/n]: " \
              "Configure login security restrictions (account lockout, etc.)? [Y/n]: " \
              "y" SETUP_LOGIN_SECURITY
fi
SETUP_LOGIN_SECURITY="${SETUP_LOGIN_SECURITY:-y}"

if [[ "$SETUP_LOGIN_SECURITY" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}4. Configuring login security...${NC}"
  else
    echo -e "${GREEN}4. 配置登录安全...${NC}"
  fi

  # 配置登录超时
  if ! grep -q "^TMOUT=" /etc/profile; then
    echo "" >> /etc/profile
    echo "# 自动登出空闲终端 (10分钟)" >> /etc/profile
    echo "TMOUT=600" >> /etc/profile
    echo "readonly TMOUT" >> /etc/profile
    echo "export TMOUT" >> /etc/profile
  fi

  # 配置密码策略（如果启用密码登录）
  if [ -f /etc/login.defs ]; then
    # 密码过期策略
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs 2>/dev/null || true
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs 2>/dev/null || true
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs 2>/dev/null || true
  fi

  # 配置 faillock (替代旧的 pam_tally2)
  apt install -y libpam-modules 2>/dev/null || true

  # 配置登录失败锁定
  FAILLOCK_CONF="/etc/security/faillock.conf"
  if [ -f "$FAILLOCK_CONF" ]; then
    cat > "$FAILLOCK_CONF" << 'EOF'
# 登录失败锁定配置
# 5 次失败后锁定
deny = 5
# 锁定时间 900 秒 (15 分钟)
unlock_time = 900
# 在此时间内计算失败次数
fail_interval = 900
# 审计
audit
# 即使对 root 也应用 (谨慎!)
# even_deny_root
# root 锁定时间
# root_unlock_time = 60
EOF
  fi

  if is_en; then
    echo -e "${GREEN}Login security configured.${NC}"
  else
    echo -e "${GREEN}登录安全已配置。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping login security configuration.${NC}"
  else
    echo -e "${YELLOW}跳过登录安全配置。${NC}"
  fi
fi

# ============================================
# 6. 禁用不必要的服务
# ============================================
if is_en; then
  prompt_read "是否禁用不常用的危险服务 (如 rpcbind, avahi 等)? [Y/n]: " \
              "Disable uncommon/risky services (rpcbind, avahi, etc.)? [Y/n]: " \
              "y" DISABLE_SERVICES
else
  prompt_read "是否禁用不常用的危险服务 (如 rpcbind, avahi 等)? [Y/n]: " \
              "Disable uncommon/risky services (rpcbind, avahi, etc.)? [Y/n]: " \
              "y" DISABLE_SERVICES
fi
DISABLE_SERVICES="${DISABLE_SERVICES:-y}"

if [[ "$DISABLE_SERVICES" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}5. Disabling unnecessary services...${NC}"
  else
    echo -e "${GREEN}5. 禁用不必要的服务...${NC}"
  fi

  # 要禁用的服务列表
  SERVICES_TO_DISABLE=(
    "rpcbind"           # NFS 相关，不需要就禁用
    "avahi-daemon"      # mDNS/Bonjour，服务器通常不需要
    "cups"              # 打印服务，服务器通常不需要
    "bluetooth"         # 蓝牙服务
    "ModemManager"      # 调制解调器管理
  )

  for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
      systemctl stop "$svc" 2>/dev/null || true
      systemctl disable "$svc" 2>/dev/null || true
      systemctl mask "$svc" 2>/dev/null || true
      if is_en; then
        echo -e "  Disabled: ${svc}"
      else
        echo -e "  已禁用: ${svc}"
      fi
    fi
  done

  if is_en; then
    echo -e "${GREEN}Unnecessary services disabled.${NC}"
  else
    echo -e "${GREEN}不必要的服务已禁用。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping service disabling.${NC}"
  else
    echo -e "${YELLOW}跳过禁用服务。${NC}"
  fi
fi

# ============================================
# 7. 配置文件权限
# ============================================
if is_en; then
  prompt_read "是否加固关键文件/目录权限? [Y/n]: " \
              "Harden permissions on critical files/directories? [Y/n]: " \
              "y" HARDEN_PERMS
else
  prompt_read "是否加固关键文件/目录权限? [Y/n]: " \
              "Harden permissions on critical files/directories? [Y/n]: " \
              "y" HARDEN_PERMS
fi
HARDEN_PERMS="${HARDEN_PERMS:-y}"

if [[ "$HARDEN_PERMS" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}6. Hardening file permissions...${NC}"
  else
    echo -e "${GREEN}6. 加固文件权限...${NC}"
  fi

  # 关键配置文件权限
  chmod 600 /etc/shadow 2>/dev/null || true
  chmod 600 /etc/gshadow 2>/dev/null || true
  chmod 644 /etc/passwd 2>/dev/null || true
  chmod 644 /etc/group 2>/dev/null || true
  chmod 600 /etc/ssh/sshd_config 2>/dev/null || true
  chmod 700 /root 2>/dev/null || true
  chmod 600 /boot/grub/grub.cfg 2>/dev/null || true

  # 移除 world-writable 权限（除了 /tmp 和 /var/tmp）
  # 这个操作比较激进，仅记录而不自动执行
  # find / -xdev -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null

  if is_en; then
    echo -e "${GREEN}File permissions hardened.${NC}"
  else
    echo -e "${GREEN}文件权限已加固。${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping permission hardening.${NC}"
  else
    echo -e "${YELLOW}跳过权限加固。${NC}"
  fi
fi

# ============================================
# 8. 安装安全工具
# ============================================
if is_en; then
  prompt_read "是否安装额外的安全工具 (rkhunter, chkrootkit, lynis)? [y/N]: " \
              "Install additional security tools (rkhunter, chkrootkit, lynis)? [y/N]: " \
              "n" INSTALL_SECURITY_TOOLS
else
  prompt_read "是否安装额外的安全工具 (rkhunter, chkrootkit, lynis)? [y/N]: " \
              "Install additional security tools (rkhunter, chkrootkit, lynis)? [y/N]: " \
              "n" INSTALL_SECURITY_TOOLS
fi
INSTALL_SECURITY_TOOLS="${INSTALL_SECURITY_TOOLS:-n}"

if [[ "$INSTALL_SECURITY_TOOLS" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}7. Installing security tools...${NC}"
  else
    echo -e "${GREEN}7. 安装安全工具...${NC}"
  fi

  apt update
  apt install -y rkhunter chkrootkit lynis

  # 更新 rkhunter 数据库
  rkhunter --update 2>/dev/null || true
  rkhunter --propupd 2>/dev/null || true

  if is_en; then
    echo -e "${GREEN}Security tools installed.${NC}"
    echo -e "${YELLOW}Run 'rkhunter --check' to scan for rootkits${NC}"
    echo -e "${YELLOW}Run 'chkrootkit' to check for rootkits${NC}"
    echo -e "${YELLOW}Run 'lynis audit system' for a full security audit${NC}"
  else
    echo -e "${GREEN}安全工具已安装。${NC}"
    echo -e "${YELLOW}运行 'rkhunter --check' 扫描 rootkit${NC}"
    echo -e "${YELLOW}运行 'chkrootkit' 检查 rootkit${NC}"
    echo -e "${YELLOW}运行 'lynis audit system' 进行完整的安全审计${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}Skipping security tools installation.${NC}"
  else
    echo -e "${YELLOW}跳过安全工具安装。${NC}"
  fi
fi

# ============================================
# 完成
# ============================================
echo -e "${GREEN}=====================================================${NC}"
if is_en; then
  echo -e "${GREEN}✅ System security hardening completed.${NC}"
  echo -e ""
  echo -e "Summary of changes made:"
  echo -e "  - Kernel security parameters (sysctl)"
  echo -e "  - Automatic security updates"
  echo -e "  - System auditing (auditd)"
  echo -e "  - Login security restrictions"
  echo -e "  - Disabled unnecessary services"
  echo -e "  - Hardened file permissions"
  echo -e ""
  echo -e "${YELLOW}Recommendations:${NC}"
  echo -e "  1. Review /etc/sysctl.d/99-security-hardening.conf"
  echo -e "  2. Run 'lynis audit system' for a comprehensive security check"
  echo -e "  3. Consider setting up centralized logging (rsyslog/ELK)"
  echo -e "  4. Regularly review audit logs: ausearch -ts today"
else
  echo -e "${GREEN}✅ 系统安全加固完成。${NC}"
  echo -e ""
  echo -e "已完成的配置："
  echo -e "  - 内核安全参数 (sysctl)"
  echo -e "  - 自动安全更新"
  echo -e "  - 系统审计 (auditd)"
  echo -e "  - 登录安全限制"
  echo -e "  - 禁用不必要的服务"
  echo -e "  - 加固文件权限"
  echo -e ""
  echo -e "${YELLOW}建议:${NC}"
  echo -e "  1. 检查 /etc/sysctl.d/99-security-hardening.conf"
  echo -e "  2. 运行 'lynis audit system' 进行全面的安全检查"
  echo -e "  3. 考虑配置集中式日志 (rsyslog/ELK)"
  echo -e "  4. 定期审查审计日志: ausearch -ts today"
fi
echo -e "${GREEN}=====================================================${NC}"
