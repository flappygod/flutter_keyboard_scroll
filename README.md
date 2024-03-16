# flutter_keyboard_scroll

A plugin for keyboard show listen.

## Getting Started


KeyboardObserver(
hideListener: (double former, double newer, time) {
FocusScope.of(context).requestFocus(FocusNode());
},
child: Column(
children: [
_buildScreenShow(),
_buildTextField(),
],
),
);


///keyboard scroll controller

final KeyboardScrollController _keyboardScrollController = KeyboardScrollController();

///add wrapper

_keyboardScrollController.addTextFieldWrapper(
TextFieldWrapper.fromKey(focusNode: _focusNode, focusKey: _globalKey),
);

///build widget

KeyboardScroll(
controller: _keyboardScrollController,
child: ListView(
padding: EdgeInsets.fromLTRB(
0,
0,
0,
MediaQuery.of(context).padding.bottom,
),
children: [
...
),
)






