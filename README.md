# Codex Monitor
### 🟢🟡🔴

一个原生 macOS Codex 辅助工具，通过菜单栏状态胶囊、桌面悬浮球、Quick View、用量和设置等界面，为 Codex 提供轻量、快速、低打扰的桌面辅助体验。

> **当前版本：Codex Monitor 1.0.8 Preview**
>
> Codex Monitor 当前为 Preview，不是 Stable Public Release，也不是 OpenAI 官方产品。部分能力依赖 Codex 的本地接口与本地数据结构，Codex 更新可能暂时影响个别能力；当数据源不可用时，应用会优先显示 Unknown / Unavailable，而不是伪造状态。

<br>

## 📂 Download

### macOS · Apple Silicon

[![下载 Codex Monitor 1.0.8 Preview](https://img.shields.io/badge/下载-1.0.8%20Preview-black?style=for-the-badge&logo=apple)](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/download/v1.0.8-preview/Codex-Monitor-1.0.8-Preview-macOS-arm64.dmg)

- [查看 v1.0.8-preview Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.8-preview)
- DMG SHA256：`d175254e39796faba2c200783887512ff975be27ee72633957c48892a7b89475`
- DMG 大小：`3,577,235 bytes`

> 当前 Preview 为 **arm64 / Apple Silicon only**，采用 ad-hoc 签名，尚未使用 Developer ID、Apple Notarization 或 Stapling。macOS Gatekeeper 可能阻止或警告该 Preview 包；它目前用于 Preview / testing，而不是无警告的正式公开发行。

<br>

## 📥 安装与升级

### 首次安装

1. 建议直接从本页 GitHub Release 下载 `Codex-Monitor-1.0.8-Preview-macOS-arm64.dmg`
2. 打开 DMG
3. 将 `Codex Monitor.app` 拖入 `/Applications`
4. 从“应用程序”启动 Codex Monitor
5. 如果你在安装/首次启用审批监听之前已经打开了 Codex 对话，请新建一个 Codex 对话后再使用审批监控；无需重启 Codex

> 建议直接从 GitHub Release 下载，不要通过聊天或协作应用二次转发安装包。部分沙箱化应用可能为转存文件附加更严格的隔离属性，导致 macOS 无法走常规的“仍要打开 / Open Anyway”流程。

### 从旧版本升级

1. 先完全退出正在运行的 Codex Monitor
2. 打开新版 DMG
3. 将新版 `Codex Monitor.app` 拖入 `/Applications`
4. macOS 提示时选择“替换”
5. 再从 `/Applications/Codex Monitor.app` 启动
6. 如果升级前已有打开中的 Codex 对话，需要新建一个对话才能加载新的审批 Hook；无需重启 Codex

请避免同时在 `/Applications` 中保留多个正式版 Codex Monitor 副本。多个使用相同 Bundle ID 的副本可能造成 macOS LaunchServices 启动路径或版本识别混淆。

当前 Preview 尚未 Developer ID 签名或 notarize，因此 Gatekeeper 仍可能警告或阻止启动。

<br>

## ✨ 1.0.8 Preview 重点更新

- 新增可选的系统默认**提示音**开关；关闭时通知保持静音，开启时使用 macOS 系统默认通知音
- 审批生命周期观察与“等待审批通知”开关彻底解耦：即使关闭审批通知，Monitor 仍继续消费审批事件并维护黄色 Orb 状态
- 提升 Approval journal 在 Observer 安装 / 迁移期间的可靠性：即使 Hook 迁移暂时失败，只要兼容 journal 仍在写入，reader 也会保持 active
- 修复启动时状态合并问题：已完成的后台任务不再错误覆盖仍在运行的当前用户任务，避免任务进行中提前出现绿色 Orb 和“已完成”通知
- 改进真实人工审批生命周期：
  - `reviewer=user` 的 pending approval 会进入黄色 Orb
  - 用户点击“允许一次 / 拒绝”后，黄色状态会立即恢复到正常任务状态
  - 任务真正完成后才进入绿色完成状态并发送“已完成”通知
- 保持通知点击激活 Codex 的既有行为；审批与完成通知继续采用原生 `UNUserNotificationCenter`
- 延续 multi-window quota、Account、Usage、runtime-state、task-title 与 diagnostics export 等既有能力

自动化回归：**410 executed / 0 failures / 4 expected skips**。

Premature Completion 真实 Human QA：**PASS**。Approval lifecycle / 黄色 Orb 恢复真实 Human QA：**PASS**。

Packaged App、ApprovalObserver helper strict codesign 与 DMG read-only mount：**PASS**。

> 已知 Preview 限制：Approval Hook 在 Codex thread / session 创建时加载。Codex Monitor 首次安装/启用审批监听之前已经存在的旧对话，后续人工审批可能不会发出可供 Monitor 消费的 Hook event。**新建一个 Codex 对话即可启用审批监控，无需重启 Codex。**

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
- 当前任务真正完成后显示绿色完成状态，不再由无关后台 task 的 terminal 状态提前覆盖

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

等待审批通知只在可确认需要人工处理的审批请求上触发；由 Codex“帮我审批”自动处理、没有进入真实 `reviewer=user` 人工等待状态的请求不会产生黄色审批提醒。通知权限或“等待审批通知”开关不会影响悬浮球本身的黄色审批状态。

Advanced 中可选择开启系统默认**提示音**。提示音关闭时通知静音；开启时使用 macOS 系统默认通知音，不内置自定义音频。

通知正文只使用经过安全展示链处理的 conversation name，不回退到 raw prompt、文件路径或内部 transcript。

### 设置

- 原生 macOS 设置界面
- 用户偏好持久化
- 悬浮球相关设置
- 通知与显示设置
- Advanced：提示音 / Sound
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

Codex Monitor 1.0.8 Preview 当前会读取本机 Codex 的本地集成数据面。

其中部分 Account 能力使用 Codex app-server 的本地 transport；Desktop runtime / session observation、approval attention 也依赖 Codex 的本地 SQLite / rollout / Hook 等实现细节，这些本地 schema 与事件目前不应被视为稳定 public contract。

因此：

- 1.0.8 定位为 **Preview-only**
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
- Approval journal reader 与 notification preference 解耦
- 审批通知的 exactly-once 与 restart recovery
- Quota 与 Account refresh 的 coherent snapshot / fail-closed 行为
- 不把 Unknown 错误表达为真实 `0%`
- 不让历史 runtime activity 或无关 background terminal 冒充当前 live task completion

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
VERSION=1.0.8 BUILD=108 RELEASE_LABEL=Preview ./Tools/package_release.sh
```

在未提供 `SIGNING_IDENTITY` 时，脚本生成明确标记的 ad-hoc local Preview；Developer ID / notarization 流程当前尚未启用。

<br>

## 📌 Release scope

Codex Monitor 1.0.8 Preview 当前验证范围：

- macOS 13+
- Apple Silicon / arm64
- 中文 / English
- 不同 HOME / username，包括空格与 Unicode
- 不同 Codex Desktop 本地 Account transport topology
- multi-window quota 与既有 Account / Usage / runtime 行为保持不变
- packaged app 与 bundled ApprovalObserver helper 校验：PASS
- `reviewer=user` 的真实人工审批：黄色 Orb / 等待审批 / resolution recovery Human QA PASS
- “等待审批通知”关闭时审批观察继续运行，黄色 Orb 生命周期不依赖通知开关
- “帮我审批”自动处理且未进入真实人工等待状态的请求不会产生黄色审批误报
- 任务运行中重启 / 启动 Monitor：不会被无关后台 terminal 提前投影为 COMPLETED，Human QA PASS
- 真正 task completion 后绿色 Orb 与完成通知顺序正确，Human QA PASS
- 安装/启用 Observer 前已经存在的旧 Codex thread 可能没有 Hook event；新建对话即可恢复，无需重启 Codex
- 等待审批 / 完成通知与点击激活 Codex：保持既有验证行为
- signed ApprovalObserver helper 与 Hook/config 完整性契约保持不变
- Release Gate：410 executed / 0 failures / 4 expected skips
