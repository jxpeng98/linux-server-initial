#!/bin/bash
# setup_env.sh
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

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

if [ "$EUID" -ne 0 ]; then
  if is_en; then
    echo -e "${RED}Please run this script as root (sudo ./setup_env.sh)${NC}"
  else
    echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./setup_env.sh)${NC}"
  fi
  exit 1
fi

if is_en; then
  echo -e "${GREEN}=== User / Dev Environment Initialization (Ubuntu/Debian) ===${NC}"
else
  echo -e "${GREEN}=== 用户环境 / 开发环境初始化 (Ubuntu/Debian) ===${NC}"
fi

if ! command -v apt &>/dev/null; then
  if is_en; then
    echo -e "${RED}This script currently supports only apt-based distros (Debian/Ubuntu, etc.).${NC}"
  else
    echo -e "${RED}当前脚本暂仅支持基于 apt 的发行版 (Debian/Ubuntu 等)。${NC}"
  fi
  exit 1
fi

# 1. 交互选择用户名
DEFAULT_USER="dev"
if is_en; then
  prompt_read "请输入要创建/配置的用户名 (默认: ${DEFAULT_USER}): " \
              "Enter the username to create/configure (default: ${DEFAULT_USER}): " \
              "$DEFAULT_USER" INPUT_USER
else
  prompt_read "请输入要创建/配置的用户名 (默认: ${DEFAULT_USER}): " \
              "Enter the username to create/configure (default: ${DEFAULT_USER}): " \
              "$DEFAULT_USER" INPUT_USER
fi
NEW_USER="${INPUT_USER:-$DEFAULT_USER}"

if is_en; then
  echo -e "Using user: ${GREEN}${NEW_USER}${NC}"
else
  echo -e "将使用用户: ${GREEN}${NEW_USER}${NC}"
fi

# 2. 确认是否配置 sudo 免密
if is_en; then
  prompt_read "是否为 ${NEW_USER} 配置 sudo 免密码? [y/N]: " \
              "Configure passwordless sudo for ${NEW_USER}? [y/N]: " \
              "n" SUDO_NOPASSWD
else
  prompt_read "是否为 ${NEW_USER} 配置 sudo 免密码? [y/N]: " \
              "Configure passwordless sudo for ${NEW_USER}? [y/N]: " \
              "n" SUDO_NOPASSWD
fi
SUDO_NOPASSWD="${SUDO_NOPASSWD:-n}"

# 3. 安装基础依赖
if is_en; then
  echo -e "${GREEN}1. Updating system and installing base packages...${NC}"
else
  echo -e "${GREEN}1. 更新系统并安装基础工具...${NC}"
fi
apt update
apt install -y git curl zsh vim ufw ca-certificates gnupg build-essential \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget llvm \
  libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
  python3-openssl

# 4. 创建用户并赋予 sudo 组
if id "$NEW_USER" &>/dev/null; then
    if is_en; then
      echo -e "${YELLOW}User $NEW_USER already exists, skipping creation.${NC}"
    else
      echo -e "${YELLOW}用户 $NEW_USER 已存在，跳过创建${NC}"
    fi
else
    useradd -m -s /usr/bin/zsh -G sudo "$NEW_USER"
    if is_en; then
      echo -e "${GREEN}User $NEW_USER created successfully.${NC}"
    else
      echo -e "${GREEN}用户 $NEW_USER 创建成功${NC}"
    fi
fi

