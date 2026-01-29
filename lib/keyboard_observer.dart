import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'keyboard_scroll.dart';
import 'dart:io';

class KeyboardObserveListenManager {
  //eventChannel
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  //listen state
  static bool _listenState = false;

  //show start listener
  static final List<KeyboardObserverListener> _showListeners = [];

  //hide start listener
  static final List<KeyboardObserverListener> _hideListeners = [];

  //add show listener
  static void addKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.add(listener);
    _checkListeners();
  }

  //add hide listener
  static void addKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.add(listener);
    _checkListeners();
  }

  //remove show listener
  static void removeKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.remove(listener);
  }

  //remove hide listener
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
        for (int s = 0; s < _showListeners.length; s++) {
          _showListeners[s](
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
      //软键盘收起
      if (data["type"] == 3) {
        for (int s = 0; s < _hideListeners.length; s++) {
          _hideListeners[s](
            double.parse(data["former"].toString()),
            double.parse(data["newer"].toString()),
            int.parse(data["time"].toString()),
          );
        }
      }
    });
  }
}

//start listener
typedef KeyboardObserverListener = Function(
    double former, double newer, int time);

//animation value listener
typedef KeyboardAnimationListener = Function(double bottomInsets, bool end);

//observer
class KeyboardObserver extends StatefulWidget {
  //child
  final Widget? child;

  //curve show
  final Curve? curveShow;

  //animation duration show
  final Duration? durationShow;

  //curve
  final Curve? curveHide;

  //animation duration hide
  final Duration? durationHide;

  //if true , we will use ios system animation
  final KeyboardAnimationMode animationMode;

  //listener
  final KeyboardObserverListener? showListener;

  //hide listener
  final KeyboardObserverListener? hideListener;

  //animation listener
  final KeyboardAnimationListener? showAnimationListener;

  //animation listener
  final KeyboardAnimationListener? hideAnimationListener;

  //add key
  const KeyboardObserver({
    Key? key,
    this.child,
    this.showListener,
    this.hideListener,
    this.curveShow,
    this.durationShow,
    this.curveHide,
    this.durationHide,
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
    with TickerProviderStateMixin {
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

  //ratio
  double? _ratio;

  //init state
  @override
  void initState() {
    _initListeners();
    super.initState();
  }

  @override
  void didUpdateWidget(KeyboardObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hideAnimationListener != null ||
        widget.showAnimationListener != null) {
      _initListeners();
    }
  }

  ///使用模拟的方式
  void _useSimulated() {
    ///hide or show listener
    _showListener ??= (double former, double newer, int time) {
      if (_ratio == null) {
        return;
      }
      double f = former / _ratio!;
      double n = newer / _ratio!;
      widget.showListener?.call(f, n, time);
      if (widget.showAnimationListener != null) {
        _showAnimation(f, n);
      }
    };
    _hideListener ??= (double former, double newer, int time) {
      if (_ratio == null) {
        return;
      }
      double f = former / _ratio!;
      double n = newer / _ratio!;
      widget.hideListener?.call(f, n, time);
      if (widget.hideAnimationListener != null) {
        _hideAnimation(f, n);
      }
    };

    ///if showAnimationListener !=null or hideAnimationListener!=null ,open animation
    if (widget.showAnimationListener != null ||
        widget.hideAnimationListener != null) {
      ///hide or show animation listener
      _showAnimListener ??= () {
        _formerHeight = _showAnim!.value;
        widget.showAnimationListener?.call(_formerHeight, false);
      };
      _hideAnimListener ??= () {
        _formerHeight = _hideAnim!.value;
        widget.hideAnimationListener?.call(_formerHeight, false);
      };
      _showAnimationController = AnimationController(
        duration: widget.durationShow ?? const Duration(milliseconds: 380),
        vsync: this,
      );
      _hideAnimationController = AnimationController(
        duration: widget.durationHide ?? const Duration(milliseconds: 380),
        vsync: this,
      );
      KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
      KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);
    }
  }

  ///使用系统自带的
  void _useMediaQuery() {
    ///hide or show listener
    _showListener ??= (double former, double newer, int time) {
      if (_ratio != null) {
        double f = former / _ratio!;
        double n = newer / _ratio!;
        widget.showListener?.call(f, n, time);
        if (widget.showAnimationListener != null) {
          _showAnimation(f, n);
        }
      }
    };
    _hideListener ??= (double former, double newer, int time) {
      if (_ratio != null) {
        double f = former / _ratio!;
        double n = newer / _ratio!;
        widget.hideListener?.call(f, n, time);
        if (widget.hideAnimationListener != null) {
          _hideAnimation(f, n);
        }
      }
    };

    ///if showAnimationListener !=null or hideAnimationListener!=null ,open animation
    _showAnimListener ??= () {
      widget.showAnimationListener
          ?.call(MediaQuery.of(context).padding.bottom, false);
    };
    _hideAnimListener ??= () {
      widget.hideAnimationListener
          ?.call(MediaQuery.of(context).padding.bottom, false);
    };
    _showAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _hideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);
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
    KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
    _showAnimationController?.dispose();
    _hideAnimationController?.dispose();
    _showAnimationController = null;
    _hideAnimationController = null;
  }

  //remove
  @override
  void dispose() {
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
      _showAnim = Tween<double>(begin: _formerHeight, end: newer)
          .animate(CurvedAnimation(
        parent: _showAnimationController!,
        curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      ));
      _showAnim?.addListener(_showAnimListener!);
      _showAnimationController?.forward().then((value) {
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
      _hideAnim = Tween<double>(begin: _formerHeight, end: newer)
          .animate(CurvedAnimation(
        parent: _hideAnimationController!,
        curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      ));
      _hideAnim?.addListener(_hideAnimListener!);
      _hideAnimationController?.forward().then((value) {
        widget.hideAnimationListener?.call(_hideAnim?.value ?? 0, true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      _ratio ??= MediaQuery.of(context).devicePixelRatio;
    } else if (Platform.isIOS) {
      _ratio ??= 1;
    } else {
      _ratio ??= 1;
    }
    return widget.child ?? const SizedBox();
  }
}
