package com.flappy.flutter_keyboard_scroll;

import android.content.res.Resources;
import android.view.ViewTreeObserver;
import android.content.Context;
import android.graphics.Point;
import android.graphics.Rect;
import android.app.Activity;
import android.view.Display;
import android.view.Window;
import android.view.View;
import android.util.Log;

/******
 * 观察键盘高度变化
 */
class KeyboardChangeObserver implements ViewTreeObserver.OnGlobalLayoutListener {

    //观察器
    private static final String TAG = "KeyboardChangeObserver";

    //键盘的最低高度
    public static final int MIN_KEYBOARD_HEIGHT = 100;

    //软键盘高度
    private int softBottomHeight = 0;

    //监听
    private KeyboardListener mKeyboardListener;

    //页面对象
    private Window mWindow;

    //content view
    private View mContentView;


    //设置监听
    public void setKeyboardListener(KeyboardListener keyboardListener) {
        this.mKeyboardListener = keyboardListener;
    }

    //创建
    public static KeyboardChangeObserver create(Activity activity) {
        return new KeyboardChangeObserver(activity);
    }

    /******
     * 构造observer
     * @param activity 页面
     */
    public KeyboardChangeObserver(Activity activity) {
        if (activity == null) {
            Log.d(TAG, "contextObj is null");
            return;
        }
        mContentView = activity.findViewById(android.R.id.content);
        mWindow = activity.getWindow();
        if (mContentView != null && mWindow != null) {
            addContentTreeObserver();
        }
    }

    /******
     * 添加监听
     */
    private void addContentTreeObserver() {
        mContentView.getViewTreeObserver().addOnGlobalLayoutListener(this);
    }

    @Override
    public void onGlobalLayout() {
        if (mContentView == null || mWindow == null) {
            return;
        }

        //获取屏幕高度
        Rect rect = new Rect();
        mWindow.getDecorView().getWindowVisibleDisplayFrame(rect);
        int screenHeight = getScreenHeight();

        //计算离底部的高度
        int keyboardHeight = screenHeight - rect.bottom;

        //底部软键盘高度
        if (keyboardHeight < MIN_KEYBOARD_HEIGHT || keyboardHeight == getNavigationBarHeight(mContentView.getContext())) {
            softBottomHeight = keyboardHeight;
        }

        //减去软键盘高度
        keyboardHeight = keyboardHeight - softBottomHeight;


        //通知高度变化
        if (mKeyboardListener != null) {
            mKeyboardListener.onKeyboardChange((keyboardHeight > 0), keyboardHeight);
        }
    }

    /******
     * 获取屏幕高度
     * @return 屏幕高度
     */
    private int getScreenHeight() {
        Display defaultDisplay = mWindow.getWindowManager().getDefaultDisplay();
        Point point = new Point();
        defaultDisplay.getRealSize(point);
        return point.y;
    }

    /******
     * destroy
     */
    public void destroy() {
        if (mContentView != null) {
            mContentView.getViewTreeObserver().removeOnGlobalLayoutListener(this);
        }
    }


    /******
     * 获取软键盘高度
     * @param context 上下文
     * @return 值
     */
    public int getNavigationBarHeight(Context context) {
        Resources resources = context.getResources();
        int resourceId = resources.getIdentifier("navigation_bar_height", "dimen", "android");
        if (resourceId > 0) {
            return resources.getDimensionPixelSize(resourceId);
        }
        return 0;
    }


}