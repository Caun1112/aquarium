# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

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


<claude-mem-context>
# Memory Context

# [aquarium] recent context, 2026-05-23 2:27pm GMT+8

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (9,392t read) | 603,997t work | 98% savings

### May 23, 2026
604 10:38a ✅ SettingsView 设置界面中文本地化（第三部分）
605 10:39a ✅ AquariumController 状态消息和对话框中文本地化
606 " ✅ 安装 XcodeGen 构建工具
607 10:40a ✅ 修改项目代码签名配置为自动签名
608 " ✅ 成功构建 Aquarium 项目并生成发布包
609 10:41a ✅ 构建成功完成并生成可分发的应用包
610 11:10a 🔵 当前日志系统实现
611 11:11a 🟣 实现日志轮转功能
612 " ✅ 在启动时调用日志轮转
S306 Aquarium 项目改进 - 日志管理优化和问题修复 (May 23 at 11:16 AM)
S307 Aquarium 项目改进 - 日志管理优化，版本更新至 0.2.1 (May 23 at 11:16 AM)
S308 Aquarium 项目改进 - 日志管理优化，发布 0.2.1 版本 (May 23 at 11:16 AM)
S309 Aquarium 项目改进 - 日志管理优化，完整发布 v0.2.1 版本 (May 23 at 11:19 AM)
S310 Aquarium 项目改进 - 日志管理优化，v0.2.1 版本发布遇到推送失败 (May 23 at 11:19 AM)
S311 Aquarium 项目改进 - 日志管理优化，v0.2.1 版本发布（推送失败待重试） (May 23 at 11:23 AM)
S312 Aquarium 项目改进 - 日志管理优化，v0.2.1 版本完整发布和验证 (May 23 at 11:23 AM)
S315 重新设计咖啡杯图标为更精致的样式，包含椭圆杯口、曲线杯身和右侧杯把，使用模板图像适配系统着色 (May 23 at 11:23 AM)
613 1:40p 🔵 Aquarium 应用当前状态栏图标实现机制
614 " 🔵 Aquarium 项目结构和图标实现细节
615 1:42p 🔵 Aquarium 项目资源结构和 Assets 配置
616 1:47p 🟣 状态栏图标从鱼图标替换为自定义咖啡杯图标
617 " 🔵 Aquarium 项目当前版本配置为 0.2.1
618 " ✅ 应用版本号从 0.2.1 升级到 0.2.2
619 " 🟣 Aquarium 0.2.2 版本 Release 构建和打包成功
620 1:48p 🟣 Aquarium 0.2.2 版本成功安装到 /Applications 目录
621 " 🔵 Aquarium 0.2.2 应用和辅助进程运行状态确认
S313 将 Aquarium 应用状态栏图标从鱼图标改为咖啡杯图标，启用时显示满杯，禁用时显示空杯，并升级版本到 0.2.2 (May 23 at 1:49 PM)
S314 将咖啡杯图标重新设计为蓝色半透明杯身 + 椭圆杯口 + 咖啡液面 + 右侧杯把样式，菜单栏改用彩色图标 (May 23 at 1:49 PM)
622 2:17p 🔵 特权助手已安装并正常运行
623 " 🔵 特权助手安装状态管理机制
624 2:18p 🔵 特权助手运行状态验证
625 " 🔵 AquariumController 助手安装流程
626 " 🔵 Aquarium 特权助手核心策略引擎
627 2:19p 🔵 AquariumConfig 配置结构和持久化机制
628 " 🔵 SettingsView UI 结构和交互逻辑
629 " 🔵 进程匹配和应用过滤实现
630 " 🔵 PrivilegedHelperInstaller 安装机制
631 " 🔵 LaunchAtLogin 功能实现
632 " 🔵 Aquarium 配置和系统状态验证
633 " 🔵 特权助手运行状态详细信息
634 2:20p 🔵 助手二进制文件版本一致性验证
635 " 🔵 助手命令行接口和诊断功能
636 " 🔵 电池解析错误根因分析
637 " 🔵 stdin 关闭测试验证 Process 对象行为
638 " 🔵 日志轮转和错误输出机制
639 2:21p 🔵 IOKit 电池 API 验证成功
640 " 🔴 修复电池解析错误：使用 IOKit API 替代 pmset 命令
641 " ✅ 开始构建修复后的 Aquarium 应用
642 " ✅ 构建成功完成，生成 Universal Binary
643 " ✅ 部署修复后的应用到系统
644 2:22p 🔴 电池解析错误修复验证成功
645 " ✅ 新版本应用和助手运行状态确认
646 " 🔵 策略引擎运行时测试验证成功
647 " 🔵 系统配置和安全策略验证
648 " ✅ Git 工作区状态总结
649 2:23p 🔵 系统睡眠状态确认
650 " ✅ 电池 API 修复代码差异
651 " 🔵 应用过滤功能验证成功
652 " 🔵 最终系统状态验证
653 2:24p ✅ 修复后的 batteryPercent() 函数最终实现

Access 604k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>