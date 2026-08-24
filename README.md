# Codex Monitor
### 🟢🟡🔴

一个原生 macOS Codex 辅助工具，通过菜单栏状态胶囊、桌面悬浮球、Quick View、用量和设置等界面，为 Codex 提供轻量、快速、低打扰的桌面辅助体验。

> **当前版本：Codex Monitor 1.0.1 Preview**
>
> Codex Monitor 当前为 Preview，不是 Stable Public Release，也不是 OpenAI 官方产品。部分能力依赖 Codex 的本地接口与本地数据结构，Codex 更新可能暂时影响个别能力；当数据源不可用时，应用会优先显示 Unknown / Unavailable，而不是伪造状态。

<br>

## 📂 Download

### macOS · Apple Silicon

[![下载 Codex Monitor 1.0.1 Preview](https://img.shields.io/badge/下载-1.0.1%20Preview-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.1-preview/Codex-Monitor-1.0.1-Preview-macOS-arm64.dmg)

- [查看 v1.0.1-preview Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.1-preview)
- [SHA256SUMS.txt](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.1-preview/SHA256SUMS.txt)

> 当前 Preview 为 **arm64 / Apple Silicon only**，采用 ad-hoc 签名，尚未使用 Developer ID、Apple Notarization 或 Stapling。macOS Gatekeeper 可能阻止或警告该 Preview 包；它目前用于 Preview / testing，而不是无警告的正式公开发行。

<br>

## ✨ 1.0.1 Preview 重点更新

- 加强跨用户 / 跨电脑兼容，不依赖开发者用户名或固定 `/Users/...` 路径
- 动态解析当前用户 HOME 与 Codex 本地环境
- 当前会话名称使用 Codex sidebar 对应的 authoritative conversation name
- Account / Quota 刷新增加 single-flight / coalescing
- transient Quota failure 使用一次 500 ms bounded whole-cycle retry，减少 `-- / 不可用` 闪烁
- partial Account snapshot 保持同一 refresh cycle 的数据一致性，避免跨账户混合
- 加强 stop / restart / cancellation 生命周期安全
- Codex Desktop 退出、重新打开后可自动恢复
- Monitor 自身退出 / 重开后自动恢复
- Mac sleep / wake 后自动恢复
- 完成通知显示 App 名称、`已完成 / Completed` 和当前对话名称
- Unknown / Unavailable 与真实 `0%` Quota 明确区分

自动化回归基线：**271 passed / 4 skipped / 0 failed**。

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

Codex Monitor 1.0.1 Preview 当前会读取本机 Codex 的本地集成数据面。

其中部分 Account 能力使用 Codex app-server / WebSocket 接口；该 transport 当前仍属于实验性接口。Desktop runtime / session observation 也依赖 Codex 的本地 SQLite / rollout 等实现细节，这些本地 schema 目前没有稳定 public contract。

因此：

- 1.0.1 定位为 **Preview-only**
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
- Quota 与 Account partial refresh 的 fail-closed 行为
- 不把 Unknown 错误表达为真实 `0%`

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
VERSION=1.0.1 BUILD=101 ./Tools/package_release.sh
```

在未提供 `SIGNING_IDENTITY` 时，脚本生成明确标记的 ad-hoc local Preview；Developer ID / notarization 流程当前尚未启用。

<br>

## 📌 Release scope

Codex Monitor 1.0.1 Preview 当前验证范围：

- macOS 13+
- Apple Silicon / arm64
- 中文 / English
- 不同 HOME / username，包括空格与 Unicode

Computer A 已完成完整 1.0.1 QA。Computer B 尚未完成 1.0.1 physical validation，因此不作已验证声明。
