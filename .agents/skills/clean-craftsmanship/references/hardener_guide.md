# Hardener Guide: 变异测试与 Golden 像素抗退化压力测试指南

本指南为 **Hardener（强化与抗压验证角色）** 的核心操作手册，用于通过**变异测试思维**对抗 AI 生成的“无效测试”，并通过 **Golden 快照**确保 UI 与交互坚如磐石。

---

## 1. 变异测试（Mutation Testing）——消灭“假测试”

### 核心机制：
变异测试通过在生产代码中故意注入**微小的逻辑缺陷（Mutants 突变体）**，验证测试用例是否能够敏锐报错。如果注入了 Bug 测试依然通过，说明测试用例存在**套套逻辑或假断言（Surviving Mutant）**。

### 常见的变异算子 (Mutation Operators)：
1. **条件边界算子**：
   - 生产代码：`if (progress >= 1.0)`
   - 注入突变：`if (progress > 1.0)`
   - *断言要求：测试必须在 `progress == 1.0` 时挂掉！*
2. **逻辑反转算子**：
   - 生产代码：`return isValid && isCached;`
   - 注入突变：`return isValid || isCached;`
3. **返回值篡改算子**：
   - 生产代码：`return book.chapters.length;`
   - 注入突变：`return 0;` 或 `return -1;`

> **Hardener 法则**：如果一个测试在篡改了核心逻辑后依然全绿，该测试必须重写，直到能 100% “杀死突变体（Kill Mutant）”。

---

## 2. Golden UI 快照抗退化测试 (Golden UI Testing)

用于毫秒级捕获页面布局、字号、边距与渲染像素层面的细微退化。

### 执行 Golden 测试：
```powershell
# 运行设置页等界面的像素级比对测试
fvm flutter test test/golden/settings_page_golden_test.dart

# 当且仅当 UI 变更是用户显式要求的主动重构时，才可更新基准快照：
fvm flutter test test/golden/settings_page_golden_test.dart --update-goldens
```

---

## 3. 极端场景压力测试协议 (Stress Testing Protocol)

在完成常规测试后，Hardener 必须主动验证以下 4 类边缘压力场景：
1. **多语言与长文本溢出**：德语/俄语等长文本渲染时，标题栏与卡片是否发生渲染溢出（RenderFlex overflowed）。
2. **数据源极端状态**：零书籍（空状态）、超万本大书架、损坏的 EPUB 压缩包、畸形 XML/OPF。
3. **横竖屏与高 DPI 切换**：平板/桌面宽屏模式与手机竖屏自适应切换。
4. **中断恢复一致性**：后台切换、断网、应用重启后状态是否能 100% 精确还原。

---

## 4. Hardener 终审验证 (The Gauntlet)

Hardener 完成以上所有抗压测试后，执行项目终审门禁：
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify_gauntlet.ps1
```
必须达成 **静态分析 0 阻断 + 41+ 项测试全绿 + Golden 比对 100% 一致 + Git 卫生干净**。
