package android.src.main.java.com.flappy.flutter_keyboard_scroll;

import android.app.Activity;

import androidx.annotation.NonNull;

import java.util.HashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** FlutterKeyboardScrollPlugin */
public class FlutterKeyboardScrollPlugin implements FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;

  //event channel
  private EventChannel eventChannel;

  //set activity
  private Activity activity;

  //listener
  private KeyboardChangeObserver keyboardChangeListener;

  //event sink
  private EventChannel.EventSink eventSink;


  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "keyboard_observer");
    eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "keyboard_observer_event");
    channel.setMethodCallHandler(this);
    eventChannel.setStreamHandler(this);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    result.notImplemented();
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    eventSink = events;
  }

  @Override
  public void onCancel(Object arguments) {
    eventSink = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    setActivity(binding);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    setActivity(null);
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    setActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    setActivity(null);
  }

  void setActivity(ActivityPluginBinding binding) {
    if (binding != null) {
      activity = binding.getActivity();
      keyboardChangeListener = new KeyboardChangeObserver(activity);
      keyboardChangeListener.setKeyboardListener(new KeyboardListener() {
        private int keyboardHeight;

        @Override
        public void onKeyboardChange(boolean isShow, int keyboardHeight) {
          if (eventSink != null) {
            HashMap<String, Object> map = new HashMap<>();
            if (isShow) {
              this.keyboardHeight = keyboardHeight;
              map.put("type", 2);
              map.put("former", "0.00");
              map.put("newer", String.valueOf(keyboardHeight));
              map.put("time", System.currentTimeMillis());
            } else {
              map.put("type", 3);
              map.put("former", String.valueOf(this.keyboardHeight));
              map.put("newer", "0.00");
              map.put("time", System.currentTimeMillis());
            }
            eventSink.success(map);
            System.out.print(map);
          }
        }
      });
    } else {
      activity = null;
    }
  }

}