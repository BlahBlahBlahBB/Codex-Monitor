# 阻断与升级规则

## 立即停止，不得绕过
- 无法观察 Desktop-created Turn
- 需要读取/保存 Codex credential 才能实现
- 需要 private backend 才能实现核心能力
- approval 只能靠猜
- quota 只能靠 Token 推
- reset 无法保证幂等/权威结果
- migration 可能破坏用户数据

## 可以 Partial Ship
- email 不可用 -> 隐藏
- plan 不可用 -> 隐藏
- cost 不可用 -> `$--`
- secondary quota 不存在 -> 只显示 primary
- multi-account switching 不支持 -> 隐藏/交给 Codex

## Bug 升级
Terra Medium
→ Terra High
→ Sol High root-cause review
→ Terra High implementation
