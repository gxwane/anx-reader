# 更新日志

**Anx Reader GX Preview** 的所有重要变更均记录于此。

本项目是 [Anx Reader](https://github.com/Anxcye/anx-reader) 的独立维护 Fork。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范。

---

## [0.1.0-preview.1] - 2026-08-25

### 新增
- 建立 GX Preview Fork 独立身份：独立 Android 包名（`io.github.gxwane.anx_reader_gx_preview`）、Windows 产品标识，以及与上游完全隔离的存储与同步命名空间。
- 重新设计设置页顶部品牌 Header：大字 "Anx" 主题色标题 + "GX PREVIEW" 胶囊徽标。
- 欢迎页大标题在所有 16 种支持语言中统一手动换行，改善小屏排版体验。
- 通过 `scripts/generate_gx_icons.py` 放大全密度 Android 启动图标（mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi）及 Windows 应用图标的 GX 折角徽标。
- WebDAV 同步路径隔离（`/anx-reader-gx-preview/`）及备份路径前缀，防止与上游版本数据冲突。
- Golden 像素快照测试套件（设置页、分享卡片、欢迎页），内置 1% 跨平台渲染容差比较器，保证 CI 稳定通过。
- 完整单元测试套件，覆盖 Fork 身份、同步路径隔离、更新通道、备份导入策略、书籍元数据提取等核心逻辑。
- Windows 安装包打包脚本（`scripts/build_windows_installer.ps1` + Inno Setup）。
- GitHub Actions 日常 CI 工作流：每次推送到 `develop` 分支自动执行静态分析与全量测试。
- GitHub Actions Tag 驱动 CD 工作流：推送 `gx-v*` Tag 后自动构建 Android APK 与 Windows 安装包并发布 Release。
- Windows 桌面自动化辅助脚本（`scripts/desktop_automation.py`）。
- 隐私政策与代码签名政策文档。

### 变更
- 禁用上游自动更新检查（`enableAutomaticUpdateCheck = false`）—— GX Preview 管理独立发布通道。
- 关于页面明确标注上游 Anx Reader 项目归属及 Fork 状态说明。
- 所有第三方 API Key 字段（翻译、TTS、同步）默认为空，由用户自行配置。

### 上游同步基准
本版本基于 [Anxcye/anx-reader](https://github.com/Anxcye/anx-reader) 同步，具体上游 Commit 参见发布工作流记录。