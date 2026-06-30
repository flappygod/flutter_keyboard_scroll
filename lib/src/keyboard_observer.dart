/// 软键盘事件与 [KeyboardObserver] 动画相关的类型与工具。
///
/// 在 Android/iOS 上通过 [EventChannel] 接收原生键盘高度变化；Web 上部分能力不可用。
library keyboard_observer;

import 'dart:async';

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

  /// EventChannel 订阅。
  static StreamSubscription? _subscription;

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
    _checkDispose();
  }

  /// 移除由 [addKeyboardHideListener] 注册的监听。
  static void removeKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.remove(listener);
    _checkDispose();
  }

  /// 在首次注册监听时订阅原生广播，并按 type 分发给对应集合。
  static void _checkListeners() {
    if (_listenState) {
      return;
    }
    _listenState = true;
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .map((result) => result as Map)
        .listen((data) {
      if (data["type"] == 2) {
        for (final listener in _showListeners.toList()) {
          listener(
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }

      if (data["type"] == 3) {
        for (final listener in _hideListeners.toList()) {
          listener(
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
    });
  }

  /// 当没有任何监听时，注销 EventChannel。
  static Future<void> _checkDispose() async {
    if (_showListeners.isNotEmpty || _hideListeners.isNotEmpty) {
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    _listenState = false;
    await subscription?.cancel();
  }
}

/// 键盘显示或隐藏时触发，参数为上一帧高度 [former]、当前目标高度 [newer] 与动画时长 [time]（毫秒）。
typedef KeyboardObserverListener = Function(
  double former,
  double newer,
  int time,
);

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

  CurvedAnimation? _showCurve;
  CurvedAnimation? _hideCurve;

  /// [KeyboardAnimationMode.mediaQuery] 下最近一次有效的底部 inset（逻辑像素）。
  double _bottomPadding = 0;

  /// mediaQuery 模式下当前 didChangeMetrics 驱动的动画类型。
  KeyboardAnimationType? _metricsDrivingType;

  /// mediaQuery 模式下当前动画目标值。
  double? _metricsTargetHeight;

  /// mediaQuery 动画序列号。每开启一段新的 mediaQuery 动画就递增。
  int _metricsSequence = 0;

  /// 当前仍然有效的 mediaQuery 动画序列号。
  int? _activeMetricsSequence;

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

    /// 同步 AnimationController 时长。
    if (widget.durationShow != oldWidget.durationShow ||
        widget.durationHide != oldWidget.durationHide) {
      _updateSimulatedDurations();
    }
  }

  /// 更新动画时长，避免打断进行中的键盘动画段。
  void _updateSimulatedDurations() {
    _showAnimationController?.duration = widget.durationShow;
    _hideAnimationController?.duration = widget.durationHide;
  }

  /// 按 [widget.animationMode] 注册原生监听并初始化对应模式的内部状态。
  void _initListeners() {
    // Web 无原生 EventChannel 实现，直接跳过。
    if (kIsWeb) {
      return;
    }

    /// 先移除之前的
    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }

    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _activeMetricsSequence = null;

    /// 创建新的
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

    /// 未配置动画监听时，仅需原生 show/hide 回调，无需创建 AnimationController。
    if (widget.showAnimationListener == null &&
        widget.hideAnimationListener == null) {
      return;
    }

    /// show动画监听
    _showAnimListener ??= () {
      switch (widget.animationMode) {
        /// 模拟模式
        case KeyboardAnimationMode.simulated:
          if (_formerHeight != _showAnim!.value) {
            _formerHeight = _showAnim!.value;
            widget.showAnimationListener?.call(_formerHeight, false);
          }
          break;

        /// mediaQuery模式：由 didChangeMetrics 驱动，这里不处理
        case KeyboardAnimationMode.mediaQuery:
          break;
      }
    };

    /// hide动画监听
    _hideAnimListener ??= () {
      switch (widget.animationMode) {
        /// 模拟模式
        case KeyboardAnimationMode.simulated:
          if (_formerHeight != _hideAnim!.value) {
            _formerHeight = _hideAnim!.value;
            widget.hideAnimationListener?.call(_formerHeight, false);
          }
          break;

        /// mediaQuery模式：由 didChangeMetrics 驱动，这里不处理
        case KeyboardAnimationMode.mediaQuery:
          break;
      }
    };

    /// show控制器更新创建
    if (_showAnimationController != null) {
      _showAnimationController?.duration = widget.durationShow;
    } else {
      _showAnimationController = AnimationController(
        duration: widget.durationShow,
        vsync: this,
      );
    }

    /// hide控制器更新创建
    if (_hideAnimationController != null) {
      _hideAnimationController!.duration = widget.durationHide;
    } else {
      _hideAnimationController = AnimationController(
        duration: widget.durationHide,
        vsync: this,
      );
    }
  }

  /// 注销原生监听、释放 [AnimationController]。
  void _disposeListeners() {
    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }
    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _activeMetricsSequence = null;
    _showCurve?.dispose();
    _hideCurve?.dispose();
    _showAnimationController?.dispose();
    _hideAnimationController?.dispose();
    _showAnimationController = null;
    _hideAnimationController = null;
    _showCurve = null;
    _hideCurve = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeListeners();
    super.dispose();
  }

  /// 开启一段新的 mediaQuery 动画序列，并返回其 token。
  int _beginMetricsSequence(
    KeyboardAnimationType type,
    double newer,
  ) {
    _metricsSequence += 1;
    final int token = _metricsSequence;
    _activeMetricsSequence = token;
    _metricsDrivingType = type;
    _metricsTargetHeight = newer;
    return token;
  }

  /// 结束当前 mediaQuery 动画序列，仅当 token 仍然有效时才执行。
  void _finishMetricsSequenceIfMatch(int token) {
    if (_activeMetricsSequence != token) {
      return;
    }
    _activeMetricsSequence = null;
    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _showAnimationController?.stop();
    _hideAnimationController?.stop();
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘展开动画。
  ///
  /// [former] 来自原生事件，当前实现以 [_formerHeight] 为 Tween 起点以衔接上一段动画。
  void _showAnimation(double former, double newer) {
    VoidCallback? hideListener = _hideAnimListener;
    if (hideListener != null) {
      _hideAnim?.removeListener(hideListener);
    }
    VoidCallback? showListener = _showAnimListener;
    if (showListener != null) {
      _showAnim?.removeListener(showListener);
    }

    // 打断可能仍在进行的反向动画
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _hideAnimationController?.reset();
    _showAnimationController?.reset();

    if (widget.animationMode == KeyboardAnimationMode.mediaQuery) {
      final int token = _beginMetricsSequence(
        KeyboardAnimationType.show,
        newer,
      );

      _formerHeight = _bottomPadding;
      widget.showAnimationListener?.call(_formerHeight, false);

      // 如果当前已经等于目标值，直接完成，并保证最终值就是 newer。
      if (_bottomPadding == newer) {
        _formerHeight = newer;
        _bottomPadding = newer;
        widget.showAnimationListener?.call(newer, true);
        _finishMetricsSequenceIfMatch(token);
        return;
      }

      _showAnimationController?.forward().then((_) {
        if (!mounted) {
          return;
        }
        if (widget.animationMode != KeyboardAnimationMode.mediaQuery) {
          return;
        }
        if (_activeMetricsSequence != token) {
          return;
        }
        if (_metricsDrivingType != KeyboardAnimationType.show) {
          return;
        }
        if (_metricsTargetHeight != newer) {
          return;
        }

        // 兜底保证：控制器完成时，最终一定以 newer 收尾。
        if (_formerHeight != newer) {
          _formerHeight = newer;
          _bottomPadding = newer;
          widget.showAnimationListener?.call(newer, false);
        }
        widget.showAnimationListener?.call(newer, true);
        _finishMetricsSequenceIfMatch(token);
      });
      return;
    }

    // simulated 模式
    if (_showAnimationController != null) {
      _showCurve?.dispose();
      _showCurve = CurvedAnimation(
        parent: _showAnimationController!,
        curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      );
      _showAnim =
          Tween<double>(begin: _formerHeight, end: newer).animate(_showCurve!);
      _showAnim?.addListener(_showAnimListener!);
      _showAnimationController?.forward().then((_) {
        if (mounted) {
          widget.showAnimationListener?.call(_showAnim?.value ?? newer, true);
        }
      });
    }
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘收起动画。
  ///
  /// [former] 来自原生事件，当前实现以 [_formerHeight] 为 Tween 起点以衔接上一段动画。
  void _hideAnimation(double former, double newer) {
    VoidCallback? hideListener = _hideAnimListener;
    if (hideListener != null) {
      _hideAnim?.removeListener(hideListener);
    }
    VoidCallback? showListener = _showAnimListener;
    if (showListener != null) {
      _showAnim?.removeListener(showListener);
    }

    // 打断可能仍在进行的反向动画
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _showAnimationController?.reset();
    _hideAnimationController?.reset();

    if (widget.animationMode == KeyboardAnimationMode.mediaQuery) {
      final int token = _beginMetricsSequence(
        KeyboardAnimationType.hide,
        newer,
      );

      _formerHeight = _bottomPadding;
      widget.hideAnimationListener?.call(_formerHeight, false);

      // 如果当前已经等于目标值，直接完成，并保证最终值就是 newer。
      if (_bottomPadding == newer) {
        _formerHeight = newer;
        _bottomPadding = newer;
        widget.hideAnimationListener?.call(newer, true);
        _finishMetricsSequenceIfMatch(token);
        return;
      }

      _hideAnimationController?.forward().then((_) {
        if (!mounted) {
          return;
        }
        if (widget.animationMode != KeyboardAnimationMode.mediaQuery) {
          return;
        }
        if (_activeMetricsSequence != token) {
          return;
        }
        if (_metricsDrivingType != KeyboardAnimationType.hide) {
          return;
        }
        if (_metricsTargetHeight != newer) {
          return;
        }

        // 兜底保证：控制器完成时，最终一定以 newer 收尾。
        if (_formerHeight != newer) {
          _formerHeight = newer;
          _bottomPadding = newer;
          widget.hideAnimationListener?.call(newer, false);
        }
        widget.hideAnimationListener?.call(newer, true);
        _finishMetricsSequenceIfMatch(token);
      });
      return;
    }

    // simulated 模式
    if (_hideAnimationController != null) {
      _hideCurve?.dispose();
      _hideCurve = CurvedAnimation(
        parent: _hideAnimationController!,
        curve: widget.curveHide ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      );
      _hideAnim =
          Tween<double>(begin: _formerHeight, end: newer).animate(_hideCurve!);
      _hideAnim?.addListener(_hideAnimListener!);
      _hideAnimationController?.forward().then((_) {
        if (mounted) {
          widget.hideAnimationListener?.call(_hideAnim?.value ?? newer, true);
        }
      });
    }
  }

  /// 系统窗口 metrics 变化时更新底部 inset（主要用于 mediaQuery 模式）。
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }

    // 所有 change 状态下，都先缓存最新 bottom inset
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    _bottomPadding = inset;

    if (widget.animationMode != KeyboardAnimationMode.mediaQuery) {
      return;
    }

    final drivingType = _metricsDrivingType;
    final targetHeight = _metricsTargetHeight;
    final activeToken = _activeMetricsSequence;

    if (drivingType == null || targetHeight == null || activeToken == null) {
      return;
    }

    if (_formerHeight != _bottomPadding) {
      _formerHeight = _bottomPadding;
      switch (drivingType) {
        case KeyboardAnimationType.show:
          widget.showAnimationListener?.call(_formerHeight, false);
          break;
        case KeyboardAnimationType.hide:
          widget.hideAnimationListener?.call(_formerHeight, false);
          break;
      }
    }

    if (_bottomPadding == targetHeight) {
      switch (drivingType) {
        case KeyboardAnimationType.show:
          _formerHeight = targetHeight;
          _bottomPadding = targetHeight;
          widget.showAnimationListener?.call(targetHeight, true);
          break;
        case KeyboardAnimationType.hide:
          _formerHeight = targetHeight;
          _bottomPadding = targetHeight;
          widget.hideAnimationListener?.call(targetHeight, true);
          break;
      }
      _finishMetricsSequenceIfMatch(activeToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}
