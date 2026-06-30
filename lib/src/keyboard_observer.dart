///软键盘事件与 [KeyboardObserver] 动画相关的类型与工具。
///
///在 Android/iOS 上通过 [EventChannel] 接收原生键盘高度变化；
///Web 上当前不接入原生键盘事件。
library keyboard_observer;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'keyboard_scroll.dart';

///与底部 inset 动画阶段对应的键盘动画类型。
enum KeyboardAnimationType {
  ///键盘展开或底部安全区增大过程中。
  show,

  ///键盘收起或底部安全区减小过程中。
  hide,
}

///键盘显示或隐藏时触发。
///
///- [former]：上一阶段高度
///- [newer]：当前目标高度
///- [time]：原生侧给出的动画时长（毫秒）
typedef KeyboardObserverListener = void Function(
  double former,
  double newer,
  int time,
);

///键盘动画过程中底部 inset 回调。
///
///- [bottomInsets]：当前底部 inset
///- [end]：
/// - `false` 表示动画进行中
/// - `true` 表示本段动画结束
typedef KeyboardAnimationListener = void Function(
  double bottomInsets,
  bool end,
);

///注册/注销原生键盘显示与隐藏监听，并向 Dart 侧广播事件。
///
///这是一个全局静态管理器：
///- 整个进程只维护一个 EventChannel 订阅
///- 多个 [KeyboardObserver] 可同时注册监听
class KeyboardObserveListenManager {
  KeyboardObserveListenManager._();

  ///与 Android/iOS 原生侧通信的广播通道。
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  ///是否已建立 EventChannel 订阅。
  static bool _listenState = false;

  ///键盘显示监听集合（原生 type == 2）。
  static final Set<KeyboardObserverListener> _showListeners = {};

  ///键盘隐藏监听集合（原生 type == 3）。
  static final Set<KeyboardObserverListener> _hideListeners = {};

  ///EventChannel 订阅对象。
  static StreamSubscription? _subscription;

  ///注册键盘显示监听。
  static void addKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.add(listener);
    _checkListeners();
  }

  ///注册键盘隐藏监听。
  static void addKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.add(listener);
    _checkListeners();
  }

  ///移除键盘显示监听。
  static void removeKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.remove(listener);
    _checkDispose();
  }

  ///移除键盘隐藏监听。
  static void removeKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.remove(listener);
    _checkDispose();
  }

  ///在首次有监听注册时建立 EventChannel 订阅。
  ///
  ///原生侧约定：
  ///- type == 2：show
  ///- type == 3：hide
  static void _checkListeners() {
    if (_listenState) {
      return;
    }

    _listenState = true;
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .map((result) => result as Map)
        .listen((data) {
      final type = int.tryParse(data['type'].toString());
      final former = double.tryParse(data['former'].toString());
      final newer = double.tryParse(data['newer'].toString());
      final time = int.tryParse(data['time'].toString());

      //数据异常时直接忽略，避免抛出格式错误。
      if (type == null || former == null || newer == null || time == null) {
        return;
      }

      if (type == 2) {
        for (final listener in _showListeners.toList()) {
          listener(former, newer, time);
        }
      } else if (type == 3) {
        for (final listener in _hideListeners.toList()) {
          listener(former, newer, time);
        }
      }
    });
  }

  ///当没有任何监听时，取消 EventChannel 订阅。
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

///包裹子组件以监听软键盘显示/隐藏，并可选择模拟或跟随系统 inset 动画。
class KeyboardObserver extends StatefulWidget {
  ///子组件。
  final Widget? child;

  ///键盘展开动画曲线；为 null 时使用默认 Cubic。
  final Curve? curveShow;

  ///键盘展开动画时长。
  final Duration durationShow;

  ///键盘收起动画曲线；为 null 时使用默认 Cubic。
  final Curve? curveHide;

  ///键盘收起动画时长。
  final Duration durationHide;

  ///动画驱动方式：
  ///- [KeyboardAnimationMode.simulated]：内部模拟插值
  ///- [KeyboardAnimationMode.mediaQuery]：跟随系统窗口 metrics 变化
  final KeyboardAnimationMode animationMode;

  ///原生 show 事件回调。
  final KeyboardObserverListener? showListener;

  ///原生 hide 事件回调。
  final KeyboardObserverListener? hideListener;

  ///键盘展开过程中的 inset 动画回调。
  final KeyboardAnimationListener? showAnimationListener;

  ///键盘收起过程中的 inset 动画回调。
  final KeyboardAnimationListener? hideAnimationListener;

  const KeyboardObserver({
    super.key,
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
  });

  @override
  State<KeyboardObserver> createState() => _KeyboardObserverState();
}

