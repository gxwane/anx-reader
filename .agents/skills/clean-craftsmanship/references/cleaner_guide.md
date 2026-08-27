# Cleaner Guide: CRAP 评分管控与 Dart 坏味道重构指南

本指南为 **Cleaner（坏味道与复杂度清理角色）** 的核心操作手册，用于通过量化指标和静态分析，消除 AI 生成代码中的膨胀、过度设计与坏味道。

---

## 1. CRAP 评分模型 (Change Risk Anti-Patterns)

CRAP 分数用于量化**“代码圈复杂度”**与**“测试覆盖率不足”**结合所带来的改动风险：

$$\text{CRAP}(m) = \text{comp}(m)^2 \times (1 - \text{cov}(m))^3 + \text{comp}(m)$$

- $\text{comp}(m)$：方法/函数 $m$ 的圈复杂度（分支数：`if`、`switch`、`for`、`while`、`catch`、`&&`、`||`、`? :` 等）。
- $\text{cov}(m)$：该方法的单元测试代码覆盖率（$0.0 \sim 1.0$）。

### 🛑 CRAP 硬性阈值要求：
1. **CRAP 分数上限**：任何函数的 CRAP 分数必须 **$\le 30$**。
2. **圈复杂度上限**：单一函数的圈复杂度 $\text{comp}(m)$ 原则上必须 **$\le 10$**。
3. **函数长度上限**：单函数行数原则上必须 **$\le 30$ 行**（超过即触发拆分重构）。

---

## 2. Dart 重构与坏味道清理实务

### 模式 1：深层嵌套扁平化（卫语句 Guard Clauses）
**Bad (深层嵌套)**:
```dart
void handleBookOpen(Book? book) {
  if (book != null) {
    if (book.filePath.isNotEmpty) {
      if (File(book.filePath).existsSync()) {
        _openReader(book);
      }
    }
  }
}
```
**Good (卫语句提前退出)**:
```dart
void handleBookOpen(Book? book) {
  if (book == null || book.filePath.isEmpty) return;
  if (!File(book.filePath).existsSync()) return;
  
  _openReader(book);
}
```

### 模式 2：异步 Context 安全性重构
在跨越 `await` 异步调用后使用 `BuildContext` 时，必须加入 mounted 保护：
```dart
final result = await showDialog(...);
if (!context.mounted) return; // <-- 必须保护
Navigator.of(context).pop();
```

### 模式 3：消除临时调试与死代码
- 严禁提交包含 `print(...)` 的代码（使用项目封装的 `AnxLog` / `Logger`）。
- 移除所有未使用的变量、导入（`unused_import`）与废弃代码注释。

---

## 3. Cleaner 质检清单 (Cleaner Checklist)

- [ ] 运行 `fvm flutter analyze --no-fatal-infos` 确认 0 compilation errors/warnings。
- [ ] 检查所有新增函数是否符合小函数（$\le 30$ 行）与单一职责（SRP）。
- [ ] 确认没有引入冗余的抽象层或过度设计。
