# Coder Guide: 严格 TDD 与 Flutter/Riverpod 测试实战指南

本指南为 **Coder（TDD 编码角色）** 的核心操作手册，用于贯彻“先写失败测试，再写最简实现”的测试驱动开发铁律。

---

## 1. 鲍勃大叔 TDD 三定律 (Uncle Bob's Three Laws of TDD)

1. **第一定律**：在写出一个**编译失败或断言失败的单元测试**之前，不准写任何生产代码。
2. **第二定律**：只要测试出现失败（哪怕只是一个断言失败或编译错误），立即停止写测试，开始写生产代码。
3. **第三定律**：生产代码只要**刚好能跑通当前失败的测试**，立即停止写生产代码，转入重构或下一个测试。

---

## 2. Flutter / Riverpod TDD 编写范式

### 范式 1：纯逻辑与工具类测试 (Pure Unit Test)
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadingPositionHelper', () {
    test('should clamp progress percentage between 0.0 and 1.0', () {
      // 1. [RED] 先写测试断言
      final result = clampProgress(1.5);
      expect(result, equals(1.0));
      
      final negative = clampProgress(-0.2);
      expect(negative, equals(0.0));
    });
  });
}
```

### 范式 2：Riverpod 状态与 Provider 单元测试
使用 `ProviderContainer` 隔离测试 Provider 行为：
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bookListProvider initializes with empty state', () {
    final container = ProviderContainer(
      overrides: [
        // 模拟依赖
      ],
    );
    addTearDown(container.dispose);

    // 观察 Provider 状态演进
    final state = container.read(bookListProvider);
    expect(state, isEmpty);
  });
}
```

### 范式 3：Widget 交互测试 (Widget Test)
```dart
testWidgets('Tapping setting tile navigates to subpage', (WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: SettingsPage()),
    ),
  );

  // 验证初始状态渲染
  expect(find.text('阅读设置'), findsOneWidget);

  // 触发交互
  await tester.tap(find.text('阅读设置'));
  await tester.pumpAndSettle();

  // 验证导航后结果
  expect(find.byType(ReadingSettingsSubpage), findsOneWidget);
});
```

---

## 3. Coder 退出标准 (Coder Definition of Done)

- [ ] 每一个 Gherkin 规约场景都有对应的单元/Widget 测试覆盖。
- [ ] 运行 `fvm flutter test` 全部通过（Green）。
- [ ] 生产代码仅包含使测试通过的最简必要逻辑，无多余未测代码。
- [ ] **→ 交接至 Cleaner**：立即对新写的每个函数逐个计算行数与圈复杂度，输出《函数量化审计表》（Gate 4）。
- [ ] **→ 交接至 Hardener**：为核心逻辑至少设计 2 个突变体，若发现突变存活须立即返回 Coder 补充精准断言（Gate 5）。
