#!/bin/bash
# setup_nginx_proxy.sh
# 安装 nginx 并配置本地反向代理（用于 Cloudflare Zero Trust）
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
  echo -e "${GREEN}=== Nginx Reverse Proxy Setup (for Cloudflare Zero Trust) ===${NC}"
else
  echo -e "${GREEN}=== Nginx 反向代理配置（用于 Cloudflare Zero Trust）===${NC}"
fi

# 配置路径
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled"
CONF_NAME="cloudflare-proxy"
CONF_FILE="${NGINX_CONF_DIR}/${CONF_NAME}"
SERVICES_DIR="/etc/nginx/proxy-services.d"

# ============================================
# 辅助函数
# ============================================

# 生成 location 配置块
generate_location_block() {
  local path="$1"
  local target="$2"
  local name="$3"
  
  cat << EOF
    # Service: ${name}
    location ${path} {
        proxy_pass ${target};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
    }
EOF
}

# ============================================
# 1. 安装 nginx
# ============================================
msg "${GREEN}1. 安装 nginx...${NC}" "${GREEN}1. Installing nginx...${NC}"
log_info "Installing nginx"

if ! command -v nginx &>/dev/null; then
  apt update
  apt install -y nginx
  log_info "nginx installed successfully"
else
  msg "${YELLOW}nginx 已安装，跳过安装步骤${NC}" "${YELLOW}nginx already installed, skipping${NC}"
  log_info "nginx already installed"
fi

# ============================================
# 2. 配置监听端口
# ============================================
DEFAULT_LISTEN_PORT="9999"
prompt_read "nginx 监听端口 (默认: ${DEFAULT_LISTEN_PORT}): " \
            "nginx listen port (default: ${DEFAULT_LISTEN_PORT}): " \
            "$DEFAULT_LISTEN_PORT" LISTEN_PORT
LISTEN_PORT="${LISTEN_PORT:-$DEFAULT_LISTEN_PORT}"

# 验证端口号
if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -le 0 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
  msg "${RED}无效端口号: $LISTEN_PORT${NC}" "${RED}Invalid port: $LISTEN_PORT${NC}"
  exit 1
fi

log_info "Using listen port: $LISTEN_PORT"

# 创建服务配置目录
mkdir -p "$SERVICES_DIR"

# ============================================
# 3. 配置后端服务
# ============================================
msg "" ""
msg "${GREEN}配置反向代理后端服务${NC}" "${GREEN}Configure reverse proxy backends${NC}"
msg "可以添加多个后端服务，每个服务需要提供名称、路径和目标地址" \
    "You can add multiple backend services, each needs a name, path and target address"
msg "之后可使用 manage_nginx_service.sh 单独管理服务" \
    "Later you can use manage_nginx_service.sh to manage services individually"
msg "" ""

# 服务配置循环
SERVICE_COUNT=0

while true; do
  prompt_read "请输入服务名称 (如 myapp，输入 done 完成配置): " \
              "Enter service name (e.g., myapp, type 'done' to finish): " \
              "" SERVICE_NAME
  
  if [ "$SERVICE_NAME" = "done" ] || [ -z "$SERVICE_NAME" ]; then
    if [ $SERVICE_COUNT -eq 0 ]; then
      msg "${YELLOW}至少需要配置一个后端服务${NC}" "${YELLOW}At least one backend service is required${NC}"
      continue
    fi
    break
  fi
  
  # 规范化名称
  SERVICE_NAME=$(echo "$SERVICE_NAME" | tr -cd 'a-zA-Z0-9-' | tr '[:upper:]' '[:lower:]')
  
  # 选择配置类型
  if is_en; then
    echo ""
    echo "Service type for '${SERVICE_NAME}':"
    echo "  1) Path-based (e.g., /api, /app) - same domain, different paths"
    echo "  2) Domain-based (e.g., gitea.domain.com) - separate domain"
    read -rp "Select type [1/2] (default: 2): " SERVICE_TYPE
  else
    echo ""
    echo "服务 '${SERVICE_NAME}' 的类型："
    echo "  1) 基于路径 (如 /api, /app) - 同一域名，不同路径"
    echo "  2) 基于域名 (如 gitea.domain.com) - 独立域名"
    read -rp "请选择类型 [1/2] (默认: 2): " SERVICE_TYPE
  fi
  
  SERVICE_TYPE="${SERVICE_TYPE:-2}"
  
  local PROXY_PATH="/"
  local PROXY_DOMAIN=""
  
  if [ "$SERVICE_TYPE" = "1" ]; then
    # 基于路径
    prompt_read "请输入服务路径 (如 / 或 /api): " \
                "Enter service path (e.g., / or /api): " \
                "/" PROXY_PATH
  else
    # 基于域名
    prompt_read "域名 (如 app.yourdomain.com): " \
                "Domain name (e.g., app.yourdomain.com): " \
                "" PROXY_DOMAIN
    
    if [ -z "$PROXY_DOMAIN" ]; then
      msg "${YELLOW}域名不能为空，请重新输入${NC}" "${YELLOW}Domain name cannot be empty, please retry${NC}"
      continue
    fi
  fi
  
  prompt_read "请输入后端地址 (如 http://127.0.0.1:3000): " \
              "Enter backend address (e.g., http://127.0.0.1:3000): " \
              "" PROXY_TARGET
  
  if [ -z "$PROXY_TARGET" ]; then
    msg "${YELLOW}后端地址不能为空，请重新输入${NC}" "${YELLOW}Backend address cannot be empty, please retry${NC}"
    continue
  fi
  
  # 保存服务配置到独立文件
  SERVICE_FILE="${SERVICES_DIR}/${SERVICE_NAME}.conf"
  
  if [ "$SERVICE_TYPE" = "1" ]; then
    # 基于路径的配置
    cat > "$SERVICE_FILE" << EOF
