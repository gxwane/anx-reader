# Architect Guide: Anx Reader 架构分层与依赖红线指南

本指南为 **Architect（架构守卫角色）** 的核心操作手册，用于确保代码改动严格遵守 **Clean Architecture（整洁架构）** 的单向依赖原则。

---

## 1. 分层架构与依赖方向 (The Dependency Rule)

```
[ Presentation Layer: lib/page/, lib/widgets/ ]  (UI 表现层)
                      │
                      ▼
[ State & Providers: lib/providers/ ]            (状态管理层)
                      │
                      ▼
[ Services & Engine Bridge: lib/service/ ]       (领域服务与引擎桥接层)
                      │
                      ▼
[ Persistence & Data: lib/dao/database.dart ]    (持久化数据层)
                      │
                      ▼
[ Pure Models & Entities: lib/models/ ]          (纯领域模型与实体)
```

> **架构黄金定律**：内层模块**绝对不得感知或依赖**外层模块。源码依赖流向必须由外向内单向流动。

---

## 2. 逐层依赖红线与禁忌 (Boundary Constraints)

### 1. `lib/models/`（核心实体与 Freezed 数据模型）
- **允许**：标准 Dart 库、JSON 序列化注解、Freezed 注解。
- **严禁**：
  - `import 'package:flutter/material.dart'`（模型层不得包含任何 UI 组件）。
  - 严禁 import `lib/page/`、`lib/providers/` 或 `lib/dao/`。

### 2. `lib/dao/`（SQLite 数据操作与迁移）
- **允许**：`sqflite`、SQLite 辅助工具、`lib/models/`。
- **严禁**：
  - 严禁包含任何 `BuildContext` 或 Flutter Widget 引用。
  - 严禁直接调用 UI 弹窗或交互逻辑。

### 3. `lib/service/book_player/`（阅读引擎与本地服务）
- **允许**：Local HTTP Server、Shelf、Foliate-js 资源分发、JS 通信通道。
- **严禁**：
  - 强耦合特定 UI Widget 实现。
  - 绕过阅读器核心生命周期方法（如初始化或资源释放）。

### 4. `lib/providers/`（Riverpod 响应式状态）
- **允许**：`flutter_riverpod`、`lib/models/`、`lib/dao/`、`lib/service/`。
- **规范**：
  - 复杂业务逻辑属于 Provider，而不是 Widget 的 `build()` 或 `onTap` 方法。

### 5. `lib/page/` & `lib/widgets/`（UI 表现层）
- **允许**：Flutter Framework、消费 Riverpod Provider（`ref.watch` / `ref.read`）。
- **严禁**：
  - 在 Widget 中直接手写原始 SQL 查询。
  - 在 Riverpod 体系外随意存储不受控的全局可变状态。

---

## 3. 架构合规审查清单 (Architect Checklist)

- [ ] 是否新增了反向依赖（例如底层 Model import 了上层 UI）？
- [ ] 是否存在循环依赖（Circular Dependencies）？
- [ ] 跨模块调用是否通过接口/Provider 抽象解耦？
