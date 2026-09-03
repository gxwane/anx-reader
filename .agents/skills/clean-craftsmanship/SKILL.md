---
name: clean-craftsmanship
description: >-
  Applies Uncle Bob's Clean Craftsmanship and Agentic Gauntlet workflow to Anx Reader.
  Use this skill for non-trivial feature implementations, bug fixes, refactoring,
  enforcing Gherkin acceptance criteria (Spec-Driven), strict TDD, architecture boundaries,
  and automated quality gauntlet verification.
---

# Clean Craftsmanship & Agentic Gauntlet Workflow

This skill implements Robert C. Martin's ("Uncle Bob") **Clean Craftsmanship and Automated Quality Gauntlet** for Flutter development in Anx Reader.

Instead of relying solely on manual, line-by-line human inspection of AI-generated code, this workflow wraps development in **deterministic quality gates, behavior specifications, and strict testing discipline**.

---

## The Dual-Loop Craftsmanship Architecture (双环驱动架构)

```
[ Outer Loop: Specifier (Gherkin BDD) & Architect Boundary Guard ]
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│  Inner TDD & Craftsmanship Loop                                  │
│  [Coder: Red] ──> [Coder: Green] ──> [Cleaner: Refactor + Audit] │
│       ▲                                          │               │
│       └────────────── (Refactor Loop) ───────────┘               │
└──────────────────────────────────────────────────────────────────┘
                          │
                          ▼
[ Hardener: Mutation Kill Protocol & Golden Regressions ]
                          │
                          ▼
[ Gauntlet Gate: powershell .\scripts\verify_gauntlet.ps1 ]
```

> **架构关键认知**：Cleaner 是 TDD 内环的 Refactor 步骤（不是事后打扫），Hardener 是外环的 BDD 验收闭合（不是可选附加项）。

---

## The 5 Agent Roles & Mandatory Deliverables

### 1. Specifier Role (规约定义)
* **Goal**: Eliminate prompt ambiguity and define the ground truth before touching code.
* **Actions**:
  - Translate user requirements / bug descriptions into formal **Gherkin Specifications (Given-When-Then)**.
  - Detail edge cases (e.g. empty lists, network timeouts, corrupt EPUB files, orientation changes).
* **Mandatory Deliverable**: 输出完整的 Gherkin Scenarios，覆盖 Happy Path + 至少 2 个 Edge Case。
* Guide: [**`references/specifier_guide.md`**](./references/specifier_guide.md)

### 2. Architect Role (架构守卫)
* **Goal**: Protect Clean Architecture boundaries and dependency inversion.
* **Actions**:
  - Review proposed changes against Anx Reader's structural layers (`lib/models` -> `lib/dao` -> `lib/service` -> `lib/providers` -> `lib/page`).
* **Mandatory Deliverable**: 明确确认无反向依赖、无循环依赖（可一行说明）。
* Guide: [**`references/architect_guide.md`**](./references/architect_guide.md)

### 3. Coder Role (严格 TDD)
* **Goal**: Ensure 100% test coverage of new behavior through the Red-Green-Refactor loop.
* **Actions**:
  - **[RED]**: Write a failing test under `test/` that mirrors the Gherkin scenario.
  - **[GREEN]**: Write minimal production code to pass the test.
* **Mandatory Deliverable**: 可运行的测试文件，`fvm flutter test` 全绿。
* Guide: [**`references/coder_guide.md`**](./references/coder_guide.md)

### 4. Cleaner Role (坏味道与复杂度清理)
* **Goal**: Keep cyclomatic complexity low ($\le 10$), function length short ($\le 30$ lines), and CRAP score ($\le 30$).
* **Actions**:
  - Run `fvm flutter analyze --no-fatal-infos` to catch static issues.
  - Flatten nested conditionals (Guard Clauses) and keep functions short.
* **Mandatory Deliverable**: ✅ **《函数量化审计表》(Function Metrics Audit Matrix)**
  - 必须逐行列出每个被新增/修改函数的：行数、圈复杂度、CRAP 预估、重构动作
  - **仅运行 `flutter analyze` 通过≠完成 Cleaner 阶段**
* Guide: [**`references/cleaner_guide.md`**](./references/cleaner_guide.md)