///[KeyboardObserver] 的状态实现。
///
///设计原则：
///
///1. simulated 模式
///  - 过程值：由 AnimationController + Tween 驱动
///  - 结束值：由 controller 完成时回调
///
///2. mediaQuery 模式
///  - 过程值：由 [didChangeMetrics] 直接驱动
///  - 结束值：仍由 controller 完成时回调
class _KeyboardObserverState extends State<KeyboardObserver>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  ///show 方向控制器。
  AnimationController? _showController;

  ///hide 方向控制器。
  AnimationController? _hideController;

  ///show 方向曲线动画包装。
  CurvedAnimation? _showCurve;

  ///hide 方向曲线动画包装。
  CurvedAnimation? _hideCurve;

  ///simulated 模式下的 show 高度动画。
  Animation<double>? _showAnim;

  ///simulated 模式下的 hide 高度动画。
  Animation<double>? _hideAnim;

  ///simulated 模式下 show 动画逐帧监听。
  VoidCallback? _showTick;

  ///simulated 模式下 hide 动画逐帧监听。
  VoidCallback? _hideTick;

  ///注册到全局管理器的原生 show 监听闭包。
  KeyboardObserverListener? _nativeShowListener;

  ///注册到全局管理器的原生 hide 监听闭包。
  KeyboardObserverListener? _nativeHideListener;

  ///最近一次已分发给外部的高度。
  ///
  ///作用：
  ///- simulated 模式下作为下一段 Tween 的 begin
  ///- mediaQuery 模式下用于避免重复通知相同值
  double _formerHeight = 0;

  ///最近一次从系统窗口 metrics 读取到的底部 inset。
  double _bottomPadding = 0;

  ///mediaQuery 模式下当前正在进行的动画方向。
  ///
  ///只有先收到原生 show/hide 事件，metrics 变化才会被视为对应动画过程。
  KeyboardAnimationType? _currentMediaAnimationType;

  ///动画 token，用于防止旧动画完成回调串扰。
  ///
  ///每次重置动画状态或释放资源时递增；
  ///controller 完成时只有 token 匹配才允许发出 end=true。
  int _animationToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    //绑定原生 show/hide 事件。
    _bindNativeListeners();

    //根据是否存在动画回调决定是否创建控制器。
    _ensureControllersIfNeeded();

    //初始化 simulated 模式下的逐帧监听闭包。
    _ensureTickListeners();
  }

  @override
  void didUpdateWidget(covariant KeyboardObserver oldWidget) {
    super.didUpdateWidget(oldWidget);

    final modeChanged = widget.animationMode != oldWidget.animationMode;
    final animationListenerChanged =
        widget.showAnimationListener != oldWidget.showAnimationListener ||
            widget.hideAnimationListener != oldWidget.hideAnimationListener;

    //动画模式或动画回调发生变化时，重置内部动画状态，
    //避免旧模式/旧监听残留。
    if (modeChanged || animationListenerChanged) {
      _resetAnimationState();
      _ensureControllersIfNeeded();
      _ensureTickListeners();
      return;
    }

    //仅 simulated 模式下同步 duration。
    if (widget.animationMode == KeyboardAnimationMode.simulated &&
        (widget.durationShow != oldWidget.durationShow ||
            widget.durationHide != oldWidget.durationHide)) {
      _syncControllerDurations();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unbindNativeListeners();
    _disposeAnimationResources();
    super.dispose();
  }

  ///当前是否至少存在一个动画过程回调。
  bool get _needsAnimationCallbacks =>
      widget.showAnimationListener != null ||
      widget.hideAnimationListener != null;

  ///读取当前窗口底部 inset（逻辑像素）。
  double _readBottomInset() {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  ///绑定原生 show/hide 监听。
  void _bindNativeListeners() {
    //Web 当前不接入原生 EventChannel。
    if (kIsWeb) {
      return;
    }

    //先移除旧监听，避免重复注册。
    _unbindNativeListeners();

    _nativeShowListener = (double former, double newer, int time) {
      //原生 show 事件透传给外部。
      widget.showListener?.call(former, newer, time);

      //若外部未监听 show 动画过程，则无需启动内部动画逻辑。
      if (widget.showAnimationListener == null) {
        return;
      }

      _startKeyboardAnimation(
        type: KeyboardAnimationType.show,
        target: newer,
      );
    };

    _nativeHideListener = (double former, double newer, int time) {
      //原生 hide 事件透传给外部。
      widget.hideListener?.call(former, newer, time);

      //若外部未监听 hide 动画过程，则无需启动内部动画逻辑。
      if (widget.hideAnimationListener == null) {
        return;
      }

      _startKeyboardAnimation(
        type: KeyboardAnimationType.hide,
        target: newer,
      );
    };

    KeyboardObserveListenManager.addKeyboardShowListener(_nativeShowListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_nativeHideListener!);
  }

  ///解绑原生 show/hide 监听。
  void _unbindNativeListeners() {
    final show = _nativeShowListener;
    final hide = _nativeHideListener;

    if (show != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(show);
    }
    if (hide != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(hide);
    }

    _nativeShowListener = null;
    _nativeHideListener = null;
  }

  ///根据当前是否需要动画回调，创建或释放控制器。
  void _ensureControllersIfNeeded() {
    if (!_needsAnimationCallbacks) {
      _disposeAnimationResources();
      return;
    }

    _showController ??= AnimationController(
      duration: widget.durationShow,
      vsync: this,
    );
    _hideController ??= AnimationController(
      duration: widget.durationHide,
      vsync: this,
    );

    _syncControllerDurations();
  }

  ///同步 simulated 模式下控制器时长。
  void _syncControllerDurations() {
    _showController?.duration = widget.durationShow;
    _hideController?.duration = widget.durationHide;
  }

  ///初始化 simulated 模式下的逐帧监听闭包。
  ///
  ///注意：
  ///- mediaQuery 模式的过程值不走这里
  ///- mediaQuery 模式由 didChangeMetrics 直接驱动
  void _ensureTickListeners() {
    _showTick ??= () {
      if (widget.animationMode != KeyboardAnimationMode.simulated) {
        return;
      }

      final value = _showAnim?.value;
      if (value == null || value == _formerHeight) {
        return;
      }

      _formerHeight = value;
      widget.showAnimationListener?.call(value, false);
    };

    _hideTick ??= () {
      if (widget.animationMode != KeyboardAnimationMode.simulated) {
        return;
      }

      final value = _hideAnim?.value;
      if (value == null || value == _formerHeight) {
        return;
      }

      _formerHeight = value;
      widget.hideAnimationListener?.call(value, false);
    };
  }

  ///从当前动画对象上移除逐帧监听。
  void _detachAnimationListeners() {
    final showTick = _showTick;
    final hideTick = _hideTick;

    if (showTick != null) {
      _showAnim?.removeListener(showTick);
    }
    if (hideTick != null) {
      _hideAnim?.removeListener(hideTick);
    }
  }

  ///重置当前动画状态，但不销毁 tick 闭包本身。
  ///
  ///用于：
  ///- 模式切换
  ///- 动画回调切换
  ///- 启动新动画前清理旧动画
  void _resetAnimationState() {
    _detachAnimationListeners();

    _showController?.stop();
    _hideController?.stop();
    _showController?.reset();
    _hideController?.reset();

    _showCurve?.dispose();
    _hideCurve?.dispose();
    _showCurve = null;
    _hideCurve = null;

    _showAnim = null;
    _hideAnim = null;

    _currentMediaAnimationType = null;

    //递增 token，使旧动画完成回调失效。
    _animationToken++;
  }

  ///释放动画相关资源。
  void _disposeAnimationResources() {
    _detachAnimationListeners();

    _showCurve?.dispose();
    _hideCurve?.dispose();
    _showCurve = null;
    _hideCurve = null;

    _showAnim = null;
    _hideAnim = null;

    _showController?.dispose();
    _hideController?.dispose();
    _showController = null;
    _hideController = null;

    _currentMediaAnimationType = null;

    //递增 token，使所有旧完成回调失效。
    _animationToken++;
  }

  ///根据动画类型获取对应的外部动画回调。
  KeyboardAnimationListener? _listenerOf(KeyboardAnimationType type) {
    switch (type) {
      case KeyboardAnimationType.show:
        return widget.showAnimationListener;
      case KeyboardAnimationType.hide:
        return widget.hideAnimationListener;
    }
  }

  ///根据动画类型获取对应控制器。
  AnimationController? _controllerOf(KeyboardAnimationType type) {
    switch (type) {
      case KeyboardAnimationType.show:
        return _showController;
      case KeyboardAnimationType.hide:
        return _hideController;
    }
  }

  ///根据动画类型获取对应曲线。
  Curve _curveOf(KeyboardAnimationType type) {
    switch (type) {
      case KeyboardAnimationType.show:
        return widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00);
      case KeyboardAnimationType.hide:
        return widget.curveHide ?? const Cubic(0.34, 0.84, 0.12, 1.00);
    }
  }

  ///保存对应方向的曲线动画对象。
  void _setCurveOf(KeyboardAnimationType type, CurvedAnimation curve) {
    switch (type) {
      case KeyboardAnimationType.show:
        _showCurve?.dispose();
        _showCurve = curve;
        break;
      case KeyboardAnimationType.hide:
        _hideCurve?.dispose();
        _hideCurve = curve;
        break;
    }
  }

  ///保存对应方向的高度动画对象。
  void _setAnimOf(KeyboardAnimationType type, Animation<double> anim) {
    switch (type) {
      case KeyboardAnimationType.show:
        _showAnim = anim;
        break;
      case KeyboardAnimationType.hide:
        _hideAnim = anim;
        break;
    }
  }

  ///获取对应方向的高度动画对象。
  Animation<double>? _animOf(KeyboardAnimationType type) {
    switch (type) {
      case KeyboardAnimationType.show:
        return _showAnim;
      case KeyboardAnimationType.hide:
        return _hideAnim;
    }
  }

  ///获取对应方向的逐帧监听闭包。
  VoidCallback? _tickOf(KeyboardAnimationType type) {
    switch (type) {
      case KeyboardAnimationType.show:
        return _showTick;
      case KeyboardAnimationType.hide:
        return _hideTick;
    }
  }

  ///启动一段键盘动画。
  ///
  ///- simulated 模式：
  /// 使用 controller + tween 驱动过程值与结束值
  ///
  ///- mediaQuery 模式：
  /// 过程值由 didChangeMetrics 驱动；
  /// 这里只负责记录当前方向，并在 controller 完成时发出 end=true
  void _startKeyboardAnimation({
    required KeyboardAnimationType type,
    required double target,
  }) {
    final listener = _listenerOf(type);
    if (listener == null) {
      return;
    }

    //启动新动画前，先清理旧动画状态。
    _resetAnimationState();

    //记录当前动画 token。
    //若后续又有新动画启动，旧 token 对应的完成回调会自动失效。
    final token = _animationToken;

    //mediaQuery 模式：
    //中间值不由 controller 驱动，而是由 didChangeMetrics 直接驱动。
    if (widget.animationMode == KeyboardAnimationMode.mediaQuery) {
      _currentMediaAnimationType = type;

      //Android 上可能出现 didChangeMetrics 先于原生 show/hide 事件到达，
      //导致首个 metrics 变化未被分发。
      //因此在动画启动时，主动以当前缓存的 bottomPadding 先补发一次过程值。
      if (_formerHeight != _bottomPadding) {
        _formerHeight = _bottomPadding;
        listener(_bottomPadding, false);
      }

      final controller = _controllerOf(type);
      controller?.forward().then((_) {
        if (!mounted || token != _animationToken) {
          return;
        }
        if (_currentMediaAnimationType != type) {
          return;
        }

        _formerHeight = _bottomPadding;
        listener(_bottomPadding, true);
      });
      return;
    }

    //simulated 模式：
    //使用 Tween 从当前已分发高度平滑过渡到目标高度。
    _currentMediaAnimationType = null;

    final controller = _controllerOf(type);
    if (controller == null) {
      return;
    }

    final curve = CurvedAnimation(
      parent: controller,
      curve: _curveOf(type),
    );
    _setCurveOf(type, curve);

    final anim = Tween<double>(
      begin: _formerHeight,
      end: target,
    ).animate(curve);
    _setAnimOf(type, anim);

    final tick = _tickOf(type);
    if (tick != null) {
      anim.addListener(tick);
    }

    controller.forward().then((_) {
      //若组件已销毁，或期间有新动画启动，则忽略旧完成回调。
      if (!mounted || token != _animationToken) {
        return;
      }

      final endValue = _animOf(type)?.value ?? target;
      _formerHeight = endValue;
      listener(endValue, true);
    });
  }

  ///系统窗口 metrics 变化时更新底部 inset。
  ///
  ///这里保留为系统窗口监听入口：
  ///- 所有模式下都会先缓存最新的 [_bottomPadding]
  ///- 仅 mediaQuery 模式下，直接驱动过程值通知
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }

    //所有 metrics 变化都先缓存当前底部 inset。
    final inset = _readBottomInset();
    _bottomPadding = inset;

    //simulated 模式不依赖 metrics 驱动过程值。
    if (widget.animationMode != KeyboardAnimationMode.mediaQuery) {
      return;
    }

    //必须先收到原生 show/hide 事件，才认为当前 metrics 变化属于键盘动画过程。
    final type = _currentMediaAnimationType;
    if (type == null) {
      return;
    }

    //相同值不重复通知。
    if (_formerHeight == inset) {
      return;
    }

    _formerHeight = inset;
    _listenerOf(type)?.call(inset, false);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}