# Service: ${SERVICE_NAME}
# Type: Path-based
# Path: ${PROXY_PATH} -> ${PROXY_TARGET}
# Created: $(date '+%Y-%m-%d %H:%M:%S')
$(generate_location_block "$PROXY_PATH" "$PROXY_TARGET" "$SERVICE_NAME")
EOF
    msg "${GREEN}已添加: ${SERVICE_NAME} (路径: ${PROXY_PATH} -> ${PROXY_TARGET})${NC}" \
        "${GREEN}Added: ${SERVICE_NAME} (path: ${PROXY_PATH} -> ${PROXY_TARGET})${NC}"
  else
    # 基于域名的配置
    cat > "$SERVICE_FILE" << EOF
# Service: ${SERVICE_NAME}
# Type: Domain-based
# Domain: ${PROXY_DOMAIN} -> ${PROXY_TARGET}
# Created: $(date '+%Y-%m-%d %H:%M:%S')
server {
    listen 127.0.0.1:${LISTEN_PORT};
    listen [::1]:${LISTEN_PORT};
    
    server_name ${PROXY_DOMAIN};
    
    # 日志
    access_log /var/log/nginx/cloudflare-proxy-access.log;
    error_log /var/log/nginx/cloudflare-proxy-error.log;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Cloudflare 相关头
    real_ip_header CF-Connecting-IP;
    
    location / {
        proxy_pass ${PROXY_TARGET};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
    }
}
EOF
    msg "${GREEN}已添加: ${SERVICE_NAME} (域名: ${PROXY_DOMAIN} -> ${PROXY_TARGET})${NC}" \
        "${GREEN}Added: ${SERVICE_NAME} (domain: ${PROXY_DOMAIN} -> ${PROXY_TARGET})${NC}"
  fi
  
  log_info "Added service: ${SERVICE_NAME} (type: ${SERVICE_TYPE}, target: ${PROXY_TARGET})"
  
  ((SERVICE_COUNT++))
done

# ============================================
# 4. 生成 nginx 主配置
# ============================================
msg "${GREEN}2. 生成 nginx 配置...${NC}" "${GREEN}2. Generating nginx configuration...${NC}"

# 备份现有配置
if [ -f "$CONF_FILE" ]; then
  BACKUP_FILE="${CONF_FILE}.bak.$(date +%F-%H%M%S)"
  cp "$CONF_FILE" "$BACKUP_FILE"
  msg "${YELLOW}已备份现有配置到: ${BACKUP_FILE}${NC}" \
      "${YELLOW}Backed up existing config to: ${BACKUP_FILE}${NC}"
  log_info "Backed up existing config to $BACKUP_FILE"
fi

# 分离基于路径和基于域名的服务
LOCATION_BLOCKS=""
SERVER_BLOCKS=""