### 5. Hardener Role (抗压与变异消灭验证)
* **Goal**: Prove test suite assertion strength via Mutation Testing; protect UI via Golden tests.
* **Actions**:
  - Execute Mutation Kill Protocol: inject ≥2 mutants, verify all are KILLED.
  - Execute Golden snapshot regression tests.
  - Run the complete project Gauntlet: `powershell .\scripts\verify_gauntlet.ps1`.
* **Mandatory Deliverable**: ✅ **《变异消灭证据日志》(Mutation Kill Evidence Log)**
  - 必须逐条列出注入的突变体、触发失败的断言、消灭证据（行号/错误消息）
  - **仅测试全绿≠完成 Hardener 阶段**
* Guide: [**`references/hardener_guide.md`**](./references/hardener_guide.md)

---

## Task Tiering & Pragmatic Fast-Track Matrix (任务分级与实用主义豁免矩阵)

To prevent gate inflation and avoid bureaucratic paralysis on minor tasks, development is strictly triaged into three tiers:

| Task Tier | Scope & Triggers | Required Quality Gates |
| :--- | :--- | :--- |
| **Tier A: Architecture & Critical Features** | Cross-module data flows, multi-tier sync topology, database schema changes, Reader core rendering/layout, major features. | **All 10 Gates are mandatory**, including Gate 2 (Independent Solution Audit) and Gate 8 (Independent PR Code Review). |
| **Tier B: Standard Features & Bugfixes** | Regular UI pages, non-global Riverpod state, localized bugfixes without architectural impact. | **Standard TDD + Gauntlet**: Execute Gates 1, 3, 4, 5, 6, 7, 9, 10. **Exempt from independent subagent audits (Gates 2 & 8)**. |
| **Tier C: Chore & Documentation Fast-Track** | Pure documentation, translations (l10n), unit test additions, CI script fixes, comment updates. | **Fast-Track**: Plan Artifact -> User Confirmation -> Execute -> Gauntlet Verification (`verify_gauntlet.ps1`) -> User Delivery. **Exempt from Gherkin, Mutation killing, and Subagent audits**. |

---

## Standard Execution Gates (10 Gates)

When working on a feature or bugfix with this skill, each Gate requires a concrete deliverable before proceeding to the next:

- [ ] **Gate 1 (Specifier & Scenarios)**: Gherkin Scenarios 已输出（Given-When-Then 完整覆盖 Happy Path + 边界用例）。
- [ ] **Gate 2 (Independent Solution Audit)**: 派发独立方案审计 Agent（Principal Solution Auditor）依据《四象限双轴清单》审查架构与 UX，签发通过结论。（**Tier A 强制，Tier B/C 豁免**）
- [ ] **Gate 3 (Architect Boundary Guard)**: 明确确认清洁架构单向依赖合规（`models` -> `dao` -> `service` -> `providers` -> `page`）。
- [ ] **Gate 4 (Coder TDD Red-Green)**: 先写失败测试（Red），再写最小实现（Green），`fvm flutter test` 全绿。
- [ ] **Gate 5 (Cleaner Metrics Matrix)**: ✅ **《函数量化审计表》已在回复中完整输出，圈复杂度 $\le 10$，函数长度 $\le 30$ 行，无 ❌ FAIL 项。**
- [ ] **Gate 6 (Hardener Mutation & Regression)**: ✅ **《变异消灭证据日志》已在回复中完整输出，变异击杀率 100%，Golden 快照无回归。**
- [ ] **Gate 7 (Quality Gauntlet Automation)**: 本地自动化质量军规 `powershell .\scripts\verify_gauntlet.ps1` 4 道门禁 100% 绿灯。
- [ ] **Gate 8 (Independent PR Code Review)**: 派发独立 PR 审计 Agent 走查源码，闭环修复中高危缺陷并取得明确的 **APPROVE ✅** 结论。（**Tier A 强制，Tier B/C 豁免**）
- [ ] **Gate 9 (Architecture & Changelog Sync Invariant)**: 涉及架构/存储拓扑必须同步更新 `AGENTS.md`；面向用户的变更必须同步更新中英双语 `CHANGELOG.md` 与 `assets/CHANGELOG.md`。
- [ ] **Gate 10 (User Visual Confirmation & Delivery)**: 向用户呈报完整交付与测试证据，获得用户明确指令后方可执行 `git commit`。


