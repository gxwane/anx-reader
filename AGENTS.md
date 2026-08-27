# AGENTS.md

This file provides universal working instructions for code agents in this repository.

---

## 1. Project Summary & Architecture

Anx Reader is a cross-platform Flutter e-book reader with EPUB/MOBI/AZW3/FB2/TXT/PDF support.

### Key Directory Structure:
- `lib/`: Flutter application code.
  - `lib/models/`: Pure domain entities and Freezed data models.
  - `lib/dao/database.dart`: SQLite database schema, helpers, and migrations.
  - `lib/providers/`: Riverpod reactive state management.
  - `lib/service/book_player/`: Local HTTP server and Foliate-js bridge.
  - `lib/page/`, `lib/widgets/`: UI presentation layer.
- `assets/foliate-js/`: JavaScript reader engine used inside the WebView.

---

## 2. Flutter SDK Baseline & Environment Invariants

This checkout uses FVM locally and is pinned to **Flutter 3.35.3**, matching CI configurations.

- Always use `fvm flutter ...` and `fvm dart ...` for project commands.
- Run `fvm flutter pub get --enforce-lockfile` only when dependency resolution is required. The lockfile must not drift unintentionally.
- For local workstation settings (proxy, test devices, node paths, VS 2026 build tools patch), see: [**`AGENTS.local.md`**](AGENTS.local.md).

---

## 3. Core Dev & Quality Verification Commands

From the repository root:

```bash
# Generate localization
fvm flutter gen-l10n

# Generate Riverpod / Freezed / JSON code
fvm dart run build_runner build --delete-conflicting-outputs

# Run the Clean Craftsmanship Automated Quality Gauntlet (analyze + tests + golden UI)
.\scripts\verify_gauntlet.ps1

# Run Golden snapshot UI tests (sub-second layout regression verification)
fvm flutter test test/golden/settings_page_golden_test.dart
```

### foliate-js Rebuild Rule
If you change anything under `assets/foliate-js/src/`, rebuild `assets/foliate-js/dist/`. Commit only `src/*` changes by default.

---

## 4. Clean Craftsmanship & Agentic Gauntlet Workflow

For non-trivial features, refactorings, and architectural fixes, activate the dedicated skill:
- **Skill Path**: [`.agents/skills/clean-craftsmanship/SKILL.md`](.agents/skills/clean-craftsmanship/SKILL.md)
- **The 5 Core Roles**:
  1. **Specifier**: Clarify requirements into Gherkin (Given-When-Then) acceptance scenarios before modifying code.
  2. **Architect**: Enforce single-direction Clean Architecture dependencies (`lib/models` -> `lib/dao` -> `lib/providers` -> `lib/page`).
  3. **Coder (TDD)**: Red (failing test under `test/`) -> Green (minimal implementation) -> Refactor.
  4. **Cleaner**: Run `fvm flutter analyze` and maintain low cyclomatic complexity.
  5. **Hardener**: Execute the project quality gauntlet via `.\scripts\verify_gauntlet.ps1`.

---

## 5. Reader Core Bugfix Protocol

1. Reproduce or inspect the bug and identify the root cause in Flutter or `foliate-js`.
2. For non-trivial fixes, summarize cause + solution before editing.
3. Implement the smallest safe fix that keeps current behavior stable.
4. If JS renderer code changed, rebuild `assets/foliate-js/dist/`.
5. Let the user manually test reader behavior when the issue depends on real books, layout, pagination, or WebView runtime behavior.
6. Before commit, stage only relevant source changes and necessary generated artifacts. Exclude unrelated dependency churn.
7. Never invoke `git commit` for reader core logic (scrolling, navigation, rendering) until the user has performed manual visual testing and explicitly confirmed the behavior.

---

## 6. Known Good Practices From This Repo

- For EPUB renderer issues, prefer fixing the reader instead of mutating user EPUB files.
- For reading-position and pagination bugs, manual verification is often more important than unit coverage alone.
- For layout bugs in the reading UI, favor bounded layouts with graceful truncation over adding complex settings.
- Do not bypass core lifecycle methods (e.g. initialization) to create navigation shortcuts.
- Do not use UI hacks (like CSS hiding or `setTimeout`) to mask visual glitches; trace asynchronous loading state instead.
- **CI/CD Constraints**: GitHub Actions cloud Windows builds must pin `runs-on: windows-2022`. Never add unused Flutter plugins to `dev_dependencies`.
- **Workspace Cleanliness & Temp Logging**: Never redirect temporary debug dumps, crash traces, or diagnostic logs directly into the workspace root. Direct all temporary outputs to `$env:TEMP` (Windows) or system temporary directories, and purge transient artifacts upon completion.

---

## 7. Packaging & CI Runbooks

For platform packaging and autonomous GitHub CI diagnostic procedures, refer to:
- [**`docs/packaging_and_ci.md`**](docs/packaging_and_ci.md) (Android APK/AAB builds, Windows Inno Setup installer, CI automation scripts).
