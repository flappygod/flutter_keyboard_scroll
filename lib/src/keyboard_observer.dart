/// 软键盘事件与 [KeyboardObserver] 动画相关的类型与工具。
///
/// 在 Android/iOS 上通过 [EventChannel] 接收原生键盘高度变化；Web 上部分能力不可用。
library keyboard_observer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'keyboard_scroll.dart';

/// 与 [MediaQuery] 底部 inset 动画阶段对应的键盘动画类型。
enum KeyboardAnimationType {
  /// 键盘展开或底部安全区增大过程中。
  show,

  /// 键盘收起或底部安全区减小过程中。
  hide,
}

/// 注册/注销原生键盘显示与隐藏监听，并向 Dart 侧广播事件。
///
/// 仅使用静态方法；不要尝试实例化本类。
class KeyboardObserveListenManager {
  KeyboardObserveListenManager._();

  /// 与 Android/iOS 原生侧通信的广播通道。
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  /// 是否已订阅 [_eventChannel]；全局只建立一次订阅。
  static bool _listenState = false;

  /// 键盘显示（type == 2）回调集合。
  static final Set<KeyboardObserverListener> _showListeners = {};

  /// 键盘隐藏（type == 3）回调集合。
  static final Set<KeyboardObserverListener> _hideListeners = {};

