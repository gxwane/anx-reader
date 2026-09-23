# AGENTS.md

This file provides universal working instructions for code agents in this repository.

---

## 1. Project Summary & Architecture

Anx Reader is a cross-platform Flutter e-book reader with EPUB/MOBI/AZW3/FB2/TXT/PDF support.

### Key Directory Structure & Domain Invariants:
- `lib/models/`: Pure domain entities and Freezed data models.
- `lib/dao/`: SQLite database schema, helpers, migrations, and table DAOs.
  - **Notes Decoupling Invariant**: Deleting a book from the bookshelf only sets `tb_books.is_deleted = 1` and cleans local physical files. Book notes (`tb_notes`) and reading statistics (`tb_reading_time`) are permanently retained as user knowledge assets.
  - **Folder Dissolution Invariant**: Dissolving a non-root folder uses one DAO transaction to move all directly assigned books (including removed or filtered-out books) and direct child groups to the valid root before deleting the folder. Other book fields, notes, statistics and descendant relationships are retained; any failure rolls back every step. Providers refresh only after commit, and the dialog awaits completion with retryable failure feedback. Restore validation remains strict.
  - **Database v9 Schema Invariant**: `currentDbVersion = 9`. A freshly created database and a clean baseline-v8 upgrade converge to the same schema: reader context fingerprint columns (`context_prefix` / `context_suffix`) on `tb_notes`, a `(book_id, cfi)` unique index on notes and a `(book_id, date)` unique index on reading time. Legacy production databases are converted offline outside the app; the runtime has no old-schema compatibility branch.
  - **Statistics Retention Invariant**: Statistics have no delete UI or DAO hard-delete endpoint; leaving the statistics page never deletes reading records.
  - **Reading Time Identity Invariant**: Reading time is stored as plain seconds per `(book_id, normalized date)` and local writes accumulate inside a transaction. No component encoding, installation identity or open-time history deduplication remains.
  - **Note Identity & Relocation Invariant**: Note saves update/insert atomically by `(book_id, cfi)` and retain existing note IDs. CFI relocation processes one book per batch: otherwise-valid in-place updates succeed, while occupation, swap, duplicate target, contradictory or stale instructions reject the whole batch and leave every original record unchanged; a later SQL failure rolls back earlier updates. No tombstone rows are produced.
  - **Local Restore Invariant**: Settings restore validates a private current-version backup copy before replacing the six business tables in one live SQLite transaction; it never drops the two unique indexes and never imports backup schema, triggers or cloud state. Duplicate identities, noncanonical dates, negative durations, dangling groups or cycles reject the restore with the live database unchanged. Soft-deleted books may retain references to soft-deleted groups (empty-group cleanup only considers live books); live books must reference a live group. Restore requires WebDAV disabled and a full app restart first, does not restore missing assets and does not roll back cloud history.
  - **Backup Discovery Boundary**: `lib/service/local_database_backups.dart` only lists existing local backup files. No whole-database WebDAV download/replacement fallback remains. Restore isolation from sync relies on the documented manual preconditions (WebDAV off, full app exit) and the provider exposes only a non-blocking `state.isSyncing` hint.
- `lib/service/bookshelf/`: Organize persistence depends only on DAOs and plan models; its Provider construction and refresh orchestration live in `lib/providers/bookshelf_organize.dart`.
- `lib/service/sync/`: Baseline upstream WebDAV whole-database snapshot sync (4 files: `sync_client_base`, `sync_client_factory`, `sync_connection_tester`, `webdav_client`) plus `lib/service/database_sync_manager.dart` for safe download, validation and replacement. The custom v1/v2 engine (sidecar progress/notes payloads, record merger, offline queue, Markdown mirror, asset passes, transport runtime and cooldown store) is removed and must not be reintroduced without a new design.
  - **WebDAV Cloud Topology** (within the app namespace):
    ```text
    <WebDAV Root>/
    └── anx-reader-gx-preview/
        ├── database9.db                  # Whole-database snapshot (version-named)
        └── data/
            ├── file/<filename>
            └── cover/<filename>
    ```
  - **Baseline Sync Limitations**: `syncFiles()` prunes local and remote assets not referenced by the current database, and a failed database download may still be followed by the asset stage. These baseline behaviors are retained as-is; they are mitigated by backups and single-device operations, not by new runtime machinery.
- `lib/service/notes/`: Book note export and external note import (Moon+ Reader `.mrexpt`, pending-import scaffolding).
- `lib/service/font/`: Font asset subsystem, OpenType/TrueType/TTC random-access stream parser (<64KB read), PostScript stable ID contract, and JIT lazy Flutter engine loading.
- `lib/providers/`: Riverpod reactive state management.
- `lib/service/book_player/`: Local HTTP server and Foliate-js bridge.
- `lib/page/`, `lib/widgets/`: UI presentation layer.
- `assets/foliate-js/`: JavaScript reader engine used inside the WebView.

---

## 2. Flutter SDK Baseline & Environment Invariants

This checkout uses FVM locally and is pinned to **Flutter 3.35.3**, matching CI configurations.

- Always use `fvm flutter ...` and `fvm dart ...` for project commands.
- Run `fvm flutter pub get --enforce-lockfile` only when dependency resolution is required. The lockfile must not drift unintentionally.
- For local workstation settings (proxy, physical device `FNENW19A18016816`, local `AnxTestDev` emulator, node paths, VS 2026 build tools patch), see: [**`AGENTS.local.md`**](AGENTS.local.md).

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
5. For background lifecycle issues (sleep/screen-off, wakeup, lockscreen audio playback, cross-chapter transitions, TTS service persistence), agents MUST autonomously verify behavior on the local emulator or connected device via ADB before requesting user testing. Let the user manually test reader behavior primarily when the issue depends on subjective typography, tactile page-turn gestures, or physical screen ergonomics (see [**`docs/mobile_autonomous_testing.md`**](docs/mobile_autonomous_testing.md)).
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
- **Runtime Changelog Asset Invariant**: `assets/CHANGELOG.md` is a runtime data asset dynamically parsed by `ChangelogScreen`. Version headers must follow `## [<version>] - <date>` (or `## <version>`). Each version block MUST contain bilingual entries (English first, followed by Chinese). When bumping `version` in `pubspec.yaml`, a new version header matching the new version MUST be prepended to `assets/CHANGELOG.md`. Never merge multiple release cycles under one header, as `extractVersionChangelog` relies on subsequent `## ` headers as its stop delimiter. This invariant is continuously enforced by `test/page/changelog_screen_test.dart` in CI.

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