# 5. 配置 sudo 免密
if [[ "$SUDO_NOPASSWD" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}Configuring passwordless sudo for ${NEW_USER}...${NC}"
  else
    echo -e "${GREEN}配置 ${NEW_USER} sudo 免密...${NC}"
  fi
  echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
  chmod 0440 "/etc/sudoers.d/$NEW_USER"
  visudo -cf "/etc/sudoers.d/$NEW_USER" >/dev/null
else
  if is_en; then
    echo -e "${YELLOW}Skip configuring passwordless sudo.${NC}"
  else
    echo -e "${YELLOW}跳过配置 sudo 免密${NC}"
  fi
fi

# 6. 配置 SSH Key
USER_HOME=$(eval echo "~$NEW_USER")
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$NEW_USER:$NEW_USER" "$SSH_DIR"

echo -e "${GREEN}==============================================${NC}"
if is_en; then
  echo -e "${GREEN}Please paste your SSH public key, then press Enter:${NC}"
else
  echo -e "${GREEN}请粘贴你的 SSH 公钥 (Public Key)，然后回车确认：${NC}"
fi
echo -e "${GREEN}==============================================${NC}"
read -r PUBLIC_KEY

if [ -z "$PUBLIC_KEY" ]; then
    if is_en; then
      echo -e "${RED}Public key is empty, exiting.${NC}"
    else
      echo -e "${RED}公钥为空，退出${NC}"
    fi
    exit 1
fi

# 幂等：如果已存在相同公钥就不重复写入
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown "$NEW_USER:$NEW_USER" "$AUTH_KEYS"

if ! grep -qF "$PUBLIC_KEY" "$AUTH_KEYS"; then
  echo "$PUBLIC_KEY" >> "$AUTH_KEYS"
  if is_en; then
    echo -e "${GREEN}SSH public key written to ${AUTH_KEYS}.${NC}"
  else
    echo -e "${GREEN}SSH 公钥已写入 ${AUTH_KEYS}${NC}"
  fi
else
  if is_en; then
    echo -e "${YELLOW}This SSH public key already exists in authorized_keys, skipping append.${NC}"
  else
    echo -e "${YELLOW}该 SSH 公钥已存在于 authorized_keys 中，跳过追加${NC}"
  fi
fi

# 7.1 可选：锁定用户密码，仅允许 SSH 公钥登录
if is_en; then
  prompt_read "是否锁定 ${NEW_USER} 的密码，仅允许 SSH 公钥登录? [Y/n]: " \
              "Lock password for ${NEW_USER} so only SSH key auth is allowed? [Y/n]: " \
              "y" LOCK_PASSWD
else
  prompt_read "是否锁定 ${NEW_USER} 的密码，仅允许 SSH 公钥登录? [Y/n]: " \
              "Lock password for ${NEW_USER} so only SSH key auth is allowed? [Y/n]: " \
              "y" LOCK_PASSWD
fi
LOCK_PASSWD="${LOCK_PASSWD:-y}"

if [[ "$LOCK_PASSWD" =~ ^[Yy]$ ]]; then
  if passwd -l "$NEW_USER" >/dev/null 2>&1; then
    if is_en; then
      echo -e "${GREEN}Password for ${NEW_USER} locked. Only SSH key login will work (for services that allow it).${NC}"
    else
      echo -e "${GREEN}已锁定 ${NEW_USER} 的密码，仅可通过 SSH 公钥等非密码方式登录（取决于服务配置）。${NC}"
    fi
  else
    if is_en; then
      echo -e "${YELLOW}Failed to lock password for ${NEW_USER}. Please check manually if needed.${NC}"
    else
      echo -e "${YELLOW}锁定 ${NEW_USER} 密码失败，如有需要请手动检查。${NC}"
    fi
  fi
else
  if is_en; then
    echo -e "${YELLOW}Password for ${NEW_USER} kept unchanged.${NC}"
  else
    echo -e "${YELLOW}保留 ${NEW_USER} 的现有密码配置，不做锁定。${NC}"
  fi
fi

# 8. 安装 Oh My Zsh 及插件
if is_en; then
  echo -e "${GREEN}2. Installing Oh My Zsh and plugins for ${NEW_USER}...${NC}"
else
  echo -e "${GREEN}2. 为 ${NEW_USER} 安装 Oh My Zsh 及插件...${NC}"
fi

if [ ! -d "${USER_HOME}/.oh-my-zsh" ]; then
    sudo -u "$NEW_USER" sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    if is_en; then
      echo -e "${YELLOW}Oh My Zsh already exists, skipping installation.${NC}"
    else
      echo -e "${YELLOW}Oh My Zsh 已存在，跳过安装${NC}"
    fi
fi

ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"
mkdir -p "$ZSH_CUSTOM/plugins"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    sudo -u "$NEW_USER" git clone https://github.com/zsh-users/zsh-autosuggestions \
      "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    sudo -u "$NEW_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

ZSHRC="${USER_HOME}/.zshrc"
if [ -f "$ZSHRC" ]; then
  if grep -q "^plugins=(git)" "$ZSHRC"; then
    sed -i 's/^plugins=(git)/plugins=(git sudo docker docker-compose zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
  elif ! grep -q "zsh-autosuggestions" "$ZSHRC"; then
    echo 'plugins=(git sudo docker docker-compose zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"
  fi
fi
chown "$NEW_USER:$NEW_USER" "$ZSHRC"

# 9. 是否安装 mise + Python/Node/uv/pnpm
if is_en; then
  prompt_read "是否安装 mise + Python/Node/uv/pnpm? [Y/n]: " \
              "Install mise + Python/Node/uv/pnpm? [Y/n]: " \
              "y" INSTALL_MISE
else
  prompt_read "是否安装 mise + Python/Node/uv/pnpm? [Y/n]: " \
              "Install mise + Python/Node/uv/pnpm? [Y/n]: " \
              "y" INSTALL_MISE
fi
INSTALL_MISE="${INSTALL_MISE:-y}"

if [[ "$INSTALL_MISE" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}3. Installing Mise and language runtimes...${NC}"
  else
    echo -e "${GREEN}3. 安装 Mise 及语言环境...${NC}"
  fi
  if [ ! -x "${USER_HOME}/.local/bin/mise" ]; then
    sudo -u "$NEW_USER" bash -c "curl -fsSL https://mise.run | sh"
  else
    if is_en; then
      echo -e "${YELLOW}mise already exists, skipping binary installation.${NC}"
    else
      echo -e "${YELLOW}mise 已存在，跳过安装二进制${NC}"
    fi
  fi

  if ! grep -q "mise activate zsh" "$ZSHRC"; then
      echo 'eval "$('"${USER_HOME}"'/.local/bin/mise activate zsh)"' >> "$ZSHRC"
  fi

  if is_en; then
    echo -e "${GREEN}Installing Python / Node / uv / pnpm via mise (existing installs will be reused automatically)...${NC}"
  else
    echo -e "${GREEN}通过 mise 安装 Python / Node / uv / pnpm (如已安装会自动复用)...${NC}"
  fi
  sudo -u "$NEW_USER" "${USER_HOME}/.local/bin/mise" use --global python@latest
  sudo -u "$NEW_USER" "${USER_HOME}/.local/bin/mise" use --global node@latest
  sudo -u "$NEW_USER" "${USER_HOME}/.local/bin/mise" use --global uv@latest
  sudo -u "$NEW_USER" "${USER_HOME}/.local/bin/mise" use --global pnpm@latest
else
  if is_en; then
    echo -e "${YELLOW}Skipping mise / language runtime installation.${NC}"
  else
    echo -e "${YELLOW}跳过 mise / 语言环境安装${NC}"
  fi
fi

# 10. 是否安装 Docker
if is_en; then
  prompt_read "是否安装 Docker (Docker Engine + Compose 插件)? [Y/n]: " \
              "Install Docker (Docker Engine + Compose plugin)? [Y/n]: " \
              "y" INSTALL_DOCKER
else
  prompt_read "是否安装 Docker (Docker Engine + Compose 插件)? [Y/n]: " \
              "Install Docker (Docker Engine + Compose plugin)? [Y/n]: " \
              "y" INSTALL_DOCKER
fi
INSTALL_DOCKER="${INSTALL_DOCKER:-y}"

if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
  if is_en; then
    echo -e "${GREEN}4. Installing Docker...${NC}"
  else
    echo -e "${GREEN}4. 安装 Docker...${NC}"
  fi
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
      chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker "$NEW_USER"
else
  if is_en; then
    echo -e "${YELLOW}Skipping Docker installation.${NC}"
  else
    echo -e "${YELLOW}跳过 Docker 安装${NC}"
  fi
fi

echo -e "${GREEN}=====================================================${NC}"
if is_en; then
  echo -e "${GREEN}✅ User / dev environment initialization completed.${NC}"
  echo -e "User: ${GREEN}$NEW_USER${NC}"
  echo -e "It is recommended to reconnect via SSH as this user and run: ${GREEN}source ~/.zshrc${NC}"
else
  echo -e "${GREEN}✅ 用户/开发环境初始化完成${NC}"
  echo -e "用户: ${GREEN}$NEW_USER${NC}"
  echo -e "建议退出当前 SSH 后以该用户重新登录，并执行: ${GREEN}source ~/.zshrc${NC}"
fi
echo -e "${GREEN}=====================================================${NC}"
