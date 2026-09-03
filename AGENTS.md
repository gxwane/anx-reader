# AGENTS.md

This file provides universal working instructions for code agents in this repository.

---

## 1. Project Summary & Architecture

Anx Reader is a cross-platform Flutter e-book reader with EPUB/MOBI/AZW3/FB2/TXT/PDF support.

### Key Directory Structure & Domain Invariants:
- `lib/models/`: Pure domain entities and Freezed data models.
- `lib/dao/`: SQLite database schema, helpers, migrations, and table DAOs.
  - **Notes Decoupling Invariant**: Deleting a book from the bookshelf only sets `tb_books.is_deleted = 1` and cleans local physical files. Book notes (`tb_notes`) and reading statistics (`tb_reading_time`) are permanently retained as user knowledge assets.
- `lib/service/sync/`: 4-tier WebDAV synchronization engine, payloads, record merger, and offline resilience queue.
  - **WebDAV Cloud Topology Standard**:
    ```text
    <WebDAV Root>/
    ├── sync/
    │   ├── progress/<file_md5>.json          # Tier 1: Single-book progress micro-sync (~240B, <30ms exit)
    │   ├── notes/<file_md5>.json             # Tier 1: Single-book notes payload with tombstones
    │   ├── latest_progress.json              # Tier 2: Bookshelf global progress index (read-modify-write)
    │   └── markdown_notes/<title - author>.md # Tier 3: PKM Obsidian/Logseq Markdown mirror
    └── <db_name>.db                          # Tier 4: Non-destructive DB snapshot merge
    ```
- `lib/service/notes/`: PKM Markdown formatting, YAML Frontmatter, Dataview tags, and cross-platform filename sanitization.
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
  2. **Architect**: Enforce single-direction Clean Architecture dependencies (`lib/models` -> `lib/dao` -> `lib/service` -> `lib/providers` -> `lib/page`).
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
- [**`docs/packaging_and_ci.md`**](docs/packaging_and_ci.md) (Android APK/AAB builds, Windows Inno Setup installer, CI automation scripts, and Section 4: Preview Release SOP & CI/CD Iron Rules).
- **Mandatory Release Protocol**: Always ensure remote `develop` CI passes 100% green before creating or pushing release tags. Never push branch commits and release tags concurrently.

---

## 8. Documentation, Architecture Sync & Changelog Invariants

Documentation must never drift from code reality. Agents must strictly follow the **Tri-Level Documentation Trigger Matrix**:

| Document Target | Purpose & Scope | Mandatory Update Triggers | Anti-Patterns (Strictly Prohibited) |
| :--- | :--- | :--- | :--- |
| **`AGENTS.md`** | Agent baseline & architecture invariants | 1. Introducing or refactoring core service packages (e.g. `lib/service/sync/`)<br>2. Changing database constraints or table invariants<br>3. Modifying WebDAV cloud file topology or global storage paths<br>4. Updating CI/SDK baselines or Clean Architecture rules | Do NOT add lengthy tutorials, internal private function details, or transient scratch scripts |
| **`docs/`** | Deep technical design & platform SOPs | 1. Cross-subsystem protocols & specs (e.g. Sync redesign, PKM mirror format)<br>2. Packaging and platform release runbooks<br>3. Deep algorithms or data flow specs (>50 lines) | Do NOT store obsolete historical drafts or incomplete notes |
| **`CHANGELOG.md` & `assets/CHANGELOG.md`** | End-user release logs (Bilingual EN/ZH) | 1. User-visible new features (e.g. PKM Markdown auto-mirroring)<br>2. Bug fixes affecting user experience<br>3. User-facing UI or behavioral adjustments | **Never update changelogs for pure internal refactors, test additions, or chore tasks** |

- **Architectural Documentation Sync Invariant**: Any modification to system architecture, cross-module data flow, public storage directory structure (e.g. WebDAV topology), or core lifecycles MUST synchronously update `AGENTS.md` in the same commit.

---

## 9. Dual-Phase Independent Agent Auditing Protocol

To ensure both architectural resilience and superior user experience, non-trivial features and refactoring tasks (Tier A) must pass through a two-phase independent agent auditing loop:

### Phase 1: Plan-Phase Audit (Principal Solution Auditor)
Before writing code, dispatch **one** unified Solution Auditor subagent to evaluate the plan artifact against the **4-Quadrant Dual-Dimension Rubric**:
- **Quadrant A: Distributed Architecture & Consistency**
  - Unique identification: Uses immutable `file_md5` to decouple cross-device auto-increment IDs.
  - Soft deletion & tombstones: Ensures deletions propagate cleanly without reviving on multi-device merge.
  - Concurrency & resilience: Prevents race conditions, debounces batch writes, and handles offline queueing.
  - Clean Architecture: Enforces `models` -> `dao` -> `service` -> `providers` -> `page` single-direction dependencies.
- **Quadrant B: Product UX & User Mental Models**
  - Mental model alignment: Preserves user intuitions (e.g. bookshelf removal does not delete personal reading notes).
  - Non-blocking flow: Ensures background micro-sync does not stall UI exit (<30ms).
  - Destructive safety: Provides confirmation dialogs and explains consequences for irreversible operations.
  - Graceful degradation: Shows non-intrusive status indicators upon network drops rather than modal interrupt dialogs.

### Phase 2: PR-Phase Audit (Principal PR Auditor)
After code implementation and passing the automated quality gauntlet:
1. Dispatch an independent PR Auditor subagent to conduct a rigorous code review of all modified and untracked files.
2. The auditor produces a categorized report (Critical / High / Medium / Low) with an architecture score and checklist.
3. The developer agent must resolve all Medium/High findings and trigger a Round 2 review to achieve an explicit **APPROVE ✅** verdict before presenting the changes to the user for commit confirmation.

