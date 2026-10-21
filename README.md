# Codex Monitor

[![Release](https://img.shields.io/badge/Release-v1.0.13-2563eb?logo=github)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.13)
![Platform](https://img.shields.io/badge/macOS-13%2B%20%7C%20Apple%20Silicon-111827?logo=apple)
![Maturity](https://img.shields.io/badge/Maturity-Preview-f59e0b)

**原生 macOS Codex 状态与额度辅助工具。** 通过菜单栏状态、桌面悬浮球、Quick View、用量与设置界面，快速查看 Codex 信息，尽量减少工作中断。

**快速入口：** [下载 1.0.13](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.13/Codex-Monitor-1.0.13-RC1-macOS-arm64.dmg) · [更新内容](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.13) · [回退至 1.0.12](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.12)

> **当前版本：Codex Monitor 1.0.13 (Build 117)**
>
> Codex Monitor 当前为 Preview，不是 Stable Public Release，也不是 OpenAI 官方产品。部分能力依赖 Codex 的本地接口与本地数据结构，Codex 更新可能暂时影响个别能力；当数据源不可用时，应用会优先显示 Unknown / Unavailable，而不是伪造状态。

<br>

## 📂 Download

### macOS · Apple Silicon

<a href="https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.13/Codex-Monitor-1.0.13-RC1-macOS-arm64.dmg"><img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-1.0.13-black?style=for-the-badge&logo=apple" alt="下载 Codex Monitor 1.0.13"></a>


- [查看 v1.0.13 Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.13)
- [SHA-256 校验文件](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.13/SHA256SUMS-v1.0.13.txt)
- DMG SHA-256：`4542f55247dc484b9f9525eacdf5596c0979a43059a23fbfd90bdbe7b647a54b`
- DMG 大小：`3,667,920 bytes`（约 3.7 MB）
- 发布源码：[`fa0f5bbc7664abfb54127bc0e4887739820aca9c`](https://github.com/BlahBlahBlahBB/Codex-Monitor/commit/fa0f5bbc7664abfb54127bc0e4887739820aca9c)（`v1.0.13` Tag 精确指向该提交；后续 `main` 合并提交不改变发布来源）

下载完成后，可以在终端校验文件：

```bash
shasum -a 256 ~/Downloads/Codex-Monitor-1.0.13-RC1-macOS-arm64.dmg
```

输出的哈希应与上方完全一致。

> 当前 Preview 为 **arm64 / Apple Silicon only**，采用 ad-hoc 签名，尚未使用 Developer ID、Apple Notarization 或 Stapling。macOS Gatekeeper 可能阻止或警告该 Preview 包；它目前用于 Preview / testing，而不是无警告的正式公开发行。

<br>

## 📥 安装与升级

### 首次安装

1. 建议直接从本页 GitHub Release 下载 `Codex-Monitor-1.0.13-RC1-macOS-arm64.dmg`
2. 打开 DMG
3. 将 `Codex Monitor.app` 拖入 `/Applications`
4. 从“应用程序”启动 Codex Monitor

> 建议直接从 GitHub Release 下载，不要通过聊天或协作应用二次转发安装包。部分沙箱化应用可能为转存文件附加更严格的隔离属性，导致 macOS 无法走常规的“仍要打开 / Open Anyway”流程。

### 从旧版本升级

1. 先完全退出正在运行的 Codex Monitor
2. 打开新版 DMG
3. 将新版 `Codex Monitor.app` 拖入 `/Applications`
4. macOS 提示时选择“替换”
5. 再从 `/Applications/Codex Monitor.app` 启动

请避免同时在 `/Applications` 中保留多个正式版 Codex Monitor 副本。多个使用相同 Bundle ID 的副本可能造成 macOS LaunchServices 启动路径或版本识别混淆。

当前 Preview 尚未 Developer ID 签名或 Apple 公证，因此 Gatekeeper 仍可能警告或阻止启动。**如果首次打开受到拦截**，先核对下载来源及 SHA-256；在尝试打开应用后，可前往 **系统设置 → 隐私与安全性 → 仍要打开**（若系统提供此选项）确认。不要为了绕过拦截执行不明来源的终端命令。

当前版本会在启动后延迟检查，并在最多 24 小时一次的自动检查中提示 GitHub 新版本；也可在 **设置 → 关于 → 检查更新** 手动查询。它**不下载、不安装或替换 App**，升级请按以上步骤手动安装。需要回退时，可从 [v1.0.12](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.12) 下载上一版本。

<br>

## ✨ 1.0.13 重点更新

- 新增 GitHub Releases 版本更新检测：启动后延迟检查，后续最多每 24 小时检查一次
- 设置 → 关于新增“检查更新”，并提供中英文无更新与新版本提醒文案
- 新版本提醒仅跳转固定的官方 GitHub Release 页面；不执行自动下载或自动安装
- 版本比较安全忽略旧版、当前版本、draft、prerelease、非法版本和缺失 Build 的推测

自动化回归：**478 executed / 4 skipped / 0 failures**。

RC1 App / DMG 静态验证及实机 QA：**PASS**。GitHub 发布资产的 SHA-256 与原 RC1 一致；未进行真实 24 小时等待测试，也未通过公开的更高版本 Release 验证升级弹窗。

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
- 真实人工审批等待时显示黄色呼吸状态与“等待审批”

### Account / Usage / Quota

在对应数据源支持的情况下，可展示：

- Account
- Plan
- Usage
- Quota
- Reset

Codex Monitor 不会用推测值替代未知值；例如 Quota 无法确认时显示不可用，而不是假装为 `0%`。

### 审批与完成通知

审批与任务完成通知采用系统通知层级：

- App 名称
- `等待审批 / Waiting for approval` 或 `已完成 / Completed`
- 当前 Codex 对话名称

点击等待审批或完成通知会激活 Codex。

等待审批通知只在可确认需要人工处理的审批请求上触发；`auto_review` 不会产生误报等待通知。通知权限不会影响悬浮球本身的黄色审批状态。

通知正文只使用经过安全展示链处理的 conversation name，不回退到 raw prompt、文件路径或内部 transcript。

### 设置

- 原生 macOS 设置界面
- 用户偏好持久化
- 悬浮球相关设置
- 通知与显示设置
- 关于：检查更新 / Check for Updates
- Advanced：立即刷新 / Refresh Now
- Advanced：导出诊断 / Export Diagnostics

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
- 手动修改 `~/.codex` 或 Codex Hook 配置

> Intel / x86_64 当前未支持或验证。

<br>

## ⚠️ Preview 数据源说明

Codex Monitor 1.0.13 当前会读取本机 Codex 的本地集成数据面。

其中部分 Account 能力使用 Codex app-server 的本地 transport；Desktop runtime / session observation、approval attention 也依赖 Codex 的本地 SQLite / rollout / Hook 等实现细节，这些本地 schema 与事件目前不应被视为稳定 public contract。

因此：

- 1.0.13 保持 **Preview-only** 定位
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
- Approval lifecycle 的 exact owner / turn 关联
- 审批 reviewer 的 exact-turn、distance-independent 查找
- 审批通知的 exactly-once 与 restart recovery
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
VERSION=1.0.13 BUILD=117 RELEASE_LABEL=RC1 ./Tools/package_release.sh
```

在未提供 `SIGNING_IDENTITY` 时，脚本生成明确标记的 ad-hoc local Preview；Developer ID / notarization 流程当前尚未启用。

<br>

## 📌 Release scope

Codex Monitor 1.0.13 当前验证范围：

- macOS 13+
- Apple Silicon / arm64
- 中文 / English
- 不同 HOME / username，包括空格与 Unicode
- 不同 Codex Desktop 本地 Account transport topology
- multi-window quota 与既有 Account / Usage / runtime 行为保持不变
- packaged app 与 bundled ApprovalObserver helper 校验：PASS
- reviewer=`user` 的真实人工审批流保持 1.0.6 已验证行为
- reviewer=`auto_review` 的误报抑制流保持 1.0.6 已验证行为
- 历史真实长 transcript reviewer 回放：`auto_review` PASS
- 超长 transcript、跨 chunk、exact/latest turn_context、畸形/截断/超限记录测试：PASS
- 等待审批 / 完成通知与点击激活 Codex：保持既有验证行为
- signed ApprovalObserver helper 与 Hook/config 完整性契约保持不变
- Release Gate：478 executed / 4 skipped / 0 failures
