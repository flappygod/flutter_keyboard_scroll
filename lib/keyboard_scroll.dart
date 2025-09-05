import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'keyboard_observer.dart';
import 'dart:math';

typedef TextFieldWrapperListener = void Function(FocusNode focusNode);

class TextFieldWrapper {
  TextFieldWrapper.fromKey({
    required this.focusNode,
    required this.focusKey,
    this.more = 0,
  }) {
    _focusDelegateListener = () {
      if (_focusChangedListener != null) {
        _focusChangedListener!(focusNode);
      }
    };
    focusNode.addListener(_focusDelegateListener!);
  }

  //focus delegate
  VoidCallback? _focusDelegateListener;

  //focus change listener
  TextFieldWrapperListener? _focusChangedListener;

  //key
  GlobalKey focusKey;

  //focus
  FocusNode focusNode;

  //bottom
  double _bottom = 0;

  //more
  double more;

  //refresh height
  void _refreshBottomHeight(double offsetHeight) {
    if (focusKey.currentContext != null) {
      final RenderBox renderBox =
          focusKey.currentContext!.findRenderObject() as RenderBox;
      var offset = renderBox.localToGlobal(Offset(0.0, renderBox.size.height));
      _bottom = MediaQuery.of(focusKey.currentContext!).size.height - offset.dy;
    }
  }

  //get bottom
  double getBottom() {
    return _bottom - more;
  }
}

//controller
class KeyboardScrollController {
  //当前的
  double _nowValue = 0;

  double _formerEnd = 0;

  bool _enabled = true;

  //wrapper
  final List<TextFieldWrapper> _wrappers = [];

  //listener
  TextFieldWrapperListener? _focusChangedListener;

  //set focus listener
  void setFocusListener(TextFieldWrapperListener listener) {
    _focusChangedListener = listener;
    for (int s = 0; s < _wrappers.length; s++) {
      _wrappers[s]._focusChangedListener = _focusChangedListener;
    }
  }

  //add text field wrapper
  void addTextFieldWrapper(TextFieldWrapper wrapper) {
    if (!_wrappers.contains(wrapper)) {
      wrapper._focusChangedListener = _focusChangedListener;
      _wrappers.add(wrapper);
    }
  }

  //remove text field wrapper
  void removeTextFieldWrapper(TextFieldWrapper wrapper) {
    if (_wrappers.contains(wrapper)) {
      wrapper._focusChangedListener = null;
      _wrappers.remove(wrapper);
    }
  }

  //refresh height
  void refreshHeights() {
    for (int s = 0; s < _wrappers.length; s++) {
      _wrappers[s]._refreshBottomHeight(_nowValue);
    }
  }

  //get bottom margin
  double? getBottomNeedMargin() {
    double? smaller;
    for (int s = 0; s < _wrappers.length; s++) {
      if (smaller == null || smaller > _wrappers[s].getBottom()) {
        if (_wrappers[s].focusNode.hasFocus) {
          smaller = _wrappers[s].getBottom();
        }
      }
    }
    return smaller;
  }

  //set enable
  void setEnable(bool flag) {
    _enabled = flag;
  }

  //get enable
  bool isEnable() {
    return _enabled;
  }
}

//type
enum KeyboardScrollType {
  //all view
  fitAllView,
  //each text
  fitAllTextField,
  //each text
  fitAddedTextField,
}

//KeyBroadScroll widget
class KeyboardScroll extends StatefulWidget {
  //close when tap
  final bool closeWhenTap;

  //close when move
  final bool closeWhenMove;

  //child
  final Widget child;

  //controller
  final KeyboardScrollController controller;

  //type
  final KeyboardScrollType fitType;

  //use ios system animation
  final bool useIOSSystemAnim;

  //listener
  final KeyboardObserverListener? showListener;

  //hide listener
  final KeyboardObserverListener? hideListener;

  //animation listener
  final KeyboardAnimationListener? showAnimationListener;

  //animation listener
  final KeyboardAnimationListener? hideAnimationListener;

  const KeyboardScroll({
    Key? key,
    required this.controller,
    required this.child,
    this.closeWhenTap = false,
    this.closeWhenMove = false,
    this.useIOSSystemAnim = false,
    this.fitType = KeyboardScrollType.fitAddedTextField,
    this.showListener,
    this.hideListener,
    this.showAnimationListener,
    this.hideAnimationListener,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _KeyboardScrollState();
  }
}

//state
class _KeyboardScrollState extends State<KeyboardScroll>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  //out animation
  AnimationController? outController;

  //int animation
  AnimationController? inController;

  //out animation
  Animation<double>? inAnimation;

  //int animation
  Animation<double>? outAnimation;

  //in anim listener
  VoidCallback? _inListener;

  //out anim listener
  VoidCallback? _outListener;

  //current keyboard height
  double currentKeyboardHeight = 0;

  //check moved or not
  bool isMoved = false;

  //position
  Offset? position;

  //global key
  final GlobalKey _globalKey = GlobalKey();

  //bottom margin
  double _distanceToBottom = 0;

