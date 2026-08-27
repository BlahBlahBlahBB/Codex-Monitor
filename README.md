# Codex Monitor
### 🟢🟡🔴

一个原生 macOS Codex 辅助工具，通过菜单栏状态胶囊、桌面悬浮球、Quick View、用量和设置等界面，为 Codex 提供轻量、快速、低打扰的桌面辅助体验。

> **当前版本：Codex Monitor 1.0.3 Preview**
>
> Codex Monitor 当前为 Preview，不是 Stable Public Release，也不是 OpenAI 官方产品。部分能力依赖 Codex 的本地接口与本地数据结构，Codex 更新可能暂时影响个别能力；当数据源不可用时，应用会优先显示 Unknown / Unavailable，而不是伪造状态。

<br>

## 📂 Download

### macOS · Apple Silicon

[![下载 Codex Monitor 1.0.3 Preview](https://img.shields.io/badge/下载-1.0.3%20Preview-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.3-preview/Codex-Monitor-1.0.3-RC2-macOS-arm64.dmg)

- [查看 v1.0.3-preview Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.3-preview)
- DMG SHA256：`5b7dc48bda1ee8380c04f937e43a31c9a83d978dd45866b90814686afe4e8e19`

> 当前 Preview 为 **arm64 / Apple Silicon only**，采用 ad-hoc 签名，尚未使用 Developer ID、Apple Notarization 或 Stapling。macOS Gatekeeper 可能阻止或警告该 Preview 包；它目前用于 Preview / testing，而不是无警告的正式公开发行。

<br>

## 📥 安装与升级

### 首次安装

1. 下载 `Codex-Monitor-1.0.3-RC2-macOS-arm64.dmg`
2. 打开 DMG
3. 将 `Codex Monitor.app` 拖入 `/Applications`
4. 从“应用程序”启动 Codex Monitor

### 从旧版本升级

1. 先完全退出正在运行的 Codex Monitor
2. 打开新版 DMG
3. 将新版 `Codex Monitor.app` 拖入 `/Applications`
4. macOS 提示时选择“替换”
5. 再从 `/Applications/Codex Monitor.app` 启动

请避免同时在 `/Applications` 中保留多个正式版 Codex Monitor 副本。多个使用相同 Bundle ID 的副本可能造成 macOS LaunchServices 启动路径或版本识别混淆。

当前 Preview 尚未 Developer ID 签名或 notarize，因此 Gatekeeper 仍可能警告或阻止启动。

<br>

## ✨ 1.0.3 Preview 重点更新

- 在 1.0.2 Golden 产品表现基础上增加 Universal Compatibility Layer，UI、Settings、Usage、Orb 与窗口行为保持不变
- Account / Quota 支持不同 Codex Desktop 本地 transport：优先使用 control socket，不可用时自动回退到受信任的 bundled Codex app-server stdio
- 单次 Account refresh 保持单一 transport provenance，不混合 socket / stdio 数据
- transient 或 incomplete refresh 不再把已有完整 Quota 快照短暂替换为 `-- / 不可用`
- Codex 退出并重新打开后，历史 runtime activity 不再错误恢复为 Thinking / Working
- stale conversation title 无法重新验证时回退到既有 `Current task / 当前任务`，不使用 transcript / prompt / path 正文作为标题
- macOS 通知权限按 `notDetermined / authorized / denied` 系统状态进行一致性处理，不改变原有通知 UX
- Release build 继续锁定已验证的 macOS SDK 26.5、macOS 13.0 minimum deployment target 与可移植 RPATH
- 同一个 1.0.3 RC2 二进制已在三台独立 Mac 上验证通过

自动化回归：**285 tests / 4 expected skips / 0 failures**。

<br>

## 📑 简介

Codex Monitor 是一个面向 macOS 的原生桌面辅助工具。

它的目标是在尽可能减少窗口切换和操作干扰的情况下，让用户快速查看 Codex 相关状态、账户、用量和运行信息。

主要界面包括：

- 菜单栏状态胶囊
- 菜单栏弹窗
- 桌面悬浮球
- 单击 Quick View
- 用量窗口
- 设置窗口

Codex Monitor 采用 Capability-driven（能力驱动）架构。只有当底层数据源真正具备对应能力时，界面才展示相应状态；无法可靠确认的数据会安全降级，而不是被包装成实时或确定信息。

<br>

## 📗 主要功能

### 菜单栏状态胶囊

- 常驻 macOS 菜单栏
- 快速查看当前 Codex 状态
- 原生 macOS 交互
- 低干扰信息展示

### 桌面悬浮球 / Quick View

- 可选桌面悬浮显示
- 支持位置与尺寸调整
- 单击快速打开只读状态速览
- 显示当前会话名称、运行状态与 Session Token（能力可用时）

### Account / Usage / Quota

在对应数据源支持的情况下，可展示：

- Account
- Plan
- Usage
- Quota
- Reset

Codex Monitor 不会用推测值替代未知值；例如 Quota 无法确认时显示不可用，而不是假装为 `0%`。

### 完成通知

任务完成通知采用系统通知层级：

- App 名称
- `已完成 / Completed`
- 当前 Codex 对话名称

通知正文只使用经过安全展示链处理的 conversation name，不回退到 raw prompt、文件路径或内部 transcript。

### 设置

- 原生 macOS 设置界面
- 用户偏好持久化
- 悬浮球相关设置
- 通知与显示设置

<br>

## ⚠️ 系统要求

下载已经封装好的 Preview App 时：

- **macOS 13 或以上**
- **Apple Silicon Mac（arm64）**
- 已安装 **Codex Desktop**
- Codex Desktop 已正常登录

普通 Preview 用户**不需要**：

- Xcode
- Swift 开发工具链
- API Key
- 手动配置 socket 路径
- `chmod`
- 修改 Codex SQLite 数据库
- 修改 `~/.codex` 或 Codex 配置

> Intel / x86_64 当前未支持或验证。

<br>

## ⚠️ Preview 数据源说明

Codex Monitor 1.0.3 Preview 当前会读取本机 Codex 的本地集成数据面。

其中部分 Account 能力使用 Codex app-server 的本地 transport；Desktop runtime / session observation 也依赖 Codex 的本地 SQLite / rollout 等实现细节，这些本地 schema 目前没有稳定 public contract。

因此：

- 1.0.3 定位为 **Preview-only**
- Codex 更新可能暂时影响某个单独 capability
- capability 缺失时应用应安全降级
- 当前不应被描述为 stable production-supported Codex integration

<br>

## 💾 技术架构

主要技术栈：

- Swift 6
- SwiftUI
- AppKit
- SQLite3
- Swift Package Manager

当前设计强调：

- Provenance / source-aware 数据来源
- Capability-driven presentation
- Account / Desktop Local 能力隔离
- Quota 与 Account refresh 的 coherent snapshot / fail-closed 行为
- 不把 Unknown 错误表达为真实 `0%`
- 不让历史 runtime activity 冒充当前 live activity

<br>

## 🧑‍💻 从源码构建

开发 / 源码构建需要 Swift 6 兼容工具链，以及 Xcode 或 Xcode Command Line Tools。

通过 SSH：

```bash
git clone git@github.com:BlahBlahBlahBB/Codex-Monitor.git
cd Codex-Monitor
swift test
```

Preview release packaging：

```bash
VERSION=1.0.3 BUILD=103 ./Tools/package_release.sh
```

在未提供 `SIGNING_IDENTITY` 时，脚本生成明确标记的 ad-hoc local Preview；Developer ID / notarization 流程当前尚未启用。

<br>

## 📌 Release scope

Codex Monitor 1.0.3 Preview 当前验证范围：

- macOS 13+
- Apple Silicon / arm64
- 中文 / English
- 不同 HOME / username，包括空格与 Unicode
- 不同 Codex Desktop 本地 Account transport topology
- 同一 RC2 二进制已在 Computer A、Computer B 与第三台独立 Mac 上完成验证
