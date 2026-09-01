# Hardener Guide: 变异测试与 Golden 像素抗退化压力测试指南

本指南为 **Hardener（强化与抗压验证角色）** 的核心操作手册，用于通过**变异测试思维**对抗 AI 生成的“无效测试”，并通过 **Golden 快照**确保 UI 与交互坚如磐石。

---

## 1. 变异测试实操协议 (4-Step Mutation Kill SOP)

Hardener **不得假设测试用例是有效的**。必须对本次核心逻辑至少设计并注入 **≥2 个突变体（Mutants）**，通过测试失败证实断言具备真实的故障捕获能力。

### 执行四步法：

**Step 1 [设计突变]**：针对生产代码修改一处关键逻辑，选用以下变异算子之一：
- **边界算子**：`progress >= 1.0` ➔ `progress > 1.0`（测试必须在 `progress == 1.0` 时挂掉）
- **逻辑反转**：`return isValid && isCached;` ➔ `return isValid || isCached;`
- **返回值篡改**：`return resultList.length;` ➔ `return 0;` 或 `return -1;`
- **状态赋值跳过**：注释掉核心状态赋值行（如 `_showHistory = true;`）

**Step 2 [注入突变并运行]**：临时修改生产代码，运行对应测试：
```powershell
fvm flutter test test/widgets/xxx_test.dart
```

**Step 3 [记录消灭证据]**：
- ✅ **突变被消灭 (KILLED)**：测试报错断言失败 → 记录失败断言与行号，证明测试有效
- ❌ **突变存活 (SURVIVED)**：测试全绿通过 → **必须立即返回 Coder 阶段补充精准断言，直到 KILLED**

**Step 4 [还原干净代码]**：将生产代码完全恢复正确实现，再次运行测试确认全绿。

### 必须在回复中输出的证据日志模板：

```
### 🛡️ Hardener Gate 5 产出物：变异消灭证据日志

| 突变编号 | 变异算子类型 | 目标位置与注入内容 | 预期触发断言 | 消灭证据（失败行号/消息） | 状态 |
| :--- | :--- | :--- | :--- | :--- | :---: |
| M-01 | 边界篡改 | `>= 1.0` ➔ `> 1.0` | `expect(status, completed)` | `Expected: completed, Actual: reading (test/xxx:42)` | ✅ KILLED |
| M-02 | 逻辑反转 | `&&` ➔ `||` | `expect(result, isFalse)` | `Expected: false, Actual: true (test/xxx:58)` | ✅ KILLED |

> **变异测试结论**：注入 X 个突变体，消灭 X 个，存活 0 个（击杀率 100%）。生产代码已完全还原。
```

> [!IMPORTANT]
> **Hardener 阶段的唯一完成证明是在回复中输出以上完整填写的证据日志。**
> "我采用了变异测试思维" 或 "测试套件已全绿" 不等于完成 Hardener 阶段。

> **Hardener 法则**：如果一个测试在篡改了核心逻辑后依然全绿，该测试必须重写，直到能 100% 杀死突变体（Kill Mutant）。

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
