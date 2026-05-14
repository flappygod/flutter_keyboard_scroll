/// 键盘弹出时自动上推可滚动内容、管理输入框与 [KeyboardScrollController] 的库。
library keyboard_scroll;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'keyboard_observer.dart';
import 'dart:math';

/// 与 [KeyboardObserver] 一致的键盘动画驱动方式。
enum KeyboardAnimationMode {
  /// 使用原生事件与本地动画控制器模拟 inset 变化。
  simulated,

  /// 跟随 [MediaQuery] / [View] 的 viewInsets 变化（更接近系统键盘动画）。
  mediaQuery,
}

/// [KeyboardScroll] 根据何种范围计算需要上移的距离。
enum KeyboardScrollType {
  /// 按整页/整棵子树与键盘高度对齐（整块内容上移）。
  fitAllView,

  /// 考虑所有已注册输入框的底部边距。
  fitAllTextField,

  /// 仅考虑通过 [KeyboardScrollController.addTextFieldWrapper] 注册的输入框。
  fitAddedTextField,
}

/// 某个 [TextFieldWrapper] 获得或失去焦点时的回调。
typedef TextFieldWrapperListener = void Function(FocusNode focusNode);

/// 将 [FocusNode] 与用于测量位置的 [GlobalKey] 绑定，供 [KeyboardScrollController] 计算底部留白。
class TextFieldWrapper {
  /// 使用 [focusKey] 对应渲染对象底部到屏幕底边的距离参与滚动计算。
  TextFieldWrapper.fromKey({
    required this.focusNode,
    required this.focusKey,
    this.more = 0,
  }) {
    _focusDelegateListener = () {
      _focusChangedListener?.call(focusNode);
    };
    focusNode.addListener(_focusDelegateListener!);
  }

  //focus delegate
  VoidCallback? _focusDelegateListener;

  //focus change listener
  TextFieldWrapperListener? _focusChangedListener;

  /// 用于 [RenderBox] 定位的 [GlobalKey]，应挂在输入框或包裹输入框的组件上。
  GlobalKey focusKey;

  /// 与 [focusKey] 绑定的焦点节点。
  FocusNode focusNode;

  //bottom
  double _bottom = 0;

  /// 在计算与屏幕底部距离时额外减去的偏移（逻辑像素），用于微调间距。
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

  /// 返回当前测得的输入框底部到屏幕底边的距离减去 [more]。
  double getBottom() {
    return _bottom - more;
  }
}

/// 持有已注册的 [TextFieldWrapper]，并在键盘高度变化时计算需要的底部上移量。
class KeyboardScrollController {
  /// 创建控制器；通过 [addTextFieldWrapper] 注册需要参与避让的输入框。
  KeyboardScrollController();

  //当前的
  double _nowValue = 0;

  double _formerEnd = 0;

  bool _enabled = true;

  //wrapper
  final List<TextFieldWrapper> _wrappers = [];

  //listener
  TextFieldWrapperListener? _focusChangedListener;

  /// 当任一已包装输入框焦点变化时调用 [listener]。
  void setFocusListener(TextFieldWrapperListener listener) {
    _focusChangedListener = listener;
    for (int s = 0; s < _wrappers.length; s++) {
      _wrappers[s]._focusChangedListener = _focusChangedListener;
    }
  }

  /// 注册需要参与滚动计算的输入框。
  void addTextFieldWrapper(TextFieldWrapper wrapper) {
    if (!_wrappers.contains(wrapper)) {
      wrapper._focusChangedListener = _focusChangedListener;
      _wrappers.add(wrapper);
    }
  }

  /// 取消注册由 [addTextFieldWrapper] 添加的 [wrapper]。
  void removeTextFieldWrapper(TextFieldWrapper wrapper) {
    if (_wrappers.contains(wrapper)) {
      wrapper._focusChangedListener = null;
      _wrappers.remove(wrapper);
    }
  }

  /// 重新测量所有已注册 [TextFieldWrapper] 的底部位置（通常在布局变化后调用）。
  void refreshHeights() {
    for (int s = 0; s < _wrappers.length; s++) {
      _wrappers[s]._refreshBottomHeight(_nowValue);
    }
  }

  /// 当前获得焦点的输入框中，距离屏幕底边最近的一条边距；无焦点时可能为 null。
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

  /// 是否响应键盘与焦点变化；为 false 时不再更新位移。
  void setEnable(bool flag) {
    _enabled = flag;
  }

  /// 当前是否启用键盘滚动逻辑。
  bool isEnable() {
    return _enabled;
  }
}

/// 在键盘弹出时通过 [Transform.translate] 上推 [child]，避免输入框被遮挡。
///
/// 内部使用 [KeyboardObserver]；需配合 [KeyboardScrollController] 与若干 [TextFieldWrapper]（视 [fitType] 而定）。
class KeyboardScroll extends StatefulWidget {
  /// 轻点抬起且未发生明显移动时是否收起键盘（将焦点交给空 [FocusNode]）。
  final bool closeWhenTap;

  /// 发生拖拽移动时是否收起键盘。
  final bool closeWhenMove;

  /// 列表或表单等可滚动内容。
  final Widget child;

  /// 共享的滚动控制器，用于注册输入框与开关。
  final KeyboardScrollController controller;

  /// 决定如何选取用于对齐的输入框与边距，见 [KeyboardScrollType]。
  final KeyboardScrollType fitType;

  /// 传递给内部 [KeyboardObserver] 的动画模式。
  final KeyboardAnimationMode animationMode;

  /// 键盘显示原生阶段回调，转发自内部 [KeyboardObserver]。
  final KeyboardObserverListener? showListener;

  /// 键盘隐藏原生阶段回调。
  final KeyboardObserverListener? hideListener;

  /// 键盘展开动画逐帧回调。
  final KeyboardAnimationListener? showAnimationListener;

  /// 键盘收起动画逐帧回调。
  final KeyboardAnimationListener? hideAnimationListener;

  /// [ClipRect] 的裁剪行为。
  final Clip clipBehavior;

  /// 创建键盘避让滚动容器。
  const KeyboardScroll({
    Key? key,
    required this.controller,
    required this.child,
    this.closeWhenTap = false,
    this.closeWhenMove = false,
    this.animationMode = KeyboardAnimationMode.simulated,
    this.fitType = KeyboardScrollType.fitAddedTextField,
    this.showListener,
    this.hideListener,
    this.showAnimationListener,
    this.hideAnimationListener,
    this.clipBehavior = Clip.hardEdge,
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
    return ClipRect(
      key: _globalKey,
      clipBehavior: widget.clipBehavior,
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
          widget.showListener?.call(former, newer, time);
        },
        hideListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.hideListener?.call(former, newer, time);
        },
        showAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.showAnimationListener?.call(value, end);
          widget.controller._nowValue = max(value - _distanceToBottom, 0);
          setState(() {});
        },
        hideAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.hideAnimationListener?.call(value, end);
          widget.controller._nowValue = max(value - _distanceToBottom, 0);
          setState(() {});
        },
        animationMode: widget.animationMode,
        child: buildListener(child: widget.child),
      );
    } else {
      ///filter text field
      return KeyboardObserver(
        showListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.showListener?.call(former, newer, time);
          _changeUserControlHeight(newer);
        },
        hideListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.hideListener?.call(former, newer, time);
          _changeUserControlHeight(newer);
        },
        showAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.showAnimationListener?.call(value, end);
        },
        hideAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          widget.hideAnimationListener?.call(value, end);
        },
        animationMode: widget.animationMode,
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