  @override
  void initState() {
    super.initState();
    initOutAnim();
    initInAnim();
    WidgetsBinding.instance.addPostFrameCallback((callback) {
      widget.controller.refreshHeights();
      _refreshDistanceToBottom();
      _initController();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  ///软键盘未弹出情况下
  void _refreshDistanceToBottom() {
    //获取控件的 RenderBox
    final RenderBox renderBox =
        _globalKey.currentContext!.findRenderObject() as RenderBox;

    //获取控件的位置
    final Offset position = renderBox.localToGlobal(Offset.zero);

    //获取控件的高度
    final double widgetHeight = renderBox.size.height;

    //获取屏幕的总高度
    final double screenHeight = MediaQuery.of(context).size.height;

    //计算距离屏幕底部的距离
    _distanceToBottom = screenHeight - (position.dy + widgetHeight);
  }

  ///init controller
  void _initController() {
    if (widget.fitType != KeyboardScrollType.fitAllView) {
      widget.controller.setFocusListener((focusNode) {
        if (focusNode.hasFocus) {
          _refreshUserControlHeight();
        }
      });
    }
  }

  @override
  void didUpdateWidget(KeyboardScroll old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((callback) {
      widget.controller.refreshHeights();
      _refreshDistanceToBottom();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    outController?.dispose();
    inController?.dispose();
    super.dispose();
  }

  ///out animation
  void initOutAnim() {
    _outListener = () {
      if (outAnimation != null) {
        widget.controller._nowValue = outAnimation!.value;
        if (mounted) setState(() {});
      }
    };
    outController = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this);
  }

  ///in animation
  void initInAnim() {
    _inListener = () {
      if (inAnimation != null) {
        widget.controller._nowValue = inAnimation!.value;
        if (mounted) setState(() {});
      }
    };
    inController = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this);
  }

  ///text focused height change
  void _refreshUserControlHeight() {
    if (!mounted) {
      return;
    }
    bool onlyAddedField =
        (widget.fitType == KeyboardScrollType.fitAddedTextField);
    double? bottomNearest = widget.controller.getBottomNeedMargin();
    double bottomMargin = max(currentKeyboardHeight - _distanceToBottom, 0);
    double bottomNeed = (bottomNearest == null && onlyAddedField) ||
            (bottomMargin <= (bottomNearest ?? 0))
        ? 0
        : (bottomMargin - (bottomNearest ?? 0));
    if (widget.controller._formerEnd != bottomNeed) {
      double newValue = bottomNeed;
      widget.controller._formerEnd = newValue;
      if (widget.controller._nowValue > newValue) {
        _createOutAnim(widget.controller._nowValue, newValue);
        outController!.reset();
        outController!.forward();
      } else {
        _createInAnim(widget.controller._nowValue, newValue);
        inController!.reset();
        inController!.forward();
      }
    }
  }

  ///text focused height change
  void _changeUserControlHeight(double newer) {
    if (!mounted) {
      return;
    }
    currentKeyboardHeight = newer;
    _refreshUserControlHeight();
  }

  ///out animation
  void _createOutAnim(double former, double newValue) {
    inAnimation?.removeListener(_inListener!);
    outAnimation?.removeListener(_outListener!);
    outAnimation = ReverseTween(Tween(begin: newValue, end: former))
        .animate(CurvedAnimation(
      parent: outController!,
      curve: Curves.easeInOut,
    ));
    outAnimation!.addListener(_outListener!);
  }

  ///in animation
  void _createInAnim(double former, double newValue) {
    inAnimation?.removeListener(_inListener!);
    outAnimation?.removeListener(_outListener!);
    inAnimation = Tween(begin: former, end: newValue).animate(
      CurvedAnimation(parent: inController!, curve: Curves.easeInOut),
    );
    inAnimation!.addListener(_inListener!);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _globalKey,
      child: buildWidget(),
    );
  }

  ///key
  Widget buildWidget() {
    if (widget.fitType == KeyboardScrollType.fitAllView) {
      ///filter just bottom
      return KeyboardObserver(
        showListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.showListener != null) {
            widget.showListener!(former, newer, time);
          }
        },
        hideListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideListener != null) {
            widget.hideListener!(former, newer, time);
          }
        },
        showAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.showAnimationListener != null) {
            widget.showAnimationListener!(value, end);
          }
          widget.controller._nowValue = max(value - _distanceToBottom, 0);
          setState(() {});
        },
        hideAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideAnimationListener != null) {
            widget.hideAnimationListener!(value, end);
          }
          widget.controller._nowValue = max(value - _distanceToBottom, 0);
          setState(() {});
        },
        useIOSSystemAnim: widget.useIOSSystemAnim,
        child: buildListener(child: widget.child),
      );
    } else {
      ///filter text field
      return KeyboardObserver(
        showListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.showListener != null) {
            widget.showListener!(former, newer, time);
          }
          _changeUserControlHeight(newer);
        },
        hideListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideListener != null) {
            widget.hideListener!(former, newer, time);
          }
          _changeUserControlHeight(newer);
        },
        showAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.showAnimationListener != null) {
            widget.showAnimationListener!(value, end);
          }
        },
        hideAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideAnimationListener != null) {
            widget.hideAnimationListener!(value, end);
          }
        },
        useIOSSystemAnim: widget.useIOSSystemAnim,
        child: buildListener(child: widget.child),
      );
    }
  }

  ///通用的Listener构造函数
  Widget buildListener({
    required Widget child,
  }) {
    bool isAnimating = (inController?.isAnimating ?? false) ||
        (outController?.isAnimating ?? false);
    return Listener(
      onPointerMove: (data) {
        position ??= data.position;
        if (position?.dy.toInt() != data.position.dy.toInt() ||
            position?.dx.toInt() != data.position.dx.toInt()) {
          position = data.position;
          isMoved = true;
        }
        if (widget.closeWhenMove && isMoved) {
          FocusScope.of(context).requestFocus(FocusNode());
        }
      },
      onPointerDown: (data) {
        isMoved = false;
        position = null;
      },
      onPointerUp: (data) {
        if (widget.closeWhenTap && !isMoved) {
          FocusScope.of(context).requestFocus(FocusNode());
        }
      },
      child: Transform.translate(
        offset: Offset(0, -widget.controller._nowValue),
        filterQuality: isAnimating ? FilterQuality.none : null,
        child: child,
      ),
    );
  }
}
