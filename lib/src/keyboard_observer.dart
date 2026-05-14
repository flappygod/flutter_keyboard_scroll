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

  //eventChannel
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  //listen state
  static bool _listenState = false;

  //show start listener
  static final Set<KeyboardObserverListener> _showListeners = {};

  //hide start listener
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

  //check listeners
  static void _checkListeners() {
    if (_listenState) {
      return;
    }
    _listenState = true;
    _eventChannel
        .receiveBroadcastStream()
        .map((result) => result as Map)
        .listen((data) {
      //软键盘弹出
      if (data["type"] == 2) {
        for (KeyboardObserverListener listener in _showListeners) {
          listener(
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
      //软键盘收起
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

//state
class _KeyboardObserverState extends State<KeyboardObserver>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  //show animation controller
  AnimationController? _showAnimationController;

  //hide  animation controller
  AnimationController? _hideAnimationController;

  //former height
  double _formerHeight = 0;

  //show anim listener
  VoidCallback? _showAnimListener;

  //hide anim listener
  VoidCallback? _hideAnimListener;

  //show listener
  KeyboardObserverListener? _showListener;

  //hide listener
  KeyboardObserverListener? _hideListener;

  //show anim
  Animation<double>? _showAnim;

  //hide anim
  Animation<double>? _hideAnim;

  //bottom padding
  double _bottomPadding = 0;

  //type
  KeyboardAnimationType? _mediaAnimType;
  double? _mediaAnimEndValue;

  //init state
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initListeners();
  }

  @override
  void didUpdateWidget(KeyboardObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationShow != oldWidget.durationShow ||
        widget.durationHide != oldWidget.durationHide ||
        widget.animationMode != oldWidget.animationMode) {
      _initListeners();
    }
  }

  ///使用模拟的方式
  void _useSimulated() {
    _mediaAnimType = null;
    _mediaAnimEndValue = null;

    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }

    ///hide or show listener
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

    ///no animation need
    if (widget.showAnimationListener == null &&
        widget.hideAnimationListener == null) {
      return;
    }

    ///hide or show animation listener
    _showAnimListener ??= () {
      if (_formerHeight != _showAnim!.value) {
        _formerHeight = _showAnim!.value;
        widget.showAnimationListener?.call(_formerHeight, false);
      }
    };
    _hideAnimListener ??= () {
      if (_formerHeight != _hideAnim!.value) {
        _formerHeight = _hideAnim!.value;
        widget.hideAnimationListener?.call(_formerHeight, false);
      }
    };
    if (_showAnimationController != null) {
      _showAnimationController!.duration = widget.durationShow;
    } else {
      _showAnimationController = AnimationController(
        duration: widget.durationShow,
        vsync: this,
      );
    }
    if (_hideAnimationController != null) {
      _hideAnimationController!.duration = widget.durationHide;
    } else {
      _hideAnimationController = AnimationController(
        duration: widget.durationHide,
        vsync: this,
      );
    }
  }

  ///使用系统自带的
  void _useMediaQuery() {
    if (_showListener != null) {
      KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    }
    if (_hideListener != null) {
      KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    }

    ///hide or show listener
    _showListener = (double former, double newer, int time) {
      widget.showListener?.call(former, newer, time);
      _mediaAnimEndValue = newer;
      _mediaAnimType = KeyboardAnimationType.show;
    };
    _hideListener = (double former, double newer, int time) {
      widget.hideListener?.call(former, newer, time);
      _mediaAnimEndValue = newer;
      _mediaAnimType = KeyboardAnimationType.hide;
    };
    KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);

    _showAnimationController?.dispose();
    _hideAnimationController?.dispose();
    _showAnimationController = null;
    _hideAnimationController = null;
  }

  ///animation
  void _initListeners() {
    if (kIsWeb) {
      return;
    }
    switch (widget.animationMode) {
      case KeyboardAnimationMode.simulated:
        _useSimulated();
        break;
      case KeyboardAnimationMode.mediaQuery:
        _useMediaQuery();
        break;
    }
  }

  //dispose
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

  //remove
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeListeners();
    super.dispose();
  }

  ///show animation
  void _showAnimation(double former, double newer) {
    if (_hideAnimListener != null) {
      _hideAnim?.removeListener(_hideAnimListener!);
    }
    if (_showAnimListener != null) {
      _showAnim?.removeListener(_showAnimListener!);
    }
    //stop former
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _hideAnimationController?.reset();
    _showAnimationController?.reset();
    //start animation
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

  ///hide animation
  void _hideAnimation(double former, double newer) {
    if (_hideAnimListener != null) {
      _hideAnim?.removeListener(_hideAnimListener!);
    }
    if (_showAnimListener != null) {
      _showAnim?.removeListener(_showAnimListener!);
    }
    //stop former
    _hideAnimationController?.stop();
    _showAnimationController?.stop();
    _showAnimationController?.reset();
    _hideAnimationController?.reset();
    //start animation
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

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }

    ///这里是在build之外收到变化
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;

    switch (_mediaAnimType) {
      case KeyboardAnimationType.show:
        if (_bottomPadding != inset) {
          _bottomPadding = inset;
          widget.showAnimationListener?.call(_bottomPadding, false);
          final end = _mediaAnimEndValue;
          if (end != null && (_bottomPadding - end).abs() < 0.1) {
            _mediaAnimType = null;
            widget.showAnimationListener?.call(_bottomPadding, true);
          }
        }
        break;
      case KeyboardAnimationType.hide:
        if (_bottomPadding != inset) {
          _bottomPadding = inset;
          widget.hideAnimationListener?.call(_bottomPadding, false);
          final end = _mediaAnimEndValue;
          if (end != null && (_bottomPadding - end).abs() < 0.1) {
            _mediaAnimType = null;
            widget.hideAnimationListener?.call(_bottomPadding, true);
          }
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}
