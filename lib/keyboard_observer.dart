import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'keyboard_scroll.dart';
import 'dart:io';

class KeyboardObserveListenManager {
  //set channel
  static const MethodChannel _channel = MethodChannel('keyboard_observer');

  //eventChannel
  static const EventChannel _eventChannel =
      EventChannel('keyboard_observer_event');

  //listen state
  static bool _listenState = false;

  //show animation value listener
  static final List<KeyboardAnimationListener> _showAnimListeners = [];

  //hide animation value listener
  static final List<KeyboardAnimationListener> _hideAnimListeners = [];

  //show start listener
  static final List<KeyboardObserverListener> _showListeners = [];

  //hide start listener
  static final List<KeyboardObserverListener> _hideListeners = [];

  //add show animation listener
  static void addKeyboardShowAnimListener(
      KeyboardAnimationListener animationListener) {
    _showAnimListeners.add(animationListener);
    _channel.invokeMethod("openAnimListener");
    _checkListeners();
  }

  //add hide animation listener
  static void addKeyboardHideAnimListener(
      KeyboardAnimationListener animationListener) {
    _hideAnimListeners.add(animationListener);
    _channel.invokeMethod("openAnimListener");
    _checkListeners();
  }

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
  static void removeKeyboardShowAnimListener(
      KeyboardAnimationListener animationListener) {
    _showAnimListeners.remove(animationListener);
    //this is for ios
    if (_showAnimListeners.isEmpty && _hideAnimListeners.isEmpty) {
      _channel.invokeMethod("closeAnimListener");
    }
  }

  //remove hide listener
  static void removeKeyboardHideAnimListener(
      KeyboardAnimationListener animationListener) {
    _hideAnimListeners.remove(animationListener);
    //this is for ios
    if (_showAnimListeners.isEmpty && _hideAnimListeners.isEmpty) {
      _channel.invokeMethod("closeAnimListener");
    }
  }

  //remove show listener
  static void removeKeyboardShowListener(KeyboardObserverListener listener) {
    _showListeners.remove(listener);
  }

  //remove hide listener
  static void removeKeyboardHideListener(KeyboardObserverListener listener) {
    _hideListeners.remove(listener);
  }

  static double _formerPos = 0;

  //check listeners
  static void _checkListeners() {
    if (!_listenState) {
      _listenState = true;
      //set show channel
      _eventChannel
          .receiveBroadcastStream()
          .map((result) => result as Map)
          .listen((data) {
        //show animation
        if (data["type"] == 1) {
          double pos = double.parse(data["data"].toString());
          bool end = data["end"] as bool;
          if (_formerPos == pos && !end) {
            return;
          }
          _formerPos = pos;
          double newPos = pos.toDouble();
          for (int s = 0; s < _showAnimListeners.length; s++) {
            _showAnimListeners[s](newPos, end);
          }
        }
        //hide animation
        if (data["type"] == 0) {
          double pos = double.parse(data["data"].toString());
          bool end = data["end"] as bool;
          if (_formerPos == pos && !end) {
            return;
          }
          _formerPos = pos;
          double newPos = pos.toDouble();
          for (int s = 0; s < _hideAnimListeners.length; s++) {
            _hideAnimListeners[s](newPos, end);
          }
        }
        //show
        if (data["type"] == 2) {
          for (int s = 0; s < _showListeners.length; s++) {
            _showListeners[s](
                double.parse(data["former"].toString()),
                double.parse(data["newer"].toString()),
                int.parse(data["time"].toString()));
          }
        }
        //hide
        if (data["type"] == 3) {
          for (int s = 0; s < _hideListeners.length; s++) {
            _hideListeners[s](
                double.parse(data["former"].toString()),
                double.parse(data["newer"].toString()),
                int.parse(data["time"].toString()));
          }
        }
      });
    }
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

  //show anim listener(IOS)
  KeyboardAnimationListener? _showAnimIOSListener;

  //hide anim listener(IOS)
  KeyboardAnimationListener? _hideAnimIOSListener;

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

  ///使用原生的方式
  void _useNative() {
    if (Platform.isIOS) {
      //show
      _showListener ??= (double former, double newer, int time) {
        widget.showListener?.call(former, newer, time);
      };
      //hide
      _hideListener ??= (double former, double newer, int time) {
        widget.hideListener?.call(former, newer, time);
      };
      //show
      _showAnimIOSListener = (double value, bool end) {
        widget.showAnimationListener?.call(value, end);
      };
      //show
      _hideAnimIOSListener = (double value, bool end) {
        widget.hideAnimationListener?.call(value, end);
      };
      //show
      KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
      //hide
      KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);
      //show
      KeyboardObserveListenManager.addKeyboardShowAnimListener(
          _showAnimIOSListener!);
      //hide
      KeyboardObserveListenManager.addKeyboardHideAnimListener(
          _hideAnimIOSListener!);
    } else {
      _useSimulated();
    }
  }

