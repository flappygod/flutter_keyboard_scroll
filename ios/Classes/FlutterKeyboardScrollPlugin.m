#import "FlutterKeyboardScrollPlugin.h"


@interface FlutterKeyboardScrollPlugin ()<FlutterStreamHandler>

//channel
@property(nonatomic,weak) FlutterEventChannel* eventChannel;

//eventSink
@property(nonatomic,strong) FlutterEventSink eventSink;

//标志变量：标记应用是否在前台
@property(nonatomic, assign) BOOL isAppInForeground;

//缓存的软键盘高度
@property(nonatomic, assign) CGFloat cacheKeyboardHeight;

@end


@implementation FlutterKeyboardScrollPlugin
{
    NSMutableDictionary* _animationEventDic;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    
    //create eventChannel
    FlutterEventChannel* eventChannel=[FlutterEventChannel eventChannelWithName:@"keyboard_observer_event"
                                                                binaryMessenger:[registrar messenger]];
    //init
    FlutterKeyboardScrollPlugin* instance = [[FlutterKeyboardScrollPlugin alloc] init];
    
    //set eventChannel
    instance.eventChannel=eventChannel;
    
    //set Handler
    [instance.eventChannel setStreamHandler:instance];
}


#pragma mark - Application Lifecycle
- (void)applicationDidEnterBackground {
    // 应用进入后台，设置标志为 NO
    self.isAppInForeground = NO;
    
    //进入后台前缓存当前的软键盘高度
    self.cacheKeyboardHeight = [self getCurrentKeyboardHeight];
}

- (void)applicationWillEnterForeground {
    //应用返回前台，设置标志为 YES
    self.isAppInForeground = YES;
    
    //弱引用
    __weak typeof(self) weakSelf = self;
    __weak typeof(_eventSink) eventSink = _eventSink;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        //高度不变不执行
        CGFloat keyboardHeight = [weakSelf getCurrentKeyboardHeight];
        
        //没有就不执行吧
        if(keyboardHeight==0){
            return;
        }
        
        //进行通知
        NSMutableDictionary* eventDic = [[NSMutableDictionary alloc] init];
        eventDic[@"type"]=[NSNumber numberWithInt:2];
        eventDic[@"former"]=[NSString stringWithFormat:@"%.2f",weakSelf.cacheKeyboardHeight];
        eventDic[@"newer"]=[NSString stringWithFormat:@"%.2f",keyboardHeight];
        eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
        eventSink(eventDic);
        
    });
}

///软键盘高度获取
- (CGFloat)getCurrentKeyboardHeight {
    // 遍历所有连接的场景（适配 iOS 13+）
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    CGFloat keyboardHeight = [self findKeyboardHeightInView:window];
                    if (keyboardHeight > 120) {
                        return keyboardHeight;
                    }
                }
            }
        }
    } else {
        // iOS 13 以下使用 keyWindow
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        return [self findKeyboardHeightInView:keyWindow];
    }
    return 0;
}

// 递归查找键盘视图并获取高度
- (CGFloat)findKeyboardHeightInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        // 判断是否为键盘视图
        if ([NSStringFromClass([subview class]) containsString:@"Keyboard"]) {
            return subview.frame.size.height;
        }
        // 递归查找子视图
        CGFloat keyboardHeight = [self findKeyboardHeightInView:subview];
        if (keyboardHeight > 0) {
            return keyboardHeight;
        }
    }
    return 0;
}




// 获取当前的 activeWindow
- (UIWindow *)activeWindow {
    if (@available(iOS 13.0, *)) {
        // iOS 13+ using UIScene
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                // Look for the key window
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
                // Fallback: Return the first window if no keyWindow is found
                if (windowScene.windows.count > 0) {
                    return windowScene.windows.firstObject;
                }
            }
        }
    } else {
        // iOS 12 and below using keyWindow
        return [UIApplication sharedApplication].keyWindow;
    }
    // Log a warning if no active window is found
    NSLog(@"Warning: No active window found!");
    return nil;
}

// Helper method to find the top view controller
- (UIViewController *)_topViewController:(UIViewController *)rootViewController {
    if (rootViewController.presentedViewController == nil) {
        return rootViewController;
    }
    if ([rootViewController.presentedViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController.presentedViewController;
        UIViewController *lastViewController = [[navigationController viewControllers] lastObject];
        return [self _topViewController:lastViewController];
    }
    UIViewController *presentedViewController = (UIViewController *)rootViewController.presentedViewController;
    return [self _topViewController:presentedViewController];
}


-(void)keyboardFrameChangeNotification:(NSNotification *)notification{
    
    // 检查标志变量
    if (!self.isAppInForeground) {
        // 应用在后台，直接返回
        return;
    }
    
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect startFrame            = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    
    //基本相等
    if (fabs(startFrame.origin.y - endFrame.origin.y) < 0.1) {
        return;
    }
    
    // 获取主屏幕的bounds
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGFloat screenHeight = screenBounds.size.height;
    if(endFrame.origin.y<screenHeight-5){
        [self keyboardWillShowNotification:notification];
    }else{
        [self keyboardWillHideNotification:notification];
    }
}


//软键盘弹出
- (void)keyboardWillShowNotification:(NSNotification *)notification
{
    
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect startFrame            = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    double duration             = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve keyboardTransitionAnimationCurve=[[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    CGFloat height = endFrame.size.height;
    
    
    //基本相等
    if (fabs(startFrame.origin.y - endFrame.origin.y) < 0.1) {
        height=0;
    }
    
    NSMutableDictionary*   eventDic=[[NSMutableDictionary alloc] init];
    eventDic[@"type"]=[NSNumber numberWithInt:2];
    eventDic[@"former"]=@"0.00";
    eventDic[@"newer"]=[NSString stringWithFormat:@"%.2f",height];
    eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
    _eventSink(eventDic);
}




//软键盘隐藏
- (void)keyboardWillHideNotification:(NSNotification *)notification
{
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double duration             = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve keyboardTransitionAnimationCurve=[[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    //send hide notification
    NSMutableDictionary*   eventDic=[[NSMutableDictionary alloc] init];
    eventDic[@"type"]=[NSNumber numberWithInt:3];
    eventDic[@"former"]=[NSString stringWithFormat:@"%.2f",endFrame.size.height];
    eventDic[@"newer"]=@"0.00";
    eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
    _eventSink(eventDic);
}



#pragma mark - <FlutterStreamHandler>
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)events {
    _eventSink=events;
    
    
    // 初始化标志变量
    self.isAppInForeground = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardFrameChangeNotification:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    
    
    // 添加应用生命周期监听
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    return nil;
}


- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink=nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillChangeFrameNotification
                                                  object:nil];
    
    // 移除应用生命周期监听
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidEnterBackgroundNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationWillEnterForegroundNotification
                                                  object:nil];
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    
}

@end
