# Codex Monitor

一个原生 macOS Codex 辅助工具，通过菜单栏状态胶囊、桌面悬浮球、Quick View、用量和设置等界面，为 Codex 提供轻量、快速、低打扰的桌面辅助体验。

> **当前状态：Developer Preview / 内部开发版本**
>
> Codex Monitor 仍处于持续开发阶段，目前尚未作为正式公共发行版本发布。

---

## 下载

### macOS

[![下载最新版](https://img.shields.io/badge/下载最新版-macOS-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/latest)

[![直接下载 macOS](https://img.shields.io/badge/直接下载-macOS-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/latest/download/Codex-Monitor-macOS.zip)

> 首个 GitHub Release 正式发布前，以上下载入口可能暂不可用。
>
> 后续正式 Release 将提供可直接安装或解压使用的 macOS 版本。

---

## 项目简介

Codex Monitor 是一个面向 macOS 的原生桌面辅助工具。

它的目标是在尽可能减少窗口切换和操作干扰的情况下，让用户快速查看 Codex 相关状态、账户、用量和运行信息。

主要界面包括：

- 菜单栏状态胶囊
- 菜单栏弹窗
- 桌面悬浮球
- 单击 Quick View
- 用量窗口
- 设置窗口

Codex Monitor 采用 Capability-driven（能力驱动）架构。

只有当底层数据源真正具备对应能力时，界面才会展示相关状态，避免把无法可靠确认的数据伪装成实时信息。

---

## 主要功能

### 菜单栏状态胶囊

- 常驻 macOS 菜单栏
- 快速查看当前状态
- 原生 macOS 交互
- 低干扰信息展示

### 菜单栏弹窗

- 快速查看 Codex 相关信息
- 提供用量与设置等功能入口
- 保持轻量、原生的 macOS 使用体验

### 桌面悬浮球

- 可选桌面悬浮显示
- 支持位置与尺寸调整
- 支持原生右键菜单
- 用于快速查看状态与打开 Quick View

### Quick View

- 单击快速打开
- 只读状态速览
- 不承担复杂操作
- 适合随时查看当前信息

### 用量

在对应数据源支持的情况下，可展示：

- Account 信息
- Usage 信息
- Quota
- Reset 信息
- 其他受 Capability 授权的数据

Codex Monitor 不会使用推测数据替代真实数据。

### 设置

- 原生 macOS 设置界面
- 用户偏好持久化
- 悬浮球相关设置
- 显示与交互设置

### 本地数据层

- SQLite 本地存储
- 明确的数据来源记录
- 数据 Provenance
- 避免不同来源信息被错误混合

---

## 技术架构

Codex Monitor 当前主要技术栈：

- Swift 6
- SwiftUI
- AppKit
- SQLite3
- Swift Package Manager

系统不会假设所有 Codex 会话都具备完全相同的实时可观测能力，而是根据数据来源和 Capability 决定允许展示的信息。

当前主要数据来源模型包括：

### Account Layer

负责账户级信息，例如：

- Account
- Plan / Auth
- Usage
- Quota
- Reset

### Monitor-owned Runtime

由 Codex Monitor 自身创建、启动或管理的 Runtime。

该来源可以支持更完整的实时状态能力。

### Codex Desktop Snapshot

普通 Codex Desktop 会话主要作为只读 Snapshot / History 来源。

该来源不会被包装成完整实时 Runtime。

### Future Observer Adapter

为未来可能出现的正式 Observer 能力预留。

当前不会输出模拟、占位或伪造的实时数据。

---

## 系统要求

- macOS 13 或以上
- Swift 6 兼容工具链
- Xcode 或 Xcode Command Line Tools

---

## 获取源码

通过 SSH：

```bash
git clone git@github.com:BlahBlahBlahBB/Codex-Monitor.git
cd Codex-Monitor
```
