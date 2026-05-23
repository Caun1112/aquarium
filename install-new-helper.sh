#!/bin/bash
set -e

echo "更新助手到新版本..."

# 停止服务
sudo launchctl bootout system /Library/LaunchDaemons/com.aquarium.helper.plist 2>/dev/null || true

# 复制新助手
sudo cp .build/DerivedData/Build/Products/Debug/aquarium-helper /Library/PrivilegedHelperTools/com.aquarium.helper
sudo chmod 755 /Library/PrivilegedHelperTools/com.aquarium.helper

# 重启服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.aquarium.helper.plist
sudo launchctl enable system/com.aquarium.helper

echo "✅ 助手已更新"
echo "查看日志: tail -f /Library/Logs/AquariumHelper.log"
