## Linux 初始配置工具 / Linux Initial Setup Toolkit

这是一个用于初始化全新 Linux 服务器的小工具，当前主要针对 **Ubuntu / Debian**（基于 `apt` 的发行版）。

This is a small toolkit for initializing a fresh Linux server, currently targeting **Ubuntu / Debian** (apt-based distros).

目前支持 / Features:

- 创建新用户并初始化常用开发环境（Zsh / Oh My Zsh / mise / Docker 等）  
  Create a new user and set up common dev tools (Zsh / Oh My Zsh / mise / Docker, etc.)
- 加固 SSH 配置并开启 UFW 防火墙（默认使用 `ufw limit` 为 SSH 端口提供简单的暴力破解防护，可选安装 fail2ban）  
  Harden SSH configuration and enable UFW firewall (using `ufw limit` on SSH ports for basic brute-force protection, optional fail2ban installation)
- 系统安全加固（内核参数 sysctl、自动安全更新、auditd 审计、登录安全限制等）  
  System security hardening (kernel parameters via sysctl, automatic security updates, auditd auditing, login security restrictions, etc.)
- 在配置出问题时回滚 SSH 配置（使用之前自动生成的备份）  
  Roll back SSH configuration using automatically created backups

所有脚本均支持 **中文 / English 双语界面**，入口脚本会先询问语言。  
All scripts support **Chinese / English UI**; the entry script will ask for language first.

### 快速开始 / Quick Start

1. 克隆仓库后进入目录 / Clone the repo and enter the directory:

   ```bash
   cd linux-server-initial
   chmod +x *.sh
   ```

2. 以 root 身份运行交互式向导（推荐） / Run the interactive wizard as root (recommended):

   ```bash
   sudo ./linux_server_initial.sh
   ```

   在向导中你可以 / From the wizard you can:
   - 创建新用户并初始化开发环境  
     Create a new user and initialize the dev environment
   - 配置 SSH 新端口 / 禁用 root / 禁用密码登录，并自动配置 UFW  
     Configure a new SSH port, disable root login and password auth, and set up UFW
   - 执行系统安全加固（sysctl、auditd、自动更新等）  
     Run system security hardening (sysctl, auditd, auto-updates, etc.)
   - 如遇问题，使用回滚功能恢复到最近一次 sshd_config 备份  
     If something goes wrong, roll back to the latest sshd_config backup

### 自动化部署 / Automated Deployment

支持通过配置文件实现非交互式自动化部署：  
Supports non-interactive automated deployment via configuration file:

1. 复制配置模板 / Copy the configuration template:

   ```bash
   cp config.env.example config.env
   ```

2. 编辑 `config.env`，取消注释并设置需要的选项 / Edit `config.env`, uncomment and set the options you need

3. 以非交互模式运行 / Run in non-interactive mode:

   ```bash
   sudo INIT_NON_INTERACTIVE=1 ./linux_server_initial.sh
   ```

**可用环境变量 / Available environment variables:**

| 变量 / Variable | 说明 / Description |
|----------------|-------------------|
| `INIT_LANG` | 语言：zh/en / Language: zh/en |
| `INIT_NON_INTERACTIVE` | 非交互模式 (1=启用) / Non-interactive mode |
| `INIT_SKIP_CHECKSUM` | 跳过完整性校验 (1=跳过) / Skip checksum verification |
| `SKIP_NETWORK_CHECK` | 跳过网络检查 (1=跳过) / Skip network check |

详细选项请参考 `config.env.example`。  
See `config.env.example` for detailed options.

### 单独运行脚本 / Run scripts individually

如果你只想执行某个步骤，也可以直接调用：  
If you only want to run a specific step, you can call the scripts directly:

- 仅初始化用户和开发环境 / Only initialize user and dev environment:

  ```bash
  sudo ./setup_env.sh
  ```

- 仅配置 SSH 和防火墙 / Only configure SSH and firewall:

  ```bash
  sudo ./setup_ssh_firewall.sh
  ```

- 仅执行系统安全加固 / Only run system security hardening:

  ```bash
  sudo ./setup_security_hardening.sh
  ```

- 出现 SSH 配置问题时回滚 / Roll back SSH config if something breaks:

  ```bash
  sudo ./rollback_ssh.sh
  ```

### 安全加固功能详情 / Security Hardening Details

`setup_security_hardening.sh` 脚本提供以下安全加固选项：  
The `setup_security_hardening.sh` script provides the following security hardening options:

