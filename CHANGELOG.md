# 更新日志

**Anx Reader GX Preview** 的所有重要变更均记录于此。

本项目是 [Anx Reader](https://github.com/Anxcye/anx-reader) 的独立维护 Fork。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范。

---

## [0.1.0-preview.8] - 2026-09-19

- Fix(bookshelf): Dissolve folders atomically, including removed and filtered-out books and child-group references, so normal bookshelf operations keep local backups restorable; retain notes and reading statistics and allow retry on failure.
- Fix(bookshelf): 解散文件夹改为原子事务，同时处理已移除、被筛选隐藏的书籍及子分组引用，避免正常书架操作导致本地备份无法恢复；保留笔记与阅读统计，失败时可重试。

### 新增
- **听书视口解耦与单一变形 FAB（Decoupled Reader Viewport & Morphing FAB during TTS Listening）**：彻底重构听书时手动翻页的交互体验。当用户在听书朗读期间翻阅前后页面或浏览跨章节内容时，视口不再因音频播放下一句而被强行暴力拉回（Snap-Back）；右下角原有悬浮按钮智能变形为 `[🎯 回到朗读处]`（英文 `Return to Voice`）药丸胶囊，点击一键精准平滑翻页回到当前正在发音的句子并绘制高亮；内核深度落实 **1B 后台无头静默连播** 与 **1C 上下文情境重合自愈**：用户浏览其他章节时，音频通过内存无头文档静默连读下一章，永不断播、绝不误判读完猝死；当用户手动浏览的章节与音频跨章自然切入的章节重合时，视口自愈吸附并恢复跟随；严密筑牢阅读进度防线，杜绝自由浏览期间切后台导致听书进度被意外覆盖。

### 变更
- **WebDAV 同步能力整体回退（WebDAV Sync Rollback）**：自研 WebDAV 同步（v1 边车微同步与 v2 不可变对象引擎）因非收敛缺陷整体回退，应用恢复为上游原版整库快照同步行为；preview.6/7 期间的云端微同步、分组 UUID 映射、Markdown 笔记镜像与冲突副本保护能力一并移除。旧云端同步元数据（`sync/`、`latest_progress.json`、`markdown_notes/` 等）需人工移出同步命名空间归档。
- **数据库结构收敛至 v9**：保留阅读器上下文指纹（`context_prefix` / `context_suffix`）与 v8 阅读状态字段，新增 `(book_id, cfi)` 笔记唯一索引与 `(book_id, date)` 阅读时长唯一索引；不再提供旧库兼容打开，生产旧库须经应用外一次性工具离线转换后接入。
- **应用内本地事务恢复**：恢复入口改为在单个 SQLite 写事务内替换六张业务表，校验目标 v9 版本与业务记录；重复身份、非法日期、负时长、分组环或悬空引用一律拒绝且原库不变。执行前须关闭 WebDAV 并完全退出应用，恢复期间不得阅读或触发同步。

### 修复
- **听书硬件级 DSP 实时变速与断句早停健壮性加固（Real-Time Hardware DSP Playback Rate & Sentence Robustness）**：
  - **硬件级 DSP 实时无感变速**：基于 Ping-Pong 双播放器实现底层播放速率瞬时切换，调速时不再丢弃已缓冲音频或重发网络请求，彻底消除调速导致的音频缓冲丢弃、网络洪峰、短句吞噬与 8 秒饥饿看门狗崩溃；
  - **彻底杜绝误报 EOF 假阳性早停**：在切句前进判定中建立连续跳过插画页、封面及空白段落的异步重试机制，并严格守卫缓冲队列，彻底修复听书跨章节时因短暂空白误报「End of book reached」猝死早停的顽疾；并在分句引擎中加入中英文分号智能断句，防范长难句导致的本地模型合成超时。
- **统计删除入口移除**：移除统计页删除与 DAO 硬删除端点，退出统计页、移除书籍均不再删除阅读统计或笔记。
- **笔记与阅读时长身份约束**：保存笔记按 `(book_id, cfi)` 原子更新并保留原笔记 ID；阅读时长按规范日期以普通秒数在事务内累加。
- **设置项导航箭头一致性**：同步与导出/导入等直接执行项、模态对话框项不再显示误导性的子页面箭头。

## [0.1.0-preview.7] - 2026-09-07

### 新增
- **阿里云百炼 Qwen3-TTS 语音大模型接入（Alibaba Cloud DashScope Qwen3-TTS Integration）**：全面接入阿里云百炼（DashScope）新一代 Qwen3-TTS（通义千问语音大模型）语音合成服务，为个人与开发者提供每月 **1,000,000 字符** 永久免费额度，只需配置 API Key 即可零门槛畅享高质量、自然拟真的情感语音（Upstream Issue #980）。内置 20 款官方精选优质声线（涵盖芊悦、苏瑶、晨煦、千雪、茉兔、月白、四月、凯、田叔、萌宝、徐大爷、小婉、沧明子、燕铮莺、十三妹、阿闻以及沪/京/陕/闽台方言特色音色）；请求载荷全面启用 MP3 压缩编码，相比未压缩 WAV 大幅节省 80% 网络带宽与首字延迟；支持 `language_type: Auto` 自适应多语种书籍朗读；针对云端缺乏数值语速参数的限制，创新实现语速倍速指令动态注入机制，并在两阶段合成（任务生成 + 音频直链下载）全链路部署 25 秒网络韧性防护；与设置页音色列表无缝联动，打造开箱即用的高品质中文听书新标杆。
- **TTS 听书对话智能断句优化与承接引语自然合并（Smart Dialogue Sentence Splitting & Lookahead Attribution Merger）**：彻底修复听书模式机械按句号、感叹号、问号切分句子，导致类似 `“我去！”他震惊地喊道。` 或 `“真的吗？”老人疑惑地问。` 被强行切分为两段单独语音发音，造成短句发音生硬突兀、语调脱节、长久停顿的重大听书体验缺陷（Upstream Issue #970）。在底层 Foliate-js 阅读引擎（`assets/foliate-js/src/tts.js`）的分句生成器中引入轻量级前瞻智能合并（Smart Lookahead Merger）算法，支持跨多级 DOM 节点探查；当闭引号（含中英文单双引号 `”`、`’`、`"`、`'` 以及日文/繁体角引号 `」`、`』`）前出现终止标点时，智能识别后文紧邻的言语动作引语标签（如 `他喊道`、`老人问`、`他说`、`微笑着说`、`she cried` 等）并将其自然合并为一个连贯完整的发音与高亮 Range 单元；同时对连续多角色对话（如 `“好。”“走。”`）及非引语长段叙事保持精准避让独立分句，无需用户进行繁琐的规则配置，全自动实现沉浸自然的开箱即用听书体验。
- **全平台系统级书籍文件关联直接打开与现代临时预览模式（Cross-Platform File Association & Modern Ephemeral Preview Mode）**：
  - **全平台系统级双击/分享关联打开（System-Wide File Association）**：在 Windows（Inno Setup 注册表 ProgID 与单实例 `WM_COPYDATA`）、macOS（`CFBundleDocumentTypes` 与 `AppDelegate.openFiles`）、iOS（Document Types 与 UTI）以及 Android（Intent 统一通道）深度集成系统文件关联与原生通道，支持双击直接打开 `.epub`, `.mobi`, `.azw3`, `.azw`, `.fb2`, `.txt`, `.pdf` 书籍文件；
  - **书架已有书籍毫秒级秒开（Instant Bookshelf Matching Fast-Path）**：通过流式计算文件 MD5（`calculateFileMd5Stream` 杜绝大文件 OOM），若文件已存在于书架中，则直接唤醒并以已有书籍身份极速秒开（<50ms），不弹窗、不重复复制；
  - **现代临时预览模式（Modern Ephemeral Preview Mode）**：若文件未在书架中，以临时预览身份（`isExternalPreview`）立即打开，不污染书架列表，不向云端 WebDAV 发起无效微同步或产生历史孤儿记录，严守用户外部物理文件绝不删除（Delete-Free）安全底线；
  - **阅读器一键入库转正（In-Reader Add to Bookshelf）**：顶部常驻「加入书架」操作按钮与沉浸式横幅提示，点击即可原子化克隆文件至本地书库、写入数据库元数据并将临时笔记平滑迁移合并；
  - **退出安全闭环与临时笔记清理（Safe Exit & Temporary Notes Cleanup）**：退出未入库的临时预览书籍时，提供友好确认弹窗（「加入书架并退出」 vs 「直接退出」），直接退出时自动清理临时笔记与格式转换缓存，保证存储空间与书架环境纯净无污染 (#975)。
- **墨水屏全局禁用动效与极致防频闪模式（E-ink Anti-Flicker & Zero-Animation Mode）**：
  - **全平台零延迟瞬时路由切换（Zero-Animation Route Transitions）**：构建 `NoAnimationPageTransitionsBuilder` 并注入全局 Material 主题引擎，在开启 E-ink 模式后彻底消除全平台页面进入与退出的平移、缩放与渐隐动效，首帧瞬时渲染，杜绝残影；
  - **根级 Hero 封面跨屏飞行拦截（Root Hero Flight Interception）**：在应用根节点部署 `HeroMode(enabled: !eInkMode)` 并动态解绑 `HeroineController`，书籍打开及卡片交互不再产生跨屏移动重绘；
  - **开书 600ms 渐隐动画自动短路（Instant Book Open Bypass）**：`openBookAnimation` 在墨水屏模式下自动求值为 `false`，彻底跳过渐隐封面与定时器，点击即可瞬时加载正文；
  - **SmartDialog 浮层动效全面抑制（SmartDialog Motion Suppression）**：动态配置 SmartDialog 的 `custom`、`attach`、`toast` 与 `loading` 四类全局浮层为 `useAnimation: false`，消除淡入与滑动闪烁；
  - **高对比度静态加载指示器（Static Anti-Strobe Loading Indicator）**：重构 `showLoading()`，在墨水屏模式下以高对比度静态沙漏图标与加粗加载文本取代 60FPS 持续旋转的 `CircularProgressIndicator`，根除高频局刷抖动与电池消耗；
  - **翻页与外观设置无缝协同（Settings & Navigation Harmony）**：在外观设置中为 E-INK 模式提供清晰说明，联动锁定开书动画开关状态，并在排版菜单中对滑动翻页提供友好禁用保护，默认锁定无动画翻页 (#986)。
- **AI 提示词模板填入输入框微调后再发送（AI Prompt Template Fill & Fine-Tuning）**：
  - **点击填入微调（Tap to Fill & Focus）**：点击预设的 AI 快捷提示词芯片（上下文提示词、空状态引导词、章节总结、全书总结、思维导图与自定义 Prompt）时，由原先的“立即直接发送”优化为自动填充至输入框、光标定位至文本末尾并自动获取焦点，供用户追加具体指令或微调内容后再发送；
  - **上下文前缀智能互斥替换（Intelligent Prefix Replacement）**：在上下文前缀词（解释、看法、总结、分析、建议）之间切换时，自动识别并替换已有前缀词，杜绝“请分析 请解释 xxx”等多重前缀重复堆叠；输入框为空时自动附带尾随空格方便输入；
  - **长按直接发送快车道与触感反馈（Long-Press Direct Send Shortcut）**：为保留高频用户的快捷直发效率，移动端长按提示词芯片直接触发即时发送，并附带轻度震动反馈（HapticFeedback）；
  - **桌面端悬浮提示与全局设置开关（Desktop Tooltip & Configurable Settings）**：桌面端鼠标悬浮展示操作指引 Tooltip（与移动端触控完全解耦，消除手势冲突）；在「AI 提示词设置」中提供「立即发送提示词模板」全局开关，支持一键切换习惯偏好 (#969)。
- **书架多选批量管理与手动标记阅读状态（Bookshelf Multi-Selection Batch Management & Manual Reading Status）**：
  - **多选批量管理模式（Batch Selection Mode）**：书架顶部支持一键进入批量管理模式，支持单选/全选/反选与实时选中计数，提供顶部常驻取消按钮与 Android 返回键/Escape 原生手势退出；
  - **批量动作操作栏（Batch Action Bar）**：提供底部悬浮管理工具栏，涵盖批量修改阅读状态（未读/在读/已读/弃读）、批量移动分组/新建文件夹/移出分组、批量释放本地存储空间（保留云端与笔记）、以及批量安全软删除（严格遵循笔记解耦契约，清理物理文件同时永久保留用户阅读笔记与统计资产）；
  - **书籍封面与文件夹多态徽章（Checkmark Badges & Folder Selection）**：支持单书封面高亮角标与文件夹局部/全选三态指示（全选显示勾选、部分选中显示减号），点击文件夹支持批量整组切换；
  - **阅读状态手动标记与多处协同（Reading Status Alignment）**：在书籍详情页、长按菜单、桌面右键菜单及底部批量管理中无缝协同手动标记阅读状态，书架列表即时响应过滤与排序 (#841)。

### 修复
- **自定义存储位置迁移失败与已有旧书库重定向修复（Custom Storage Migration Robustness & Existing Library Mount）**：修复 Windows 下更改存储目录时易报"迁移失败，数据仍在原位置"的问题，以及选择存储目录时因存在任何文件就被硬性拦截"请选择空文件夹"的交互缺陷。迁移逻辑现支持幂等恢复（跳过目标端已有同大小文件），防止因文件重名冲突抛出异常；目录选择新增三路分支判断：选择空目录时正常迁移数据，选择含有合法 Anx 书库结构（`databases/` 或 `file/`）的目录时弹出确认弹窗直接挂载而无需复制数据，其他非空目录继续提示选择空目录（#745, #839）。
- **TTS 听书后台与锁屏跨章节自动连读卡死修复（TTS Background & Lockscreen Cross-Chapter Transition Fix）**：彻底修复在系统朗读（System TTS）与在线朗读（Online TTS / Edge TTS）过程中，手机灭屏锁屏或应用切至后台时，音频播放至当前章节末尾后永久卡死停止、直到用户点亮屏幕唤醒应用后才突发跳入下一章继续播放的重大体验缺陷（Upstream Issue #544）。深入分析 WebKit 与 Chromium 内核底层机制，定位到系统灭屏（`document.hidden === true`）时浏览器内核为了省电挂起垂直同步（VSYNC）并暂停所有 `requestAnimationFrame` 驱动帧，导致底层 Foliate-js 翻页滚动动画 Promise 永久无法 resolve 并反向死锁挂起 Flutter 端 `callAsyncJavaScript`；重构 `assets/foliate-js/src/paginator.js`，在页面隐藏状态下直接跳过逐帧动画实施 `<1ms` 瞬时重定位，配备物理时间看门狗与 `visibilitychange` 状态变化自愈监听；在 `book.js` 中重构 `nextSection` / `prevSection` 调度体系，支持单文件虚拟章节跨章节定位，消除书籍末尾处的互递归死锁；在 `OnlineTts` 与 `SystemTts` 中建立确定性的章节结束与全书末尾优雅停播机制；在章节切换时通过 `AudioService` 动态刷新锁屏通知栏上的媒体章节标题与元数据；并在底层 `view.js` 与 Flutter 生命周期中引入 `visibilitychange` 视口瞬时自愈对齐（Self-Healing）与 rAF 防抖排版就绪机制，彻底消除手机熄屏听书播放多页后亮屏时视口停留在陈旧页面的延迟脱节盲区，实现开屏即对齐当前发音句子与高亮。
- **Windows 窗口最小化/最大化桌面图标无法点击与鼠标穿透遮挡修复（Windows Window State Desktop Mouse Hit-Test & Ghost Layer Fix）**：彻底修复 Windows 端在阅读器打开状态下将窗口最小化或最大化后，桌面图标无法点击、鼠标点击被隐藏的阅读器 WebView 幽灵图层无形拦截的重大体验缺陷（Upstream Issue #981 及关联重复反馈 #243, #255, #830, #850）。分析并定位 Microsoft Edge WebView2 在窗口最小化时 DirectComposition 输入层驻留桌面截获鼠标事件的核心机制，构建 `ActiveWebViewRegistry` 统一调度活动 WebView 生命周期，在窗口最小化与后台隐藏时立即触发 `pause()` 调用底层 `put_IsVisible(false)` 释放输入层并在恢复时即时 `resume()`；同时在 Win32 Runner 原生层实现双重防御——在 `WM_SIZE (SIZE_MINIMIZED)` 时主动调用 `ShowWindow(SW_HIDE)` 隐藏原生渲染子窗口，修复 `WM_ACTIVATE` 在窗口失焦时错误向子窗口 `SetFocus` 导致的焦点争夺，并在 `FlutterWindow` 中确保被插件拦截的窗口尺寸与激活消息仍能可靠通知到 Runner 基础生命周期，全链路保障桌面交互纯净无阻。
- **Gemini AI 工具调用 400 ApiException 思考签名缺失修复（Gemini AI Tool Calling Missing thought_signature Fix）**：彻底修复使用 Gemini 2.0 / 2.5 / 3.0 等具备思考推理能力（Thinking Models）的模型进行 AI 助手多轮工具调用时抛出 `ApiException(400): Function call is missing a thought_signature in functionCall parts` 的缺陷。实现专用 HTTP 客户端拦截器 `GeminiThoughtSignatureClient`，自动监听并提取服务端返回的 `thoughtSignature` / `thought_signature`（支持 JSON 与 SSE 流式事件），并在后续携带 `functionCall` 与 `functionResponse` 的多轮会话回传请求中自动对齐回填，或在极端缺失时自动注入 Google 官方标准跳过标记 `skip_thought_signature_validator`，对底层第三方 SDK 保持零侵入与高内聚，彻底恢复 Gemini 工具调用的全链路稳定性 (#977)。
- **正文划词选区与上下文菜单焦点自动恢复及硬件翻页键穿透平移修复（Reader Text Selection Focus Recovery & Hardware Turn-Page Pan Fix）**：彻底修复在正文选中文本、划线或弹出操作菜单后，因原生 WebView 抢占焦点导致 Flutter 端硬件翻页键（Windows 方向键/空格/PageDown 及移动端音量键）失效、并向底层 WebView 穿透导致页面出现横向左右异常平移的缺陷。将阅读页焦点请求公开为 `requestReaderFocus()`，并在 `EpubPlayerState` 建立 `restoreReaderFocus()` 响应链路；在上下文菜单关闭（`onClose`）、选区取消回调（`onSelectionCleared`）、挂起锁释放以及点击空白处关闭浮层时全链路可靠回收焦点，确保阅读器硬件翻页状态机始终保持跟手响应。

## [0.1.0-preview.6] - 2026-09-05

### 修复
- **书籍目录树与朗读设置折叠箭头及交互体验优化（TOC & Settings Chevron Direction UX Alignment & Visual Rhythm）**：全面修复正文目录树（`book_toc.dart`）与朗读设置中章节/分类在折叠状态下错误展示向下箭头（`Icons.expand_more` / `keyboard_arrow_down`）的心智模型反模式，统一定制校正为折叠时向右箭头 `chevron_right` (`>`)，展开时向下箭头 `keyboard_arrow_down` (`v`)，并自适应 RTL（从右至左）文字方向；彻底移除当前无子目录章节下方误用向右箭头 `>`（`keyboard_arrow_right_rounded`）展示章节内页码导致的“伪子节点”认知错觉与 40dp 到 60dp 的行高跳变，统一采用规整平整的标准单行排版，当前阅读章节依托主题色高亮与粗体清晰呈现。
- **通用网络拓扑智能诊断分析器与无偏见自动展开（Universal Network Topology Diagnostics & Unbiased Auto-Expansion）**：
  - **人话级智能拓扑诊断（Dynamic Diagnostic Analyzer）**：彻底根除在自建/本地语音服务异常时向用户甩出 `Exception: 502` 或 `Connection refused (10061)` 等晦涩报错的技术壁垒；构建纯 Dart 解耦的 `TtsDiagnosticAnalyzer` 领域分析器，动态规整用户输入的 URL（含无协议前缀容错与精确端口提取），严密识别本地回环（`127.0.0.0/8`, `::1`）、RFC 1918 局域网私网与公网域名；针对 502 网关拦截、连接被拒、401 鉴权缺失、404 端点未实现及超时等场景提供包含真实端口与主机名的结构化排查指引（智能提示 Clash 本地代理旁路、防火墙放行等），同时提供可折叠技术日志与一键复制功能；
  - **无语言偏见智能展开与探测状态感知（Unbiased Auto-Expansion & Transparent Discovery）**：对所有语种实施平权自动展开（单分类时无条件展开，当前生效模型所在分类自动展开），并记录用户主动折叠意图；在自建语音探测失败时于列表顶部展示友好提示横幅与一键重试/排查按钮，彻底消除以往静默回退默认预设导致用户误以为不支持模型获取的认知断层。
- **Microsoft Edge 微软自然语音与本地自建/OpenAI兼容 TTS 开放生态（Edge-TTS & Local Self-Hosted TTS Ecosystem）**：
  - **Microsoft Edge 自然语音（Edge-TTS）**：提供完全免 Key、零配置门槛的微软高质量多语种神经网络语音服务（涵盖晓晓、云希、云健、台湾晓臻、香港晓曼及美日英法德等核心音色）；算法深度对齐 Windows File Time（1601纪元、300秒对齐窗口、100ns高精度时钟戳）与 `TrustedClientToken` 动态 SHA-256 签名（`Sec-MS-GEC`），通过单连接 WebSocket 流式拉取 24kHz/48kbps 高清 MP3 音频帧并精准剥离二进制私有包头，全面支持 XML 实体转义与自适应语速语调微调；
  - **本地自建 / OpenAI 兼容语音（Self-Hosted Local TTS）**：深度兼容遵循 OpenAI `/v1/audio/speech` 规范的本地或局域网 AI 语音模型（包括 CosyVoice、GPT-SoVITS、ChatTTS、Piper、Ollama 等）；支持局域网免鉴权模式（留空 API Key 时严格省略 `Authorization` 请求头，杜绝内网 401 报错），支持 `/v1/audio/voices`、`/v1/voices`、`/v1/models` 多层级动态音色发现，将单句合成超时放宽至 30 秒以从容应对本地 GPU/CPU 模型的长推理与冷启动耗时，并配备响应体二进制非音频错误拦截保护。
- **TTS 流式朗读 Ping-Pong 乒乓双播放器与视听解耦（Gapless Ping-Pong Audio Pipeline & Visual Decoupling）**：彻底消除在线与自建 TTS 朗读断句时的 300ms~500ms 停顿感。构建双 `AudioPlayer` 乒乓轮换架构，在第 N 句播放的同时后台预热解码第 N+1 句音频，并在播放结束瞬间以 <5ms 极速切换 resume；将 WebView DOM 划线高亮完全解耦为异步观察者，不再同步阻塞音频主时钟；引入单调递增会话 Epoch 纪元令牌，防范快速切章或停止时的竞态与音频残留。
- **字体子系统现代化重构与综合字体管理中心（Font Subsystem Modernization & Font Hub）**：
  - **综合字体管理中心（Font Hub）**：打造“我的字体 / 系统字体库 / 在线字体库”三合一综合字体中心，支持即时搜索预览、一键切换当前阅读字体、当前使用字体高亮徽章，以及自定义字体的安全删除确认对话框；在设置外观与阅读设置中建立直达入口；
  - **在线字体库容灾韧性与开放多源生态（Online Font Store Resilience & Open Multi-Source Ecosystem）**：
    - **三级容灾降级流水线（Failover Pipeline）**：官方源主站异常或超时时自动静默回退至官方备用镜像；遭遇全面断网时自动降级展示本地分源隔离缓存（`.cache/fonts_manifest_${source.id}.json`），并展示非阻断式离线通知横幅，绝不弹出侵入式错误弹窗；
    - **自定义字体源扩展与前置探活（Custom Font Sources & Pre-flight Validation）**：支持用户添加自建或第三方开源字体仓库源，基于 RFC 3986 标准实现动态 URI 相对/绝对解析，全面兼容任意自建 CDN 与分布式托管；配备前置网络探活与 JSON Schema 安全校验，拒绝非法或破损数据源；
    - **多源切换与生命周期自愈（Source Switcher UX & Auto-healing Fallback）**：在线商店常驻顶部源选择器与管理弹窗，官方源受保护不可删除；当删除当前生效的自定义源时，触发自愈兜底机制自动回退至官方商店，并在异常状态下提供快速切回官方商店的逃生通道；
  - **在线字体库架构加固与体验闭环（Online Font Store Modernization & Atomic Pipeline）**：引入 `<fontDir>/downloaded/<font.id>/` 存储命名空间隔离，彻底消灭多个开源字体同名文件相互静默覆写的重大隐患；引入临时目录暂存与跨分区安全提交流程，多文件总字节平滑累加进度，异常自动原子回滚；新增在线字体实时模糊搜索与 KeepAlive 页面驻留，卡片显式标注文件大小（MB/KB），下载完成后支持一键「应用字体」即时生效，修复预览图单色染色滤镜与暂停文案，并提供 Manifest 10s 超时与离线本地缓存降级；
  - **跨平台系统字体发现与收藏机制（System Font Pinning & Favorites）**：支持即时发现 Windows/macOS/Linux 本地已安装系统字体，引入星标收藏机制，避免成百上千款系统字体涌入阅读弹窗造成视觉干扰；
  - **双轨渲染管线与代码块排版保护（Direct CSS Pipeline & Monospace Guard）**：系统字体直接通过原生 CSS 声明生效，消除无谓的 Dart 堆内存字体装载与本地 HTTP 中转；在本地 HTTP 字体服务中引入严格的 `path.isWithin` 目录防遍历安全隔离；在阅读渲染引擎中强化代码块等宽字体保护规则（`<pre>`, `<code>`, `<kbd>`, `<samp>` 等及其高亮子节点），杜绝语法高亮污染；
  - **零拷贝轻量流式解析器（OpenType Stream Parser）**：以随机读取模式解析 OpenType/TrueType/TTC 元数据（单次读取 < 64KB），彻底替代以往将整个几十兆字体全量加载至内存的同步 I/O，并建立不可变的 PostScript 稳定标识体系与 JIT 延迟加载。
- **划线笔记跨格式坐标归一化与上下文指纹自愈重定位（W3C Context Fingerprint & Fuzzy Relocation）**：
  - 划线时自动提取符合 W3C Web Annotation 规范的上下文指纹（前后各 32 字符），随笔记存入 SQLite 数据库（升级至 v10，具备幂等无损迁移）；
  - 当电子书重排版、排版引擎微调或版本更新导致传统 CFI 坐标失效时，基于多候选扫描与非对称相似度评分模型（Dice-Sørensen Bigram，阈值 $\ge 0.7$）毫秒级自动重定位正确文本区间；
  - 纠偏新坐标时通过单次 IPC 批量回写，并在同一 SQLite 事务中为旧坐标原子生成 WebDAV 墓碑标记（`is_deleted = 1`），彻底杜绝跨设备微同步时的僵尸笔记死灰复燃。
- **个人知识库联动（PKM: Obsidian / Logseq 笔记 Markdown 自动镜像导出）**：
  - 支持在 WebDAV 同步设置中一键开启 Markdown 笔记自动镜像，在划线、写批注或退出阅读时，自动将笔记生成带标准 YAML Frontmatter 的 Markdown 格式并保存至 WebDAV 独立目录 `sync/markdown_notes/<书名> - <作者>.md`；
  - 深度兼容 Obsidian、Logseq、Notion 与 Dataview 元数据规范，包含书名、作者、封面 MD5、阅读状态、笔记总数与 `tags: [anx-reader, book-notes]`；
  - 配备工业级跨平台文件名安全转义器（自动清洗 Windows 保留名与非法字符），并提供一键全量镜像历史笔记与带进度指示器的节流上传。
- **WebDAV 解耦多粒度无损同步引擎完整重构**：
  - **网络流量削减与单请求极速微同步（Single-Request Dirty-Checked Micro-Sync）**：废除 WebDAV 上传前冗余的 `DELETE` 请求，严格遵循 RFC 4918 由 HTTP `PUT` 就地原子覆盖（削减 50% 写入网络往返）；在 `BookNoteDao` 引入轻量脏检查，仅当笔记真正修改时才上传笔记；全局索引 `latest_progress.json` 移入后台防抖批处理工作队列，实现 95% 日常阅读退出场景**仅需 1 次极速 HTTP PUT 请求（~240 字节，耗时 < 30ms）**，彻底消除连接重置与并发冲突；
  - **单书毫秒级微同步（Sidecar Sync）**：退出阅读页时秒级异步上传 ~300 字节轻量进度 JSON (`sync/progress/<md5>.json`) 与单书笔记集合，耗时 < 50ms，彻底将高频进度与庞大的 SQLite 数据库解耦，多设备阅读不同书籍在物理层天然零冲突；
  - **书架全局聚合进度索引与秒级下拉刷新（Bookshelf Progress Index & Pull-to-Refresh）**：在 WebDAV 上增量维护轻量全局索引 (`sync/latest_progress.json`)；在书架下拉刷新或应用唤醒时，仅需 1 次 GET 请求（~2KB，耗时 < 300ms）即可完成全书架图书阅读进度的毫秒级静默对齐，并在 SQLite 事务中严格保留远端时间戳以彻底防范回流循环；
  - **离线阅读与弱网自愈重试队列（Offline Sync Queue & Resilience）**：引入轻量持久化待同步队列与线程安全写锁，当在飞行模式、地铁等离线或弱网环境下单书微同步失败时自动入队；网络恢复（5 秒防抖）、应用前台唤醒或触发全量同步时自动后台无感知补发，具备已删书籍优雅跳过、鉴权错误熔断与互斥锁保护，保障离线进度 100% 不丢；
  - **跨设备记录级无损智能合并（Record-level Non-Destructive Merge）**：彻底终结整库 Last-Write-Wins 覆盖缺陷。以全局不可变 `file_md5` 为主键动态映射本地自增 `book_id`，多端离线新增的图书、阅读进度、划线笔记在联网时自动双向合流取并集，阅读时长取最大值，杜绝数据相互踩踏覆盖；
  - **笔记软删除与墓碑机制（Tombstone Support）**：数据库升级至 v9（在 `tb_notes` 引入 `is_deleted` 字段与幂等迁移），删除笔记时写入墓碑标记并按更新时间戳合并，彻底解决跨端同步导致的已删除笔记死灰复燃 Bug；
  - **彻底废除阻塞式模态选择弹窗**：全量同步 100% 后台静默安全运行；在阅读界面中检测到云端进度更新时，采用类似 Kindle 的非阻塞轻量底部微提示（`"检测到在 [设备名] 读至第 X 章 (XX%)  [跳转]  [忽略]"`），绝不阻断用户正常阅读。
- **解耦笔记与书架物理文件，持久保留与展示历史笔记资产**：彻底消除从书架移除电子书（释放存储空间）后笔记在“笔记页”被意外隐身的问题。将用户的划线批注作为独立的第一等知识资产持久保留与平权展示，保持笔记列表纯净无多余标签；对本地物理文件已移除的笔记在尝试跳转原文时进行安全拦截与精准提示，杜绝文件缺失崩溃。
- **支持一键批量删除单书全部笔记**：在笔记主列表卡片支持左滑快捷删除，并在书籍笔记详情页顶部操作区提供清空全部笔记入口；配备防误触二次确认弹窗、WebDAV 墓碑同步以及桌面端分屏状态自愈机制。

### 优化
- **全局滚动体验现代化与跨平台自适应滚动条（Universal Scrollbar Modernization & Platform Adaptive Scrolling）**：
  - **平台自适应滚动物理（Platform-Adaptive Scroll Physics）**：废除硬编码的 `BouncingScrollPhysics`，引入全局 `AppScrollBehavior`，在 Windows 与 Linux 上采用符合桌面操作习惯的夹紧滚动 `ClampingScrollPhysics`，在 macOS、iOS 与 Android 上保持原生回弹滚动 `BouncingScrollPhysics`，支持全套鼠标、触屏与手写笔输入；
  - **沉浸式自适应滚动条样式（Unified Scrollbar Styling & Contrast Guard）**：全局统一 `ScrollbarThemeData`，实现悬停/拖动时 6dp 增宽至 8dp 交互动效，拖动时高亮主题色，针对墨水屏（E-ink）环境部署纯黑高对比度与纯白轨道防抖保护；
  - **防重复注入与未挂载控制器崩溃守护（AppScrollbar Safe Container）**：统一封装 `AppScrollbar` 组件，通过 `copyWith(scrollbars: false)` 彻底根除外层自定义滚动条与桌面底层系统滚动条并存导致的“双重重叠滚动条”瑕疵；针对骨架屏与异步加载视图智能感知 `hasClients` 状态，彻底杜绝未挂载控制器时的断言闪退；
  - **章节目录 Scrubbing 滚动条（Continuous TocScrollbar）**：专门针对 `ScrollablePositionedList` 构建双端视口归一化数学模型，实现精确的亚像素连续滑动映射，彻底消除滑块滑动到 80% 即到顶到底的数学天花板断层；引入 `_isDragging` 互斥锁杜绝指针拖动与视口监听器相互争抢导致的橡皮筋抖动，并配备 Material 3 拖动实时章节指示气泡；
  - **核心页面全面覆盖与控制器生命周期闭环**：对正文目录（`BookToc`）、笔记列表（`NotesPage`）、设置主页（`SettingsPage`）、朗读设置（`NarrateSettings`）及字体中心三大标签页（`FontsSettingPage`）全面装配现代滚动条，补全内部 `ScrollController` 释放生命周期，彻底杜绝内存泄漏。
- **更新日志解析系统与多端响应式现代布局重构（Changelog System & Responsive UI Modernization）**：
  - 核心解析引擎重构：引入三级自适应版本匹配机制（完整预发布版本号 $\rightarrow$ 基准 SemVer $\rightarrow$ 最新第一段标头自愈兜底），彻底消除非对齐版本下的警告日志与占位符；废除对半切分历史技术债，改用中文字符集 Unicode 智能分类器，消除多语言混杂泄露与截断风险；补齐资源文件版本标头并使双语条目严格镜像对齐；
  - 桌面端全屏体验与排版重构：彻底修复桌面端全屏状态下因松散约束与 shrink-wrap 导致的滚动条悬浮在屏幕中央（约 53% 处）以及底栏确认按钮被横向粗暴拉伸至 1920px 宽的严重视觉排版缺陷；
  - 响应式双端卡片架构：引入 Material 3 居中响应式卡片架构（`maxWidth: 820`），配置高亮版本胶囊徽章、应用徽标与版本升级迁移路径展示；规范管理 `ScrollController` 生命周期杜绝监听泄露，滚动条严格依附卡片边缘，桌面端采用紧凑操作按钮，移动端保持全宽触控，全屏阅读体验与视觉质感显著提升。
- **弹窗动效与多端自适应呈现架构重构（Changelog & Onboarding Adaptive Presentation）**：彻底清除在桌面端硬编码调用 iOS 专属 `showCupertinoSheet` 的历史遗留问题，根除由此导致的桌面主窗口背景被整体缩小下移（`0.94x`）、顶部露出纯黑底色死角（`#000000`）以及关闭时弹簧震颤的严重视觉缺陷；封装统一的 `ChangelogScreen.show` 呈现引擎，桌面端自适应呈现为 Material 3 居中模态对话框（背景 100% 保持静止、柔和半透明暗色遮罩，配备右上角 X、支持 ESC 键、遮罩点击或底栏退出），移动端平滑过渡为原生全屏页面；完成退出途径与版本号持久化闭环，同步净化引导页 `OnboardingScreen` 呈现逻辑。
- **设置界面交互规范与心智模型对齐（Settings Navigation Chevron UX Alignment）**：全面审查并规范清理设置各模块（同步、高级、AI、外观）中非子页面跳转项误带的右侧导航箭头（`>`），将直接触发执行项（导出数据、导入数据、立即同步、清空缓存、重算 MD5、重新显示提示等）以及模态对话框项（主题颜色、界面语言、提示词编辑等）由 `SettingsTile.navigation` 规范收敛为 `SettingsTile`，消除误导性子层级暗示，严格遵循 HIG 与 Material Design 导航指引。
- **字体子系统架构重构第二阶段（Font Subsystem Modernization - Phase 2）**：
  - 接入跨平台操作系统字体发现引擎（`SystemFontService`），在 Windows 下通过零依赖注册表双键（`HKLM` + `HKCU`）扫描系统字体名，并提供跨平台优质字体名册降级；
  - 引入用户常用系统字体收藏/置顶机制（Pinning UX），搭配实时搜索与预览弹窗，彻底杜绝海量系统字体冲垮日常阅读下拉菜单；
  - 重构 Foliate WebView 双渲染管线，系统字体直接应用 CSS 原生规则（零网络请求、零内存拷贝），并严格保护代码块（`<pre><code>`）及其子高亮节点的等宽字体排版与缩进；
  - 彻底解耦阅读菜单 [`style_widget.dart`](file:///E:/Documents/anx-reader/lib/widgets/reading_page/style_widget.dart)，废除同步阻塞扫盘与伪实体技术债，全面接入 Riverpod 响应式状态流。
- **字体子系统架构重构第一阶段（Font Subsystem Modernization - Phase 1）**：
  - 引入 `OpenTypeStreamParser` 4KB 头部随机寻址流式解析器，单字体元数据解析 I/O 消耗从 50MB 骤降至 <64KB，彻底消除主线程同步读盘卡顿，并扩展支持 `.ttc` 字体集合与 `.woff2` 格式；
  - 建立确定性不可变唯一标识体系（基于 PostScript Name 与 SHA-256），根除目录变动引起的字体排版漂移，向下无损兼容存量用户的偏好配置；
  - 废除启动时向 Flutter 引擎全量载入所有字体的内存浪费行为，改为摘录分享卡片按需 JIT 懒加载，大幅降低应用启动耗时与内存驻留；
  - 完善运行时动态服务端口解析与内置默认字体的安全删除防护。

## [0.1.0-preview.5] - 2026-09-02

### 新增
- **工业级 OpenCC 简繁转换引擎重构**：彻底废除旧的 2270 字符单字暴力线性替换，引入 OpenCC 分词字典与 Trie 前缀树匹配引擎，精准解决「頭髮/發展」、「皇后/前後」、「吃麵/表面」、「乾燥/幹活」等一简多繁歧义错字；转换性能提升至毫秒级（$O(1)$ 查找，消灭长章翻页卡顿）；扩展支持通用繁体、台湾正体与香港繁体，动态更新 `html.lang` 激活原生地域异体字形渲染；划线笔记与目录全面实现简繁等价归一化保护。

### 优化
- **AI 对话分屏历史原地平滑切换**：彻底移除阅读分屏模式下历史抽屉向左横穿遮挡书籍正文的动画，采用原地淡入淡出（Fade Transition）与边界裁剪，并优化 AppBar 图标语义与 Tooltip 规范。
- **长思考过程智能手势滚动锁**：引入手势通知感知机制，在用户向上滑动浏览思考过程或历史内容时即刻挂起自动向下跟随，杜绝长文本流式输出时的屏幕抢占与跳闪；滑回底部即时恢复跟随。
- **思考面板自适应高度约束**：动态约束思考面板最大高度并赋予独立滚动控制器生命周期，避免大模型长篇推理挤压主消息视口。
- **确定性全量消息列表与 120 FPS 满帧滑动**：主消息列表全面切换为确定性布局，彻底消灭动态懒加载导致的滚动条滑块忽长忽短与剧烈跳动问题，滚动全程零排版开销、滑块长度绝对恒定。
- **输入框连续输入焦点保持**：发送消息后主动保持输入框焦点，支持桌面端与移动端流畅连续追问。
- **历史加载后首次发消息零闪烁**：StreamBuilder 接入初始数据平滑过渡，彻底解决从历史列表加载会话后第 1 次发送消息时历史记录冲刷空白闪烁的问题。
- **打字机呼吸光标与完成态视觉界限**：输出过程中展示独立呼吸光标并严格隐藏复制与重新生成按钮，生成完毕瞬间光标隐去、操作栏平滑就位，消除状态模糊与误操作。
- **快捷提问 Chip 自然左对齐**：调整快捷提问排版，与输入框文本光标及模型选择器形成统一垂直左对齐基线。

### 工程与规范
- **Clean Craftsmanship 双环驱动与硬性证据门禁升级**：将技能架构升级为内外双环模型（内环 TDD 编码与坏味道清理、外环 BDD 验收与变异消灭），引入强制《函数量化审计表》（行数、圈复杂度、CRAP 分数）与《变异消灭证据日志》，杜绝 Agent 流程形式化与步骤跳过。

## [0.1.0-preview.4] - 2026-09-01

### 修复
- 数据库迁移幂等性加固（SQLite 启动防崩溃）：引入 `addColumnIfNotExists` 防御性列迁移机制，在字段已提前存在或迁移中断重入时自动跳过，杜绝 SQLite `duplicate column name` 导致的启动异常退出。

## [0.1.0-preview.3] - 2026-08-31

### 新增
- 核心阅读状态生命周期管理：新增「未读、在读、已读完、弃读」全生命周期状态，解耦阅读状态与物理阅读进度，升级 SQLite 数据库至 v8 并实现存量数据平滑智能回填。
- 书架多态状态筛选：书架顶部支持「正在读 / 未读 / 已读完 / 弃读」全状态 Chip 切换，支持与标签、关键字组合筛选。
- 移动端 1-Tap 状态切换：升格重构书架长按底部栏（`BookBottomSheet`），顶部直接展示状态胶囊组，单手 1 步秒切并配备触觉振动反馈（Haptics）。
- 桌面端鼠标原地右键菜单：在 Windows/macOS/Linux 上右键点击图书，直接在光标坐标就地呼出原生上下文菜单，彻底消除宽屏菲茨定律操作割裂。
- 书架卡片多态视觉指示系统：已读完图书展示打勾徽标（`✓`），弃读图书应用柔和去饱和置灰滤镜，书架卡片底部信息行严格约束避免极端尺寸下的溢出报错。
- 书籍详情页时序状态选择器：自适应等宽 4 列胶囊选择器，按标准时序（未读 → 在读 → 已读完 → 弃读）排列，支持展示累计已读遍数与起止时间。
- 阅读器智能状态感知：未读书籍在阅读器中产生有效阅读自动无感流转为在读。
- 全套 Clean Craftsmanship 规约、TDD 单元测试与变异测试（Mutation Testing）保障。

## [0.1.0-preview.2] - 2026-08-27

### 新增
- 应用内版本无缝升级：支持在应用内直接流式下载安装包，实时展示下载百分比、已下载大小及传输速率，并在下载完成后自动唤起系统安装（Android 原生 `FileProvider` 与 Windows Inno Setup 安装包）。
- 更新通道自主切换：在「设置」->「关于」中支持自由选择「正式版」或「测试预览版」更新通道。
- 测试版安全保障：切换至测试预览版时提供二次风险确认弹窗，检测到预览版更新时在弹窗显式标注橙色测试版警告横幅并提供「前往备份」快捷入口。
- GitHub API 规范化与 403 频率限制优雅降级：为升级检查网络请求注入标准 `User-Agent` 与 GitHub API 协议头；在 IP 触发 GitHub API 403 速率超限时弹出友好提示并提供直达 GitHub 发布页的一键跳转通道。
- 语义化版本（SemVer）完整支持：引入 `AppVersion` 引擎，精准处理预发布版本与正式版的递增/升级比较及防误降级逻辑。
- 规约测试集（Gherkin Spec Verification）：编写覆盖通道切换、预警横幅、降级弹窗与版本比对的场景级自动化测试。

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