  ///使用模拟的方式
  void _useSimulated() {
    //show
    _showListener ??= (double former, double newer, int time) {
      if (_ratio == null) {
        return;
      }
      double f = former / _ratio!;
      double n = newer / _ratio!;
      widget.showListener?.call(f, n, time);
      //check animation listener
      if (widget.showAnimationListener != null) {
        _showAnimation(f, n);
      }
    };
    //hide
    _hideListener ??= (double former, double newer, int time) {
      if (_ratio == null) {
        return;
      }
      double f = former / _ratio!;
      double n = newer / _ratio!;
      widget.hideListener?.call(f, n, time);
      //check animation listener
      if (widget.hideAnimationListener != null) {
        _hideAnimation(f, n);
      }
    };
    //show anim listener
    _showAnimListener ??= () {
      _formerHeight = _showAnim!.value;
      widget.showAnimationListener?.call(_formerHeight, false);
    };
    //hide anim listener
    _hideAnimListener ??= () {
      _formerHeight = _hideAnim!.value;
      widget.hideAnimationListener?.call(_formerHeight, false);
    };
    //just add two listener
    KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);
    _showAnimationController = AnimationController(
      duration: widget.durationShow ?? const Duration(milliseconds: 320),
      vsync: this,
    );
    _hideAnimationController = AnimationController(
      duration: widget.durationHide ?? const Duration(milliseconds: 320),
      vsync: this,
    );
  }

  ///使用系统自带的
  void _useMediaQuery() {
    //show
    _showListener ??= (double former, double newer, int time) {
      if (_ratio != null) {
        double f = former / _ratio!;
        double n = newer / _ratio!;
        widget.showListener?.call(f, n, time);
        //check animation listener
        if (widget.showAnimationListener != null) {
          _showAnimation(f, n);
        }
      }
    };
    //hide
    _hideListener ??= (double former, double newer, int time) {
      if (_ratio != null) {
        double f = former / _ratio!;
        double n = newer / _ratio!;
        widget.hideListener?.call(f, n, time);
        //check animation listener
        if (widget.hideAnimationListener != null) {
          _hideAnimation(f, n);
        }
      }
    };
    //show anim listener
    _showAnimListener ??= () {
      widget.showAnimationListener?.call(
        MediaQuery.of(context).padding.bottom,
        false,
      );
    };
    //hide anim listener
    _hideAnimListener ??= () {
      widget.hideAnimationListener?.call(
        MediaQuery.of(context).padding.bottom,
        false,
      );
    };
    //just add two listener
    KeyboardObserveListenManager.addKeyboardShowListener(_showListener!);
    KeyboardObserveListenManager.addKeyboardHideListener(_hideListener!);
    _showAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _hideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
  }

  //animation
  void _initListeners() {
    if (kIsWeb) {
      return;
    }
    switch (widget.animationMode) {
      case KeyboardAnimationMode.native:
        _useNative();
        break;
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
    switch (widget.animationMode) {
      case KeyboardAnimationMode.native:
        if (Platform.isIOS) {
          KeyboardObserveListenManager.removeKeyboardShowAnimListener(
              _showAnimIOSListener!);
          KeyboardObserveListenManager.removeKeyboardHideAnimListener(
              _hideAnimIOSListener!);
          KeyboardObserveListenManager.removeKeyboardShowListener(
              _showListener!);
          KeyboardObserveListenManager.removeKeyboardHideListener(
              _hideListener!);
        } else {
          KeyboardObserveListenManager.removeKeyboardShowListener(
              _showListener!);
          KeyboardObserveListenManager.removeKeyboardHideListener(
              _hideListener!);
          _showAnimationController?.dispose();
          _hideAnimationController?.dispose();
        }
        break;
      case KeyboardAnimationMode.simulated:
      case KeyboardAnimationMode.mediaQuery:
        KeyboardObserveListenManager.removeKeyboardShowListener(_showListener!);
        KeyboardObserveListenManager.removeKeyboardHideListener(_hideListener!);
        _showAnimationController?.dispose();
        _hideAnimationController?.dispose();
        break;
    }
  }

  //remove
  @override
  void dispose() {
    _disposeListeners();
    super.dispose();
  }

  //show animation
  void _showAnimation(double former, double newer) {
    _hideAnim?.removeListener(_hideAnimListener!);
    _showAnim?.removeListener(_showAnimListener!);
    //stop former
    _hideAnimationController!.stop();
    _showAnimationController!.stop();
    _hideAnimationController!.reset();
    _showAnimationController!.reset();
    //_showAnim
    _showAnim = Tween<double>(begin: _formerHeight, end: newer).animate(
      CurvedAnimation(
        parent: _showAnimationController!,
        curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      ),
    );
    _showAnim?.addListener(_showAnimListener!);
    //start animation
    _showAnimationController!.forward().then((value) {
      widget.showAnimationListener?.call(_showAnim?.value ?? 0, true);
    });
  }

  //hide anim
  void _hideAnimation(double former, double newer) {
    _hideAnim?.removeListener(_hideAnimListener!);
    _showAnim?.removeListener(_showAnimListener!);
    //stop former
    _hideAnimationController!.stop();
    _showAnimationController!.stop();
    _showAnimationController!.reset();
    _hideAnimationController!.reset();
    //hide
    _hideAnim = Tween<double>(begin: _formerHeight, end: newer).animate(
      CurvedAnimation(
        parent: _hideAnimationController!,
        curve: widget.curveShow ?? const Cubic(0.34, 0.84, 0.12, 1.00),
      ),
    );
    _hideAnim?.addListener(_hideAnimListener!);
    //hide animation
    _hideAnimationController!.forward().then((value) {
      widget.hideAnimationListener?.call(_hideAnim?.value ?? 0, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    //Android
    if (Platform.isAndroid) {
      _ratio ??= MediaQuery.of(context).devicePixelRatio;
    }
    if (Platform.isIOS) {
      _ratio ??= 1;
    }
    return widget.child ?? const SizedBox();
  }
}
