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

/// 键盘事件监听回调。
///
/// 参数依次为：
/// - former: 变化前高度
/// - newer: 变化后高度
/// - time: 动画时长/时间（由原生侧定义）
typedef KeyboardObserverListener = void Function(
  double former,
  double newer,
  int time,
);

/// 注册原生键盘显示与隐藏监听，并向 Dart 侧广播事件。
///
/// 设计说明：
/// - 全程常驻订阅 EventChannel，只初始化一次，不主动取消；
/// - 避免频繁 add/remove listener 时，因订阅切换产生事件丢失；
/// - 仅使用静态方法；不要尝试实例化本类。
class KeyboardObserveListenManager {
  KeyboardObserveListenManager._();

  /// 与 Android/iOS 原生侧通信的广播通道。
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  /// 键盘显示（type == 2）回调集合。
  static final Set<KeyboardObserverListener> _showListeners =
      <KeyboardObserverListener>{};

  /// 键盘隐藏（type == 3）回调集合。
  static final Set<KeyboardObserverListener> _hideListeners =
      <KeyboardObserverListener>{};

  /// EventChannel 订阅。
  static StreamSubscription<dynamic>? _subscription;

  /// 是否已经完成初始化。
  static bool _initialized = false;

  /// 注册键盘即将显示阶段的监听（原生 type == 2 时回调）。
  static void addKeyboardShowListener(KeyboardObserverListener listener) {
    _ensureInitialized();
    _showListeners.add(listener);
  }

  /// 注册键盘即将隐藏阶段的监听（原生 type == 3 时回调）。
  static void addKeyboardHideListener(KeyboardObserverListener listener) {
    _ensureInitialized();
    _hideListeners.add(listener);
  }

