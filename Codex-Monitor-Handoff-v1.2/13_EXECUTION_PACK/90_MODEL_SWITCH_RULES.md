# 模型切换规则

## 默认
- Sol: High
- Terra: Medium
- Luna: Medium

## Terra 升 High
满足任一：
- protocol ambiguity
- concurrency
- AppKit lifecycle
- migration
- reset credit
- 两次合理修复失败

## 升 Sol
满足任一：
- Terra High 两次仍失败
- 要改 Frozen
- P0 证据冲突
- 安全/隐私
- cross-module architecture change
- Release gate

## Luna 只做
- fixtures
- tests
- localization
- repetitive refactor
- docs
-明确边界的小任务

## 关键操作
每切一次模型：
1. 当前 Phase 出报告
2. 停止
3. 新建 Task
4. 手动选模型
5. 读 Master + 当前 Phase + 上一 Report
6. 只做当前 Phase
