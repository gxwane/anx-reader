# Specifier Guide: Given-When-Then 规约与验收定义指南

本指南为 **Specifier（需求与规约角色）** 的核心操作手册，用于在编写任何代码前，将自然语言需求或缺陷描述转化为**精确、确定性的 Gherkin 验收规约与边界定义**。

---

## 1. 规约制定三原则 (Specifier Principles)

1. **消除自然语言歧义**：绝不接受“优化一下排版”或“修一下崩溃”这种模糊指令，必须将其拆解为明确的前置状态、触发动作与断言。
2. **穷尽边界与边缘异常**：主动推演空列表、空文件、网络中断、超长文本、未授权等异常场景。
3. **可直接映射测试**：每一个 `Scenario` 必须能直接转换为一个 Flutter 单元测试或 Widget 测试（`testWidgets`）。

---

## 2. Gherkin 标准规约模板 (Specifier Template)

```gherkin
Feature: [功能 / 缺陷修复标题]
  As a [用户角色，例如：EPUB 读者 / 设置管理者]
  I want [具体操作意图]
  So that [带来的业务价值]

  # 场景 1：正常主流程 (Happy Path)
  Scenario: [正常操作成功的场景描述]
    Given [前置状态 / 数据上下文，如：书架已加载 1 本 EPUB 书籍]
    When [用户触发操作，如：点击打开书籍]
    Then [期望达到的系统状态 / 页面渲染结果]
    And [附加后置断言]

  # 场景 2：边界与异常处理 (Edge Cases & Fault Tolerance)
  Scenario: [异常或边界情况，如：损坏的书籍文件]
    Given [输入异常数据或不可用依赖]
    When [触发解析操作]
    Then [系统应友好提示错误，且绝不崩溃]
    And [底层状态保持安全回滚]

  # 场景 3：阅读器状态一致性 (State Preservation)
  Scenario: [翻页、旋转屏幕或主题切换]
    Given [阅读器处于特定章节位置 (CFI / 进度百分比)]
    When [发生系统事件（如切换深色模式 / 屏幕旋转）]
    Then [阅读位置必须 100% 精准恢复]
    And [不出现画面白屏或状态抖动]
```

---

## 3. Flutter 测试映射范式 (Flutter Mapping)

Specifier 定义的 Gherkin 场景将直接交接给 **Coder 角色**：

```dart
testWidgets('Scenario: [Feature Name] happy path', (WidgetTester tester) async {
  // GIVEN: 初始化 mock 或状态
  
  // WHEN: 触发事件或 pump UI
  
  // THEN: 验证结果断言
  expect(find.text('...'), findsOneWidget);
});
```
