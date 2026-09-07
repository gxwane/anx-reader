[English](#English)
[简体中文](#简体中文)
[Русский](#русский)

# English
## Unable to Import Books
- Ensure the book format is supported. Please check the supported formats in the [README](../README.md).
- Ensure the book file is not corrupted. You can try using other readers to confirm if the file is normal.
- Ensure the file path does not contain special characters (such as spaces, “/”, etc.).
- Check the device's webview version. If importing books fails, click the bottom right corner of the interface -> Settings -> More Settings -> Advanced -> Logs, scroll down, and in the last few entries, you can see something like `INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null`, where Chrome/128.0.6613.25 is the webview version. If the version number is relatively low, it may cause import failures. You can try upgrading the webview version.

## How to Obtain Log Files
After **reproducing the issue**, click on the bottom right corner of the interface: Settings -> More Settings -> Advanced -> Logs. Click the button in the top right corner to export the log file. Send the log file to the developers to help them better assist you in resolving the issue.

For some issues, you may need to first disable the "Clear logs on startup" option in the "Advanced" interface to export the log file after reproducing the issue.

## WebDAV Sync & Cloud Storage FAQ

### 1. Cloud Directory Structure (Topology)
When WebDAV sync is enabled, Anx Reader organizes your data into the following cloud directory structure (e.g. under `anx-reader-gx-preview/` or `anx-reader/`):

```text
<Sync Root>/
├── data/
│   ├── file/                          # Physical book storage (.epub, .pdf, .mobi, etc.)
│   └── cover/                         # Book cover cache (.png)
├── sync/
│   ├── progress/<file_md5>.json       # Sub-30ms micro-sync: per-book reading progress
│   ├── notes/<file_md5>.json          # Per-book notes with tombstone deletion tracking
│   ├── latest_progress.json           # Global bookshelf recent-reading index
│   └── markdown_notes/                # Obsidian/Logseq PKM Markdown mirror notes
└── database<N>.db (e.g. database10.db) # Tier 4 full snapshot: relational database for styles, groups, stats
```

### 2. Why Are There Multiple `database{N}.db` Files on My WebDAV?
You might notice several files such as `database.db`, `database8.db`, `database9.db`, and `database10.db` on your cloud drive.

- **Database Schema Evolution**: As Anx Reader introduces new features (such as book ratings, customizable highlight colors, bookshelf folders/groups, reading statistics, and reading status), the internal SQLite database structure version increments (`currentDbVersion = 10` in the latest version).
- **Cross-Device Crash Protection (Backward Compatibility)**:
  - If all app versions shared a single `database.db`, an older version of the app on your phone downloading an upgraded database created by a newer app on your PC would crash or fail due to unrecognized columns.
  - Anx Reader strictly partitions databases by schema version (`database<version>.db`). Each app version only interacts with its compatible database.
- **Why doesn't the app delete older databases automatically?**:
  - In a decentralized serverless sync model, the app cannot know if you have other offline or un-upgraded devices that still rely on an earlier database version.

### 3. What Does "Database Version Mismatch" Mean?
If you see the dialog:
> *"Database version mismatch. The remote database (version 10) is newer than what your app supports (version 9). Please update your app to the latest version."*

- **Cause**: One of your devices running a newer release has already upgraded and synced the database to version 10, while the current device is still running an older release.
- **Solution**: Simply update the app on the current device to the latest version. Once updated, it will seamlessly merge with the remote `database10.db`.

### 4. How to Safely Clean Up Legacy Database Files
> [!WARNING]
> **DO NOT DELETE** the `sync/` or `data/` directories! They contain your actual book files, cover images, and incremental reading progress/notes.

If you wish to free up cloud storage or keep your drive tidy:
1. Ensure **all** your devices (phones, tablets, PCs, e-ink readers) have been updated to the latest Anx Reader version.
2. Open the app on any updated device and perform a successful sync.
3. Once completed, older database files with lower version numbers (e.g. `database.db`, `database8.db`, `database9.db`) are inactive legacy snapshots and can be safely deleted. Only keep the latest version (currently `database10.db`) alongside `data/` and `sync/`.

# 简体中文
## 无法导入书籍

- 确保书籍格式支持，请从[README](../README_zh.md)中查看支持的格式。
- 确保书籍文件没有损坏，可以尝试使用其他阅读器确认文件是否正常。
- 确保文件路径没有特殊字符(如空格、”/“ 等)。
- 检查设备 webview 版本，导入书籍失败后，点击界面右下角设置 -> 更多设置 -> 高级 -> 日志，向下滑动，在最后几条中可以看到类似`INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null` ，其中`Chrome/128.0.6613.25` 为 webview 版本，如果版本号较低，可能会导致导入失败，可以尝试升级到最新 webview 版本。

## 如何得到日志文件
在**重现问题后**，点击界面右下角设置 -> 更多设置 -> 高级 -> 日志，点击右上角按钮即可导出日志文件，将日志文件发送给开发者，以便更好地帮助您解决问题。

部分问题可能需要先关闭“高级”界面的“启动时清空日志”选项，以便在重现问题后导出日志文件。

## WebDAV 同步与云端数据管理常见问题

### 1. WebDAV 云端目录拓扑结构说明
开启 WebDAV 同步后，Anx Reader 会在网盘中建立如下规范的目录结构（如 `anx-reader-gx-preview/` 或 `anx-reader/`）：

```text
<同步根目录>/
├── data/
│   ├── file/                          # 书籍物理文件库（.epub / .pdf / .mobi 等）
│   └── cover/                         # 书籍封面缓存库（.png）
├── sync/
│   ├── progress/<file_md5>.json       # 极速微同步：单书阅读进度与百分比 (~240B, <30ms 退出)
│   ├── notes/<file_md5>.json          # 增量笔记同步：高亮、下划线、书签与软删除墓碑
│   ├── latest_progress.json           # 书架全局最近阅读索引
│   └── markdown_notes/                # 双链知识库：自动镜像的 Markdown 笔记 (Obsidian/Logseq)
└── database<N>.db (如 database10.db)   # 全量合并快照：包含书架分组、样式、统计等完整关系库
```

### 2. 为什么网盘根目录存在多个版本的 `database{N}.db`？
很多用户在网盘后台会发现同时存在 `database.db`、`database8.db`、`database9.db`、`database10.db` 等多个文件：

- **数据库结构（Schema）升级**：随着 Anx Reader 的功能演进（如增加评分、笔记多色高亮、书架分组/文件夹、多维阅读统计、阅读状态等），底层 SQLite 数据库结构从版本 1、7、8、9 升级至当前的 **版本 10**。
- **多设备防闪退保护（跨设备向下兼容）**：
  - 如果所有版本共用同一个 `database.db`，当你在电脑上使用新版生成了包含新字段的数据库后，手机端若还是旧版，下载该数据库就会因无法识别新表结构而**直接闪退**或损坏数据。
  - Anx Reader 强制按结构版本号命名（`database<版本号>.db`），各版本客户端只读写其兼容的库文件，彻底保障数据安全。
- **为什么客户端不自动在云端删除旧版本？**：
  - 在无中心服务器的去中心化同步模型中，客户端无法预知用户是否还有其他离线未升级的旧设备需要依赖旧版数据库，因此不会盲目自动清理远端历史文件。

### 3. 遇到“数据库版本不匹配”提示怎么办？
如果同步时弹出：
> *“数据库版本不匹配。远程数据库（版本 10）比您的应用支持的版本（版本 9）更新。请更新您的应用到最新版本。”*

- **原因**：您的某台设备已更新到新版并完成了同步，而当前设备版本较旧。为了防止旧版本破坏新版数据结构，同步被安全拦截。
- **解决方法**：只需将当前设备上的 App 更新到最新版本即可恢复自动双向同步，无需手动操作任何数据。

### 4. 如何安全清理 WebDAV 历史无用文件？
> [!WARNING]
> **绝对不要删除** `sync/` 与 `data/` 目录！这些目录存放了您的真实图书物理文件、封面图片以及跨设备增量进度与笔记。

如果您希望释放网盘空间或保持目录整洁，请按以下安全 SOP 操作：
1. 确认您当前正在使用的**所有设备**（手机、电脑、平板、电纸书等）均已升级至最新版本；
2. 在任意一台设备上打开 App，执行一次成功的 WebDAV 同步；
3. 此时，编号较小的历史文件（如 `database.db`、`database8.db`、`database9.db`）已完全退役为闲置冷备快照，您可以直接在网盘中放心删除它们。只需保留当前最新版本的数据库文件（如 `database10.db`）以及 `data/`、`sync/` 目录即可。

# Русский
## Не удаётся импортировать книги
- Убедитесь, что формат книги поддерживается. Пожалуйста, проверьте поддерживаемые форматы в [README](../README.md).
- Проверьте, что файл книги не повреждён. Вы можете попробовать открыть его в других приложениях для чтения, чтобы убедиться, что файл в порядке.
- Убедитесь, что путь к файлу не содержит специальных символов (например, пробелов, «/» и т.д.).
- Проверьте версию WebView на устройстве. Если импорт книг не удаётся, нажмите в правом нижнем углу интерфейса: Настройки -> Дополнительные настройки -> Расширенные -> Логи, пролистайте вниз и в последних записях вы увидите что-то вроде `INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null`, где Chrome/128.0.6613.25 — это версия WebView. Если номер версии низкий, это может вызывать сбои при импорте. Попробуйте обновить WebView до последней версии.

## Как получить файлы логов
После **повторения проблемы** нажмите в правом нижнем углу интерфейса: Настройки -> Дополнительные настройки -> Расширенные -> Логи. В правом верхнем углу нажмите кнопку экспорта файла лога. Отправьте этот файл разработчикам, чтобы им было легче помочь вам решить проблему.

Для некоторых проблем может потребоваться сначала отключить опцию "Очистка логов при запуске" в разделе "Расширенные", чтобы после повторения проблемы можно было экспортировать файл логов.
