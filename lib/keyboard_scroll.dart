import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'keyboard_observer.dart';

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

  void setEnable(bool flag) {
    _enabled = flag;
  }
}

//type
enum KeyboardScrollType {
  //just bottom
  fitJustBottom,
  //each text
  fitEveryText,
  //each text
  fitAddedText,
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
  final KeyboardScrollType scrollType;

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
    this.scrollType = KeyboardScrollType.fitEveryText,
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

  Offset? position;

  @override
  void initState() {
    super.initState();
    initOutAnim();
    initInAnim();
    WidgetsBinding.instance.addPostFrameCallback((callback) {
      _initController();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  //init controller
  void _initController() {
    if (widget.scrollType == KeyboardScrollType.fitEveryText) {
      //set listener
      widget.controller.setFocusListener((focusNode) {
        if (focusNode.hasFocus) {
          _refreshUserControlHeight(
              widget.scrollType == KeyboardScrollType.fitAddedText);
        }
      });
      widget.controller.refreshHeights();
    }
  }

  @override
  void didUpdateWidget(KeyboardScroll old) {
    super.didUpdateWidget(old);
    //widget.controller.refreshHeights();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    outController?.dispose();
    inController?.dispose();
    super.dispose();
  }

  //out animation
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

  //in animation
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

  //text focused height change
  void _refreshUserControlHeight(bool onlyAddedField) {
    if (mounted) {
      double? bottomNearest = widget.controller.getBottomNeedMargin();
      if (bottomNearest == null && onlyAddedField) {
        return;
      } else {
        bottomNearest ??= 0;
      }
      double bottomMargin = currentKeyboardHeight;
      double bottomNeed = (bottomMargin - bottomNearest) < 0
          ? 0
          : (bottomMargin - bottomNearest);
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
  }

  //text focused height change
  void _changeUserControlHeight(double newer, bool onlyAddedField) {
    if (mounted) {
      currentKeyboardHeight = newer;
      double? bottomNearest = widget.controller.getBottomNeedMargin();
      if (bottomNearest == null && onlyAddedField) {
        return;
      } else {
        bottomNearest ??= 0;
      }
      double bottomMargin = newer;
      double bottomNeed = (bottomMargin - bottomNearest) < 0
          ? 0
          : (bottomMargin - bottomNearest);
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
  }

  //out animation
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

  //in animation
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
    bool isAnimating = (inController?.isAnimating ?? false) ||
        (outController?.isAnimating ?? false);
    if (widget.scrollType == KeyboardScrollType.fitJustBottom) {
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
          widget.controller._nowValue = value;
          setState(() {});
        },
        hideAnimationListener: (value, end) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideAnimationListener != null) {
            widget.hideAnimationListener!(value, end);
          }
          widget.controller._nowValue = value;
          setState(() {});
        },
        useIOSSystemAnim: widget.useIOSSystemAnim,
        child: Listener(
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
            if (widget.closeWhenTap && isMoved == false) {
              FocusScope.of(context).requestFocus(FocusNode());
            }
          },
          child: Transform.translate(
            offset: Offset(0, -widget.controller._nowValue),
            filterQuality: isAnimating ? FilterQuality.none : null,
            child: widget.child,
          ),
        ),
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
          _changeUserControlHeight(
            newer,
            widget.scrollType == KeyboardScrollType.fitAddedText,
          );
        },
        hideListener: (former, newer, time) {
          if (!widget.controller._enabled) {
            return;
          }
          if (widget.hideListener != null) {
            widget.hideListener!(former, newer, time);
          }
          _changeUserControlHeight(
            newer,
            widget.scrollType == KeyboardScrollType.fitAddedText,
          );
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
        child: Listener(
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
            if (widget.closeWhenTap && isMoved == false) {
              FocusScope.of(context).requestFocus(FocusNode());
            }
          },
          child: Transform.translate(
            offset: Offset(0, -widget.controller._nowValue),
            filterQuality: isAnimating ? FilterQuality.none : null,
            child: widget.child,
          ),
        ),
      );
    }
  }
}
