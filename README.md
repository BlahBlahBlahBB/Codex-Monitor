# Codex Monitor
### 🟢🟡🔴

一个原生 macOS Codex 辅助工具，通过菜单栏状态胶囊、桌面悬浮球、Quick View、用量和设置等界面，为 Codex 提供轻量、快速、低打扰的桌面辅助体验。

> **当前版本：Codex Monitor 1.0.7 Preview**
>
> Codex Monitor 当前为 Preview，不是 Stable Public Release，也不是 OpenAI 官方产品。部分能力依赖 Codex 的本地接口与本地数据结构，Codex 更新可能暂时影响个别能力；当数据源不可用时，应用会优先显示 Unknown / Unavailable，而不是伪造状态。

<br>

## 📂 Download

### macOS · Apple Silicon

[![下载 Codex Monitor 1.0.7 Preview](https://img.shields.io/badge/下载-1.0.7%20Preview-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.7-preview/Codex-Monitor-1.0.7-RC1-macOS-arm64.dmg)

- [查看 v1.0.7-preview Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.7-preview)
- DMG SHA256：`2666bc4287002fd1517af1a6c1c57b2cf723f8e0206eb8e77ea2f41a5030af83`
- DMG 大小：`3,549,710 bytes`

> 当前 Preview 为 **arm64 / Apple Silicon only**，采用 ad-hoc 签名，尚未使用 Developer ID、Apple Notarization 或 Stapling。macOS Gatekeeper 可能阻止或警告该 Preview 包；它目前用于 Preview / testing，而不是无警告的正式公开发行。

<br>

## 📥 安装与升级

### 首次安装

1. 建议直接从本页 GitHub Release 下载 `Codex-Monitor-1.0.7-RC1-macOS-arm64.dmg`
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

当前 Preview 尚未 Developer ID 签名或 notarize，因此 Gatekeeper 仍可能警告或阻止启动。

<br>

## ✨ 1.0.7 Preview 重点更新

- 修复长 transcript 下 Approval Attention reviewer 识别可能失效的问题：reviewer 查找不再依赖 `turn_context` 距 transcript EOF 的固定尾部窗口
- ApprovalObserver 改为有界内存的反向精确扫描，继续保持 exact `turn_id` 与最新顶层 `turn_context` 匹配；单条 JSONL 记录保留 8 MiB 安全上限，未知或异常输入继续保守返回 `unknown`
- 修复真实 `auto_review` turn 因上下文距离过远被误判为 `unknown`，进而可能触发黄色等待审批状态 / 等待审批通知的问题
- 延续 1.0.6 的真实 **等待审批 / Waiting for approval** 状态、app-managed 审批集成与签名验证的 **ApprovalObserver** helper
- 延续 **等待审批通知** 与 **完成通知**，点击通知可直接激活 Codex；通知仍采用 crash-safe、exactly-once 的持久化处理与重启恢复
- Approval Attention Filter 继续使用 exact-turn reviewer 分类：`user` 保留真实人工审批提醒，`auto_review` 不产生等待审批误报；未知状态继续保守处理
- Settings 保持已清理后的结构：移除实验性审批黄灯 Beta 与 Settings-only“打开 Codex”，将“导出诊断”和“立即刷新”统一保留在 Advanced
- 延续既有 multi-window quota、Account、Usage、runtime-state、task-title 与 diagnostics export 行为

自动化回归：**388 executed / 384 passed / 4 skipped / 0 failures**。

Packaged App、ApprovalObserver strict codesign、DMG verify 与 release smoke：**PASS**。包内 helper 对历史真实长 transcript 的只读回放结果为 `auto_review`。

> 已知 Preview 限制：人工点击 Reject 后，黄色等待状态可能短暂维持，直到 Codex 发出可安全关联的后续 resolution event；这不会导致已拒绝的命令继续执行，也不会重复发送等待审批通知。
>
> 1.0.7 不声称修复 Codex Desktop 0.153.3 自身的原生 Guardian / approval UI 行为，也不声称修复 Codex 进入 Guardian routing 但未保留 `PermissionRequest` Hook dispatch 的上游情况。

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

Codex Monitor 1.0.7 Preview 当前会读取本机 Codex 的本地集成数据面。

其中部分 Account 能力使用 Codex app-server 的本地 transport；Desktop runtime / session observation、approval attention 也依赖 Codex 的本地 SQLite / rollout / Hook 等实现细节，这些本地 schema 与事件目前不应被视为稳定 public contract。

因此：

- 1.0.7 定位为 **Preview-only**
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
VERSION=1.0.7 BUILD=107 RELEASE_LABEL=RC1 ./Tools/package_release.sh
```

在未提供 `SIGNING_IDENTITY` 时，脚本生成明确标记的 ad-hoc local Preview；Developer ID / notarization 流程当前尚未启用。

<br>

## 📌 Release scope

Codex Monitor 1.0.7 Preview 当前验证范围：

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
- Release Gate：388 executed / 384 passed / 4 skipped / 0 failures
