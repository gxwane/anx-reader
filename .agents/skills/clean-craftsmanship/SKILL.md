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

## The 5 Agent Roles & Execution Pipeline

```
[Specifier] ──> [Architect] ──> [Coder (TDD)] ──> [Cleaner] ──> [Hardener] ──> [Verification Gate]
```

### 1. Specifier Role (规约定义)
* **Goal**: Eliminate prompt ambiguity and define the ground truth before touching code.
* **Actions**:
  - Translate user requirements / bug descriptions into formal **Gherkin Specifications (Given-When-Then)**.
  - Detail edge cases (e.g. empty lists, network timeouts, corrupt EPUB files, orientation changes).
  - Guide: [**`references/specifier_guide.md`**](./references/specifier_guide.md)

### 2. Architect Role (架构守卫)
* **Goal**: Protect Clean Architecture boundaries and dependency inversion.
* **Actions**:
  - Review proposed changes against Anx Reader's structural layers (`lib/models` -> `lib/dao` -> `lib/service` -> `lib/providers` -> `lib/page`).
  - Guide: [**`references/architect_guide.md`**](./references/architect_guide.md)

### 3. Coder Role (严格 TDD)
* **Goal**: Ensure 100% test coverage of new behavior through the Red-Green-Refactor loop.
* **Actions**:
  - **[RED]**: Write a failing test under `test/` that mirrors the Gherkin scenario.
  - **[GREEN]**: Write minimal production code to pass the test.
  - **[REFACTOR]**: Clean up naming and eliminate duplication.
  - Guide: [**`references/coder_guide.md`**](./references/coder_guide.md)

### 4. Cleaner Role (坏味道与复杂度清理)
* **Goal**: Keep cyclomatic complexity low ($\le 10$) and enforce CRAP score threshold ($\le 30$).
* **Actions**:
  - Run `fvm flutter analyze --no-fatal-infos` to catch static issues.
  - Flatten nested conditionals (Guard Clauses) and keep functions short ($\le 30$ lines).
  - Guide: [**`references/cleaner_guide.md`**](./references/cleaner_guide.md)

### 5. Hardener Role (抗压与防退化验证)
* **Goal**: Validate that tests are genuinely robust (Mutation Testing) and protect UI via Golden tests.
* **Actions**:
  - **Mutation Mentality**: Test boundary and logical operator mutations to kill surviving mutants.
  - **Golden Regression**: Execute Golden snapshot tests (`fvm flutter test test/golden/...`).
  - Run the complete project Gauntlet script: `powershell .\scripts\verify_gauntlet.ps1`.
  - Guide: [**`references/hardener_guide.md`**](./references/hardener_guide.md)

---

## Standard Execution Checklist

When working on a feature or bugfix with this skill:

- [ ] **Step 1: Output Gherkin Spec**: See [Specifier Guide](./references/specifier_guide.md).
- [ ] **Step 2: Check Architectural Layer**: See [Architect Guide](./references/architect_guide.md).
- [ ] **Step 3: Red Phase (TDD)**: See [Coder Guide](./references/coder_guide.md).
- [ ] **Step 4: Green Phase**: Implement solution and pass test.
- [ ] **Step 5: Cleaner Refactoring**: See [Cleaner Guide](./references/cleaner_guide.md).
- [ ] **Step 6: Hardener & Gauntlet**: See [Hardener Guide](./references/hardener_guide.md), run `.\scripts\verify_gauntlet.ps1`.
- [ ] **Step 7: User Visual Test**: For UI or reader engine changes, invite the user for runtime verification before final commit.
