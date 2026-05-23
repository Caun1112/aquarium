# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Aquarium 是一个 macOS 菜单栏应用，用于在合盖时保持 Mac 唤醒。它使用特权助手架构来修改系统电源管理设置。

## 构建和开发命令

项目使用 XcodeGen 生成 Xcode 项目文件。所有构建命令都在 Makefile 中定义：

```bash
# 生成 Xcode 项目（修改 project.yml 后必须运行）
make generate

# 构建 Debug 版本
make build

# 构建并打开应用
make open

# 构建 Release 版本
make release

# 打包发布版本（生成 .build/Aquarium-0.1.9.zip）
make package

# 安装特权助手到系统（需要 sudo）
make install-helper

# 卸载特权助手
make uninstall-helper

# 清理构建产物
make clean
```

## 架构说明

### 双进程架构

项目由两个独立的可执行文件组成：

1. **Aquarium.app**（主应用）
   - SwiftUI 菜单栏应用
   - 使用 Swift 6.0 的 `@Observable` 宏
   - 负责用户界面和配置管理
   - 通过 XPC 与特权助手通信

2. **aquarium-helper**（特权助手）
   - 命令行工具，以 root 权限运行
   - 由 launchd 管理（`/Library/LaunchDaemons/com.aquarium.helper.plist`）
   - 负责修改系统电源设置（`pmset disablesleep`）
   - 控制内置显示器亮度（通过 DisplayServices 私有框架）

### 代码组织

- **Sources/AquariumApp/**：主应用代码
  - `AquariumController`：核心控制器，管理配置和助手安装
  - `SettingsView`：SwiftUI 设置界面
  - `PrivilegedHelperInstaller`：助手安装逻辑

- **Sources/AquariumHelper/**：特权助手代码
  - `main.swift`：助手主入口

- **Sources/AquariumCore/**：共享代码
  - `AquariumConfig`：配置数据模型（主应用和助手共享）

### 配置存储

配置文件存储在 `/Library/Application Support/Aquarium/config.json`，由主应用写入，助手读取。配置包括：
- 是否启用防止合盖睡眠
- 应用过滤器（仅在特定应用运行时生效）
- 电池阈值设置
- 亮度控制选项

### 特权助手安装流程

1. 主应用启动时检查助手是否已安装（`PrivilegedHelperInstaller.isInstalled()`）
2. 如果未安装，调用 `installFromBundle()` 安装助手
3. 安装过程会提示用户输入管理员密码
4. 助手安装到 `/Library/PrivilegedHelperTools/com.aquarium.helper`
5. launchd 配置安装到 `/Library/LaunchDaemons/`

## 重要技术细节

- **Swift 6.0**：使用严格并发检查，所有 UI 代码标记为 `@MainActor`
- **私有框架**：助手链接 DisplayServices 和 CoreGraphics 私有框架来控制亮度
- **代码签名**：需要手动签名配置（见 `project.yml` 中的 `CODE_SIGN_IDENTITY`）
- **沙箱**：主应用不使用沙箱，助手以 root 权限运行
- **最低系统要求**：macOS 14.0

## 修改项目配置

项目配置在 `project.yml` 中定义（XcodeGen 格式）。修改后必须运行 `make generate` 重新生成 Xcode 项目。

不要直接修改 `Aquarium.xcodeproj`，因为它是生成的文件。
