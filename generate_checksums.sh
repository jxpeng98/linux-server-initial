#!/bin/bash
# generate_checksums.sh
# 生成脚本文件的 SHA256 校验和
# 用法: ./generate_checksums.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 需要校验的核心脚本文件列表
SCRIPT_FILES=(
  "common.sh"
  "linux_server_initial.sh"
  "setup_env.sh"
  "setup_ssh_firewall.sh"
  "setup_security_hardening.sh"
  "rollback_ssh.sh"
)

CHECKSUM_FILE="checksums.sha256"

echo "Generating checksums for script files..."

# 检查所有文件是否存在
MISSING_FILES=()
for file in "${SCRIPT_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo "Error: Missing files:"
  for file in "${MISSING_FILES[@]}"; do
    echo "  - $file"
  done
  exit 1
fi

# 生成校验和
sha256sum "${SCRIPT_FILES[@]}" > "$CHECKSUM_FILE"

echo "✅ Checksums generated successfully: $CHECKSUM_FILE"
echo ""
echo "Contents:"
cat "$CHECKSUM_FILE"