  /// 移除由 [addKeyboardShowListener] 注册的监听。
  static void removeKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.remove(listener);
  }

  /// 移除由 [addKeyboardHideListener] 注册的监听。
  static void removeKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.remove(listener);
  }

  /// 可选：移除所有显示监听。
  static void clearKeyboardShowListeners() {
    _showListeners.clear();
  }

  /// 可选：移除所有隐藏监听。
  static void clearKeyboardHideListeners() {
    _hideListeners.clear();
  }

  /// 可选：移除所有监听。
  static void clearAllListeners() {
    _showListeners.clear();
    _hideListeners.clear();
  }

  /// 确保 EventChannel 只初始化订阅一次。
  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _subscription = _eventChannel.receiveBroadcastStream().listen(
          _handleEvent,
          onError: _handleError,
          onDone: _handleDone,
          cancelOnError: false,
        );
  }

  /// 处理原生事件分发。
  static void _handleEvent(dynamic result) {
    if (result is! Map) {
      return;
    }
    final dynamic typeValue = result['type'];
    final int? type = _toInt(typeValue);
    if (type == null) {
      return;
    }
    final double former = _toDouble(result['former']) ?? 0.0;
    final double newer = _toDouble(result['newer']) ?? 0.0;
    final int time = _toInt(result['time']) ?? 0;
    if (type == 2) {
      for (final listener in _showListeners.toList()) {
        listener(former, newer, time);
      }
      return;
    }
    if (type == 3) {
      for (final listener in _hideListeners.toList()) {
        listener(former, newer, time);
      }
    }
  }

  /// 处理订阅错误。
  ///
  /// 常驻模式下，如果底层流异常结束，尝试自动重建订阅。
  static void _handleError(Object error, [StackTrace? stackTrace]) {
    _subscription = null;
    _initialized = false;
    _ensureInitialized();
  }

  /// 处理订阅结束。
  ///
  /// 常驻模式下，如果底层流结束，尝试自动重建订阅。
  static void _handleDone() {
    _subscription = null;
    _initialized = false;
    _ensureInitialized();
  }

  /// 将动态值安全转换为 int。
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  /// 将动态值安全转换为 double。
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// 可选：手动初始化。
  ///
  /// 如果你希望在应用启动时就建立订阅，可以主动调用一次。
  static void initialize() {
    _ensureInitialized();
  }

  /// 可选：仅用于测试或应用彻底销毁时手动释放。
  ///
  /// 正常业务场景下，常驻模式通常不需要调用。
  static Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    _initialized = false;
    await subscription?.cancel();
  }
}

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

  /// simulated 动画序列号。每开启一段新的 simulated 动画就递增。
  int _simulatedSequence = 0;

  /// 当前仍然有效的 simulated 动画序列号。
  int? _activeSimulatedSequence;

  /// Android 下 mediaQuery 模式的“稳定检测”定时器。
  Timer? _androidMetricsSettleTimer;

  /// Android 下判定“已稳定”的静默时长。
  static const Duration _androidMetricsSettleDuration =
      Duration(milliseconds: 200);

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

  /// 根据平台决定动画结束时采用的最终高度。
  ///
  /// Android：最终以 Flutter 侧最新的 [_bottomPadding] 为准。
  /// iOS/其他平台：继续使用原生事件给出的 [newer]。
  double _resolveFinalHeight(double newer) {
    if (_isAndroid) {
      return _bottomPadding;
    }
    return newer;
  }

  /// 取消 Android metrics 稳定检测定时器。
  void _cancelAndroidMetricsSettleTimer() {
    _androidMetricsSettleTimer?.cancel();
    _androidMetricsSettleTimer = null;
  }

  /// 启动/重启 Android metrics 稳定检测。
  ///
  /// 每次 didChangeMetrics 收到新 inset 后重启一次；
  /// 若在一段时间内不再变化，则认为本段键盘动画结束。
  void _restartAndroidMetricsSettleTimer(int token) {
    _cancelAndroidMetricsSettleTimer();
    _androidMetricsSettleTimer = Timer(_androidMetricsSettleDuration, () {
      if (!mounted) {
        return;
      }
      if (widget.animationMode != KeyboardAnimationMode.mediaQuery) {
        return;
      }
      if (_activeMetricsSequence != token) {
        return;
      }
      final drivingType = _metricsDrivingType;
      if (drivingType == null) {
        return;
      }
      final double finalHeight = _bottomPadding;
      _formerHeight = finalHeight;
      switch (drivingType) {
        case KeyboardAnimationType.show:
          widget.showAnimationListener?.call(finalHeight, true);
          break;
        case KeyboardAnimationType.hide:
          widget.hideAnimationListener?.call(finalHeight, true);
          break;
      }
      _finishMetricsSequenceIfMatch(token);
    });
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

    _cancelAndroidMetricsSettleTimer();
    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _activeMetricsSequence = null;
    _activeSimulatedSequence = null;

    /// 创建新的
    _showListener = (double former, double newer, int time) {
      widget.showListener?.call(former, newer, time);
      if (widget.showAnimationListener == null) {
        return;
      }
      _showAnimation(newer);
    };
    _hideListener = (double former, double newer, int time) {
      widget.hideListener?.call(former, newer, time);
      if (widget.hideAnimationListener == null) {
        return;
      }
      _hideAnimation(newer);
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
    _cancelAndroidMetricsSettleTimer();
    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _activeMetricsSequence = null;
    _activeSimulatedSequence = null;
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
    _cancelAndroidMetricsSettleTimer();
    return token;
  }

  /// 结束当前 mediaQuery 动画序列，仅当 token 仍然有效时才执行。
  void _finishMetricsSequenceIfMatch(int token) {
    if (_activeMetricsSequence != token) {
      return;
    }
    _cancelAndroidMetricsSettleTimer();
    _activeMetricsSequence = null;
    _metricsDrivingType = null;
    _metricsTargetHeight = null;
    _showAnimationController?.stop();
    _hideAnimationController?.stop();
  }

  /// 开启一段新的 simulated 动画序列，并返回其 token。
  int _beginSimulatedSequence() {
    _simulatedSequence += 1;
    final int token = _simulatedSequence;
    _activeSimulatedSequence = token;
    return token;
  }

  /// 判断两个高度是否足够接近，避免浮点误差导致无法收尾。
  bool _isCloseTo(double a, double b, [double epsilon = 0.5]) {
    return (a - b).abs() <= epsilon;
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘展开动画。
  ///
  /// 当前实现以 [_formerHeight] / 当前 [_bottomPadding] 为衔接起点。
  void _showAnimation(double newer) {
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

      // Android存在很多特殊情况.
      if (_isAndroid) {
        _restartAndroidMetricsSettleTimer(token);
      }

      // iOS/其他平台：如果当前已经等于目标值，直接完成。
      // Android：不信任原生目标值，交给 didChangeMetrics + settle timer 收尾。
      if (!_isAndroid && _isCloseTo(_bottomPadding, newer)) {
        final double finalHeight = _resolveFinalHeight(newer);
        _formerHeight = finalHeight;
        _bottomPadding = finalHeight;
        widget.showAnimationListener?.call(finalHeight, true);
        _finishMetricsSequenceIfMatch(token);
      }
      return;
    }

    final int token = _beginSimulatedSequence();

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
        if (!mounted) {
          return;
        }
        if (widget.animationMode != KeyboardAnimationMode.simulated) {
          return;
        }
        if (_activeSimulatedSequence != token) {
          return;
        }
        _formerHeight = newer;
        widget.showAnimationListener?.call(newer, true);
      });
    }
  }

  /// 从 [_formerHeight] 插值到 [newer]，驱动键盘收起动画。
  ///
  /// 当前实现以 [_formerHeight] / 当前 [_bottomPadding] 为衔接起点。
  void _hideAnimation(double newer) {
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

      if (_isAndroid) {
        _restartAndroidMetricsSettleTimer(token);
      }

      // iOS/其他平台：如果当前已经等于目标值，直接完成。
      // Android：不信任原生目标值，交给 didChangeMetrics + settle timer 收尾。
      if (!_isAndroid && _isCloseTo(_bottomPadding, newer)) {
        final double finalHeight = _resolveFinalHeight(newer);
        _formerHeight = finalHeight;
        _bottomPadding = finalHeight;
        widget.hideAnimationListener?.call(finalHeight, true);
        _finishMetricsSequenceIfMatch(token);
      }
      return;
    }

    final int token = _beginSimulatedSequence();

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
        if (!mounted) {
          return;
        }
        if (widget.animationMode != KeyboardAnimationMode.simulated) {
          return;
        }
        if (_activeSimulatedSequence != token) {
          return;
        }
        _formerHeight = newer;
        widget.hideAnimationListener?.call(newer, true);
      });
    }
  }

  /// 系统窗口 metrics 变化时更新底部 inset（主要用于 mediaQuery 模式）。
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }

    // 所有 change 状态下，都先缓存最新 bottom inset。
    // 若 native 事件晚于 metrics 到达，后续会以当前这一帧的 _bottomPadding 作为起点继续。
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

    if (_isAndroid) {
      // Android：不信任原生目标值作为最终值。
      // 每次 metrics 变化后重启稳定检测；一段时间内不再变化则结束。
      _restartAndroidMetricsSettleTimer(activeToken);
      return;
    }

    // iOS / 其他平台：仍以原生目标值为主，接近目标值时结束。
    if (_isCloseTo(_bottomPadding, targetHeight)) {
      final double finalHeight = _resolveFinalHeight(targetHeight);
      switch (drivingType) {
        case KeyboardAnimationType.show:
          _formerHeight = finalHeight;
          _bottomPadding = finalHeight;
          widget.showAnimationListener?.call(finalHeight, true);
          break;
        case KeyboardAnimationType.hide:
          _formerHeight = finalHeight;
          _bottomPadding = finalHeight;
          widget.hideAnimationListener?.call(finalHeight, true);
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