for service_file in "$SERVICES_DIR"/*.conf; do
  if [ -f "$service_file" ]; then
    if grep -q "^# Type: Path-based" "$service_file"; then
      # 基于路径的服务
      LOCATION_BLOCKS+="$(grep -A 999 "^    location" "$service_file" || cat "$service_file")"
      LOCATION_BLOCKS+=$'\n'
    elif grep -q "^# Type: Domain-based" "$service_file"; then
      # 基于域名的服务
      SERVER_BLOCKS+="$(grep -A 999 "^server {" "$service_file" || cat "$service_file")"
      SERVER_BLOCKS+=$'\n'
    else
      # 兼容旧格式
      LOCATION_BLOCKS+="$(cat "$service_file")"
      LOCATION_BLOCKS+=$'\n'
    fi
  fi
done

# 写入主配置文件
cat > "$CONF_FILE" << EOF
# Nginx reverse proxy for Cloudflare Zero Trust
# Generated by linux-server-initial on $(date '+%Y-%m-%d %H:%M:%S')
# Listen on localhost:${LISTEN_PORT} for Cloudflare Tunnel
#
# Service configurations are stored in: ${SERVICES_DIR}/
# Use manage_nginx_service.sh to add/remove services

# Default server block (for path-based routing)
server {
    listen 127.0.0.1:${LISTEN_PORT} default_server;
    listen [::1]:${LISTEN_PORT} default_server;
    
    server_name _;
    
    # 日志
    access_log /var/log/nginx/cloudflare-proxy-access.log;
    error_log /var/log/nginx/cloudflare-proxy-error.log;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Cloudflare 相关头
    real_ip_header CF-Connecting-IP;
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\\n";
        add_header Content-Type text/plain;
    }

${LOCATION_BLOCKS}
}

# Domain-based server blocks
${SERVER_BLOCKS}
EOF

log_info "Generated nginx config at $CONF_FILE"

# ============================================
# 5. 启用配置
# ============================================
msg "${GREEN}3. 启用 nginx 配置...${NC}" "${GREEN}3. Enabling nginx configuration...${NC}"

# 删除默认站点（可选）
if [ -L "${NGINX_CONF_ENABLED}/default" ]; then
  prompt_read "是否禁用 nginx 默认站点? [y/N]: " \
              "Disable nginx default site? [y/N]: " \
              "n" DISABLE_DEFAULT
  if [[ "$DISABLE_DEFAULT" =~ ^[Yy]$ ]]; then
    rm -f "${NGINX_CONF_ENABLED}/default"
    msg "${YELLOW}已禁用默认站点${NC}" "${YELLOW}Default site disabled${NC}"
    log_info "Disabled default nginx site"
  fi
fi

# 创建符号链接
if [ ! -L "${NGINX_CONF_ENABLED}/${CONF_NAME}" ]; then
  ln -s "$CONF_FILE" "${NGINX_CONF_ENABLED}/${CONF_NAME}"
fi

# ============================================
# 6. 测试并重载配置
# ============================================
msg "${GREEN}4. 测试 nginx 配置...${NC}" "${GREEN}4. Testing nginx configuration...${NC}"

if nginx -t 2>&1; then
  msg "${GREEN}配置测试通过${NC}" "${GREEN}Configuration test passed${NC}"
  log_info "nginx config test passed"
else
  msg "${RED}配置测试失败，请检查配置文件${NC}" "${RED}Configuration test failed, please check config${NC}"
  log_error "nginx config test failed"
  exit 1
fi

# ============================================
# 7. 启动/重载 nginx
# ============================================
msg "${GREEN}5. 重载 nginx 服务...${NC}" "${GREEN}5. Reloading nginx service...${NC}"

systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

log_info "nginx service reloaded"

# ============================================
# 8. 显示配置摘要
# ============================================
echo ""
echo -e "${GREEN}=====================================================${NC}"
if is_en; then
  echo -e "${GREEN}✅ Nginx reverse proxy configured successfully${NC}"
  echo ""
  echo -e "Listen address: ${GREEN}127.0.0.1:${LISTEN_PORT}${NC}"
  echo -e "Config file: ${GREEN}${CONF_FILE}${NC}"
  echo -e "Services dir: ${GREEN}${SERVICES_DIR}${NC}"
  echo ""
  echo -e "Configured backends:"
  for service_file in "$SERVICES_DIR"/*.conf; do
    if [ -f "$service_file" ]; then
      name=$(basename "$service_file" .conf)
      if grep -q "^# Type: Domain-based" "$service_file"; then
        domain=$(grep -oP '(?<=server_name )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        backend=$(grep -oP '(?<=proxy_pass )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        echo -e "  ${GREEN}${name}${NC} (domain): ${domain} -> ${backend}"
      else
        path=$(grep -oP '(?<=location )[^ ]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        backend=$(grep -oP '(?<=proxy_pass )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        echo -e "  ${GREEN}${name}${NC} (path): ${path} -> ${backend}"
      fi
    fi
  done
  echo ""
  echo -e "Health check: ${GREEN}http://127.0.0.1:${LISTEN_PORT}/health${NC}"
  echo ""
  echo -e "${YELLOW}Service Management:${NC}"
  echo -e "  Add service:    ${GREEN}sudo ./manage_nginx_service.sh add${NC}"
  echo -e "  Remove service: ${GREEN}sudo ./manage_nginx_service.sh remove${NC}"
  echo -e "  List services:  ${GREEN}sudo ./manage_nginx_service.sh list${NC}"
  echo ""
  echo -e "${YELLOW}Cloudflare Tunnel Configuration:${NC}"
  echo -e "In Cloudflare Zero Trust Dashboard or config.yml:"
  echo -e "  ${GREEN}Forward ALL domains (*.yourdomain.com) to:${NC}"
  echo -e "  ${GREEN}http://127.0.0.1:${LISTEN_PORT}${NC}"
  echo ""
  echo -e "Example config.yml:"
  echo -e "  ingress:"
  echo -e "    - hostname: \"*.yourdomain.com\""
  echo -e "      service: http://127.0.0.1:${LISTEN_PORT}"
  echo -e "    - service: http_status:404"
  echo ""
  echo -e "${YELLOW}How it works:${NC}"
  echo -e "  Cloudflare → 127.0.0.1:${LISTEN_PORT} (single entry point)"
  echo -e "  Nginx routes by domain to different backend services"
else
  echo -e "${GREEN}✅ Nginx 反向代理配置完成${NC}"
  echo ""
  echo -e "监听地址: ${GREEN}127.0.0.1:${LISTEN_PORT}${NC}"
  echo -e "配置文件: ${GREEN}${CONF_FILE}${NC}"
  echo -e "服务目录: ${GREEN}${SERVICES_DIR}${NC}"
  echo ""
  echo -e "已配置的后端服务:"
  for service_file in "$SERVICES_DIR"/*.conf; do
    if [ -f "$service_file" ]; then
      name=$(basename "$service_file" .conf)
      if grep -q "^# Type: Domain-based" "$service_file"; then
        domain=$(grep -oP '(?<=server_name )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        backend=$(grep -oP '(?<=proxy_pass )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        echo -e "  ${GREEN}${name}${NC} (域名): ${domain} -> ${backend}"
      else
        path=$(grep -oP '(?<=location )[^ ]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        backend=$(grep -oP '(?<=proxy_pass )[^;]+' "$service_file" 2>/dev/null | head -1 || echo "?")
        echo -e "  ${GREEN}${name}${NC} (路径): ${path} -> ${backend}"
      fi
    fi
  done
  echo ""
  echo -e "健康检查: ${GREEN}http://127.0.0.1:${LISTEN_PORT}/health${NC}"
  echo ""
  echo -e "${YELLOW}服务管理:${NC}"
  echo -e "  添加服务: ${GREEN}sudo ./manage_nginx_service.sh add${NC}"
  echo -e "  删除服务: ${GREEN}sudo ./manage_nginx_service.sh remove${NC}"
  echo -e "  列出服务: ${GREEN}sudo ./manage_nginx_service.sh list${NC}"
  echo ""
  echo -e "${YELLOW}Cloudflare Tunnel 配置:${NC}"
  echo -e "在 Cloudflare Zero Trust Dashboard 或 config.yml 中:"
  echo -e "  ${GREEN}将所有域名 (*.yourdomain.com) 转发到:${NC}"
  echo -e "  ${GREEN}http://127.0.0.1:${LISTEN_PORT}${NC}"
  echo ""
  echo -e "示例 config.yml:"
  echo -e "  ingress:"
  echo -e "    - hostname: \"*.yourdomain.com\""
  echo -e "      service: http://127.0.0.1:${LISTEN_PORT}"
  echo -e "    - service: http_status:404"
  echo ""
  echo -e "${YELLOW}工作原理:${NC}"
  echo -e "  Cloudflare → 127.0.0.1:${LISTEN_PORT} (统一入口)"
  echo -e "  Nginx 根据域名自动分流到不同的后端服务"
fi
echo -e "${GREEN}=====================================================${NC}"
