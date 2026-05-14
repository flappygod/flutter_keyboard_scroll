# flutter_keyboard_scroll

在 Flutter 中监听系统软键盘的显示与隐藏，并在键盘遮挡输入区域时上推页面或可滚动内容。实现依赖 Android / iOS 原生侧与 Dart 侧 `EventChannel` 协同。

## 支持平台

| 平台 | 说明 |
| --- | --- |
| **Android** | 支持，一等能力目标。 |
| **iOS** | 支持，一等能力目标。 |
| **Web** | 不在支持范围；本包未提供 Web 插件实现。 |
| **Windows / macOS / Linux** | 不在支持范围；桌面端无对应原生键盘通道，**多平台工程请按平台选用或自行降级**（勿在桌面目标上依赖本库的键盘事件）。 |

若应用同时面向移动端与桌面/Web，建议在业务层用 `defaultTargetPlatform`、`Theme.of(context).platform` 或编译期条件导入，仅在 Android、iOS 上使用本包相关 API。

## 安装

在工程 `pubspec.yaml` 中加入依赖：

```yaml
dependencies:
  flutter_keyboard_scroll: ^1.0.23
```

然后执行 `flutter pub get`。

## 使用场景概览

- **仅监听键盘高度**：使用 `KeyboardObserver`，在 `showListener` / `hideListener` 或动画回调里自行改 `padding`、`Transform` 等。
- **自动把输入区顶到键盘上方**：使用 `KeyboardScroll` + `KeyboardScrollController`，为需要避让的 `TextField` 注册 `TextFieldWrapper`（`GlobalKey` + `FocusNode`）。

建议在包含键盘避让逻辑的页面将 `Scaffold` 的 `resizeToAvoidBottomInset` 设为 `false`，由本插件统一控制底部留白，避免与系统双重 resize 冲突。

## 示例一：`KeyboardObserver`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_scroll/flutter_keyboard_scroll.dart';

Widget build(BuildContext context) {
  return Scaffold(
    resizeToAvoidBottomInset: false,
    body: KeyboardObserver(
      showListener: (double former, double newer, int time) {
        // 键盘展开阶段（原生上报）
      },
      hideListener: (double former, double newer, int time) {
        // 键盘收起阶段
      },
      showAnimationListener: (double bottomInsets, bool end) {
        // 展开过程逐帧 bottom inset；end == true 表示本段动画结束
      },
      hideAnimationListener: (double bottomInsets, bool end) {
        // 收起过程逐帧
      },
      animationMode: KeyboardAnimationMode.mediaQuery,
      child: Column(
        children: const [
          Expanded(child: Placeholder()),
          TextField(decoration: InputDecoration(hintText: '输入内容')),
        ],
      ),
    ),
  );
}
```

## 示例二：`KeyboardScroll` + 控制器

```dart
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_scroll/flutter_keyboard_scroll.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final KeyboardScrollController _keyboardScrollController =
      KeyboardScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _keyboardScrollController.addTextFieldWrapper(
      TextFieldWrapper.fromKey(
        focusNode: _focusNode,
        focusKey: _fieldKey,
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: KeyboardScroll(
        controller: _keyboardScrollController,
        fitType: KeyboardScrollType.fitAddedTextField,
        child: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const SizedBox(height: 400),
            TextField(
              key: _fieldKey,
              focusNode: _focusNode,
              decoration: const InputDecoration(hintText: '消息'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## 主要 API

| 类型 | 说明 |
| --- | --- |
| `KeyboardObserver` | 包裹子树，接收键盘显示/隐藏与可选逐帧动画回调。 |
| `KeyboardScroll` | 内部组合 `KeyboardObserver`，按策略上推 `child`。 |
| `KeyboardScrollController` | 注册 `TextFieldWrapper`、开关是否参与避让等。 |
| `TextFieldWrapper` | 将 `FocusNode` 与测量用的 `GlobalKey` 绑定。 |
| `KeyboardAnimationMode` | `simulated` 使用本地动画；`mediaQuery` 跟随系统 inset。 |
| `KeyboardScrollType` | 控制按整页、全部输入框或仅已注册输入框计算位移。 |

更完整的符号说明见 pub.dev 上的 API 文档（由 dartdoc 生成）。

## 示例工程

仓库内 `example/` 目录为官方示例应用，可执行：

```bash
cd example && flutter run
```

## 链接

- 源码与 Issue：<https://github.com/flappygod/flutter_keyboard_scroll>