  /// 注册键盘即将显示阶段的监听（原生 type == 2 时回调）。
  static void addKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.add(listener);
    _checkListeners();
  }

  /// 注册键盘即将隐藏阶段的监听（原生 type == 3 时回调）。
  static void addKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.add(listener);
    _checkListeners();
  }

  /// 移除由 [addKeyboardShowListener] 注册的监听。
  static void removeKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.remove(listener);
  }

  /// 移除由 [addKeyboardHideListener] 注册的监听。
  static void removeKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.remove(listener);
  }

  /// 在首次注册监听时订阅原生广播，并按 type 分发给对应集合。
  static void _checkListeners() {
    if (_listenState) {
      return;
    }
    _listenState = true;
    _eventChannel
        .receiveBroadcastStream()
        .map((result) => result as Map)
        .listen((data) {
      // type == 2：软键盘弹出
      if (data["type"] == 2) {
        for (KeyboardObserverListener listener in _showListeners) {
          listener(
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
      // type == 3：软键盘收起
      if (data["type"] == 3) {
        for (KeyboardObserverListener listener in _hideListeners) {
          listener(
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
    });
  }
}

/// 键盘显示或隐藏时触发，参数为上一帧高度 [former]、当前目标高度 [newer] 与动画时长 [time]（毫秒）。
typedef KeyboardObserverListener = Function(
    double former, double newer, int time);

/// 键盘动画过程中底部 inset 回调：[bottomInsets] 为当前值，[end] 为 true 表示本段动画结束。
typedef KeyboardAnimationListener = Function(double bottomInsets, bool end);

/// 包裹子组件以监听软键盘显示/隐藏，并可选择模拟或跟随系统 inset 动画。
class KeyboardObserver extends StatefulWidget {
  /// 子组件。
  final Widget? child;

  /// 键盘展开动画曲线；为 null 时使用默认 Cubic。
  final Curve? curveShow;

  /// 键盘展开动画时长。
  final Duration durationShow;

  /// 键盘收起动画曲线；为 null 时使用默认 Cubic。
  final Curve? curveHide;

  /// 键盘收起动画时长。
  final Duration durationHide;

  /// 动画驱动方式：模拟插值或跟随 [MediaQuery] 变化。
  final KeyboardAnimationMode animationMode;

  /// 键盘显示阶段原生回调。
  final KeyboardObserverListener? showListener;

  /// 键盘隐藏阶段原生回调。
  final KeyboardObserverListener? hideListener;

  /// 键盘展开过程中逐帧 inset 回调（需与 [animationMode] 配合）。
  final KeyboardAnimationListener? showAnimationListener;

  /// 键盘收起过程中逐帧 inset 回调（需与 [animationMode] 配合）。
  final KeyboardAnimationListener? hideAnimationListener;

  /// 创建键盘观察者。
  const KeyboardObserver({
    Key? key,
    this.child,
    this.showListener,
    this.hideListener,
    this.curveShow,
    this.durationShow = const Duration(milliseconds: 500),
    this.curveHide,
    this.durationHide = const Duration(milliseconds: 500),
    this.showAnimationListener,
    this.hideAnimationListener,
    this.animationMode = KeyboardAnimationMode.simulated,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _KeyboardObserverState();
  }
}

/// [KeyboardObserver] 的状态：按 [KeyboardAnimationMode] 选择模拟动画或跟随系统 inset。
class _KeyboardObserverState extends State<KeyboardObserver>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// [KeyboardAnimationMode.simulated] 下键盘展开动画控制器。
  AnimationController? _showAnimationController;

  /// [KeyboardAnimationMode.simulated] 下键盘收起动画控制器。
  AnimationController? _hideAnimationController;

  /// 模拟动画当前插值高度，用于下一段 Tween 的 begin。
  double _formerHeight = 0;

  /// 展开动画每帧监听，转发给 [KeyboardObserver.showAnimationListener]。
  VoidCallback? _showAnimListener;

  /// 收起动画每帧监听，转发给 [KeyboardObserver.hideAnimationListener]。
  VoidCallback? _hideAnimListener;

  /// 注册到 [KeyboardObserveListenManager] 的显示阶段闭包。
  KeyboardObserverListener? _showListener;

  /// 注册到 [KeyboardObserveListenManager] 的隐藏阶段闭包。
  KeyboardObserverListener? _hideListener;

  /// 当前展开方向的高度 Tween。
  Animation<double>? _showAnim;

  /// 当前收起方向的高度 Tween。
  Animation<double>? _hideAnim;

  /// [KeyboardAnimationMode.mediaQuery] 下最近一次有效的底部 inset（逻辑像素）。
  double _bottomPadding = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initListeners();
  }

  @override
  void didUpdateWidget(KeyboardObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationMode != oldWidget.animationMode) {
      _initListeners();
      return;
    }

    ///mediaQuery 不使用 duration；仅 simulated 下同步 AnimationController 时长。
    if (widget.animationMode == KeyboardAnimationMode.simulated &&
        (widget.durationShow != oldWidget.durationShow ||
            widget.durationHide != oldWidget.durationHide)) {
      _updateSimulatedDurations();
    }
  }

  /// [KeyboardAnimationMode.simulated] 下仅更新动画时长，避免打断进行中的键盘动画段。
  void _updateSimulatedDurations() {
    _showAnimationController?.duration = widget.durationShow;
    _hideAnimationController?.duration = widget.durationHide;
  }

  /// 在 [didChangeMetrics] 中应用新的底部 inset，驱动逐帧回调或暂存 pending。
  void _applyMediaQueryInset(double inset) {
    _bottomPadding = inset;
  }

  /// 按 [widget.animationMode] 注册原生监听并初始化对应模式的内部状态。
  void _initListeners() {
    // Web 无原生 EventChannel 实现，直接跳过。
    if (kIsWeb) {
      return;
    }

    ///先移除之前的
    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }

    ///创建新的
    _showListener = (double former, double newer, int time) {
      widget.showListener?.call(former, newer, time);
      if (widget.showAnimationListener == null) {
        return;
      }
      _showAnimation(former, newer);
    };
    _hideListener = (double former, double newer, int time) {
      widget.hideListener?.call(former, newer, time);
      if (widget.hideAnimationListener == null) {
        return;
      }
      _hideAnimation(former, newer);
    };
    KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);

    ///未配置动画监听时，仅需原生 show/hide 回调，无需创建 AnimationController。
    if (widget.showAnimationListener == null &&
        widget.hideAnimationListener == null) {
      return;
    }

    ///show动画监听
    _showAnimListener ??= () {
      switch (widget.animationMode) {
        case KeyboardAnimationMode.simulated:
          if (_formerHeight != _showAnim!.value) {
            _formerHeight = _showAnim!.value;
            widget.showAnimationListener?.call(_formerHeight, false);
          }
          break;
        case KeyboardAnimationMode.mediaQuery:
          if (_formerHeight != _bottomPadding) {
            _formerHeight = _bottomPadding;
            widget.showAnimationListener?.call(_formerHeight, false);
          }
          break;
      }
    };

    ///hide动画监听
    _hideAnimListener ??= () {
      switch (widget.animationMode) {
        case KeyboardAnimationMode.simulated:
          if (_formerHeight != _hideAnim!.value) {
            _formerHeight = _hideAnim!.value;
            widget.hideAnimationListener?.call(_formerHeight, false);
          }
          break;
        case KeyboardAnimationMode.mediaQuery:
          if (_formerHeight != _bottomPadding) {
            _formerHeight = _bottomPadding;
            widget.hideAnimationListener?.call(_formerHeight, false);
          }
          break;
      }
    };

    ///show控制器更新创建
    if (_showAnimationController != null) {
      _showAnimationController?.duration = widget.durationShow;
    } else {
      _showAnimationController = AnimationController(
        duration: widget.durationShow,
        vsync: this,
      );
    }

    ///hide控制器更新创建
    if (_hideAnimationController != null) {
      _hideAnimationController!.duration = widget.durationHide;
    } else {
      _hideAnimationController = AnimationController(
        duration: widget.durationHide,
        vsync: this,
      );
    }
  }

  /// 注销原生监听、取消 debounce、释放 [AnimationController]。
  void _disposeListeners() {
    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }
    _showAnimationController?.dispose();
    _hideAnimationController?.dispose();
    _showAnimationController = null;
    _hideAnimationController = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeListeners();
    super.dispose();
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘展开动画。
  ///
  /// [former] 来自原生事件，当前实现以 [_formerHeight] 为 Tween 起点以衔接上一段动画。
  void _showAnimation(double former, double newer) {
    if (_hideAnimListener != null) {
      _hideAnim?.removeListener(_hideAnimListener!);
    }
    if (_showAnimListener != null) {
      _showAnim?.removeListener(_showAnimListener!);
    }
    // 打断可能仍在进行的反向动画
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _hideAnimationController?.reset();
    _showAnimationController?.reset();
    if (_showAnimationController != null) {
      _showAnim = Tween<double>(begin: _formerHeight, end: newer).animate(
        CurvedAnimation(
          parent: _showAnimationController!,
          curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
        ),
      );
      _showAnim?.addListener(_showAnimListener!);
      _showAnimationController?.forward().then((_) {
        widget.showAnimationListener?.call(_showAnim?.value ?? 0, true);
      });
    }
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘收起动画。
  ///
  /// [former] 来自原生事件，当前实现以 [_formerHeight] 为 Tween 起点以衔接上一段动画。
  void _hideAnimation(double former, double newer) {
    if (_hideAnimListener != null) {
      _hideAnim?.removeListener(_hideAnimListener!);
    }
    if (_showAnimListener != null) {
      _showAnim?.removeListener(_showAnimListener!);
    }
    // 打断可能仍在进行的反向动画
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _showAnimationController?.reset();
    _hideAnimationController?.reset();
    if (_hideAnimationController != null) {
      _hideAnim = Tween<double>(begin: _formerHeight, end: newer).animate(
        CurvedAnimation(
          parent: _hideAnimationController!,
          curve: widget.curveHide ?? const Cubic(0.34, 0.84, 0.12, 1.00),
        ),
      );
      _hideAnim?.addListener(_hideAnimListener!);
      _hideAnimationController?.forward().then((_) {
        widget.hideAnimationListener?.call(_hideAnim?.value ?? 0, true);
      });
    }
  }

  /// 系统窗口 metrics 变化时更新底部 inset（主要用于 mediaQuery 模式）。
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    //在 build 之外收到 metrics 变化，需通过 View 读取 viewInsets。
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    _applyMediaQueryInset(inset);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}
