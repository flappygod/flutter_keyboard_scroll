package com.flappy.flutter_keyboard_scroll;

public interface KeyboardListener {
    /**
     * call back
     *
     * @param isShow         true is show else hidden
     * @param keyboardHeight keyboard height
     */
    void onKeyboardChange(boolean isShow, int keyboardHeight);
}