| 功能 / Feature | 说明 / Description |
|---------------|-------------------|
| **sysctl 内核参数** | 防止 IP 欺骗、SYN 洪水攻击、ICMP 重定向等网络攻击；启用 ASLR 等内存保护 |
| **Kernel parameters (sysctl)** | Prevent IP spoofing, SYN flood attacks, ICMP redirects; enable ASLR memory protection |
| **禁用 IPv6** | 如不使用 IPv6，可选择禁用以减少攻击面 |
| **Disable IPv6** | Optionally disable IPv6 if not in use to reduce attack surface |
| **自动安全更新** | 配置 unattended-upgrades 自动安装安全补丁 |
| **Automatic security updates** | Configure unattended-upgrades to auto-install security patches |
| **auditd 审计** | 监控用户操作、配置变更、权限提升等关键事件 |
| **System auditing (auditd)** | Monitor user actions, config changes, privilege escalation, etc. |
| **登录安全** | 配置登录失败锁定、终端超时等 |
| **Login security** | Configure account lockout on failed logins, terminal timeout, etc. |
| **禁用危险服务** | 禁用 rpcbind、avahi-daemon 等不常用服务 |
| **Disable risky services** | Disable rpcbind, avahi-daemon, and other uncommon services |
| **文件权限加固** | 确保关键配置文件权限正确 |
| **File permission hardening** | Ensure proper permissions on critical config files |
| **安全工具** | 可选安装 rkhunter、chkrootkit、lynis 等 |
| **Security tools** | Optionally install rkhunter, chkrootkit, lynis, etc. |

### SSH 安全增强 / SSH Security Enhancements

`setup_ssh_firewall.sh` 现在包含以下增强的 SSH 安全配置：  
`setup_ssh_firewall.sh` now includes the following enhanced SSH security configurations:

- **认证限制**: `MaxAuthTries 3`, `LoginGraceTime 60`
- **会话保活**: `ClientAliveInterval 300`, `ClientAliveCountMax 2`
- **禁用不安全功能**: X11Forwarding, TcpForwarding, AgentForwarding 等
- **现代加密算法**: 仅允许 curve25519, AES-GCM, chacha20-poly1305 等强加密
- **用户白名单**: 可选配置 `AllowUsers` 限制可登录用户
- **详细日志**: `LogLevel VERBOSE` 便于审计

### 适用范围与注意事项 / Scope and Notes

- 当前脚本默认使用 `apt` 安装依赖，仅支持 **Ubuntu / Debian** 及其衍生系统。  
  Scripts use `apt` and currently support **Ubuntu / Debian** and derivatives only.
- 默认新建用户名为 `dev`（运行时可自定义），可以选择是否锁定该用户密码，仅通过 SSH 公钥登录。  
  Default new username is `dev` (customizable at runtime), and you can choose to lock this user's password so only SSH key auth works.
- 默认新增的 SSH 端口是 `2222`，UFW 对端口 `22` 和新端口都使用 `limit` 规则限制过于频繁的尝试，可选安装 fail2ban，并在脚本内提供**可选关闭 22 端口**的步骤（强烈建议在另一条会话中测试新端口没问题再选择关闭）。  
  Default additional SSH port is `2222`. UFW uses `limit` rules for both port `22` and the new port, you can optionally install fail2ban, and there is an **optional step in the script to disable port 22** (strongly recommended only after testing the new port from another session).

### 推荐实战流程 / Recommended Operational Flow

1) 首次登录服务器使用默认端口 22，运行入口脚本 `sudo ./linux_server_initial.sh`，按菜单先创建用户并初始化环境。  
   First login via port 22, run `sudo ./linux_server_initial.sh`, create the user and setup the environment.

2) 运行 SSH/防火墙脚本，设置新端口（默认 2222），启用 UFW limit，按需安装 fail2ban。  
   Run the SSH/firewall script, set the new port (default 2222), enable UFW limit, install fail2ban if desired.

3) 保持当前会话不断开，用 **另一条终端/窗口** 用新端口测试登录：  
   Keep the current session open; use another terminal/window to test the new port:  
   `ssh -p <new-port> <user>@<server-ip>`

4) 只有在确认新端口可以正常登录后，才在脚本里选择关闭 22；脚本会备份配置、修改 sshd_config 和 UFW，并重启 ssh。  
   Only after confirming the new port works, choose to disable port 22 in the script; it will back up configs, update sshd_config and UFW, then restart ssh.

5) 如遇异常，使用 `sudo ./rollback_ssh.sh` 恢复最近备份。  
   If something goes wrong, use `sudo ./rollback_ssh.sh` to restore the latest backup.

### 排查提示 / Troubleshooting

- SSH 日志：`journalctl -u ssh` 或 `/var/log/auth.log`（取决于发行版）  
  SSH logs: `journalctl -u ssh` or `/var/log/auth.log`
- fail2ban 日志/状态：`journalctl -u fail2ban`，`fail2ban-client status` / `fail2ban-client status sshd`  
  fail2ban logs/status: `journalctl -u fail2ban`, `fail2ban-client status` / `fail2ban-client status sshd`
- UFW 状态：`ufw status verbose`  
  UFW status: `ufw status verbose`
后续如果你希望支持其他发行版（如 CentOS / Rocky / AlmaLinux 等）或增加更多初始化选项，可以在此基础上继续扩展菜单和脚本逻辑。  
If you want to support other distros (CentOS / Rocky / AlmaLinux, etc.) or add more initialization options, you can extend the menu and scripts based on this structure.
