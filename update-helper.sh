#!/bin/bash
set -e

echo "正在更新 Aquarium 助手..."

# 停止现有服务
sudo launchctl bootout system /Library/LaunchDaemons/com.aquarium.helper.plist 2>/dev/null || true

# 复制新的助手二进制文件
sudo install -m 755 ".build/DerivedData/Build/Products/Debug/aquarium-helper" "/Library/PrivilegedHelperTools/com.aquarium.helper"

# 重新启动服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.aquarium.helper.plist
sudo launchctl enable system/com.aquarium.helper

echo "✅ 助手已更新并重启"
echo ""
echo "查看日志："
echo "  tail -f /Library/Logs/AquariumHelper.log"
