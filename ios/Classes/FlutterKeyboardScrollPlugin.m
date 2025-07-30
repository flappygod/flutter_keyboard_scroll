#import "FlutterKeyboardScrollPlugin.h"


@interface FlutterKeyboardScrollPlugin ()<FlutterStreamHandler>

//channel
@property(nonatomic,weak) FlutterEventChannel* eventChannel;

//eventSink
@property(nonatomic,strong) FlutterEventSink eventSink;

//frameView
@property(nonatomic,strong) UIView* frameView;

//show link
@property(nonatomic,strong) CADisplayLink* showLink;

//hide link
@property(nonatomic,strong) CADisplayLink* hideLink;

// 标志变量：标记应用是否在前台
@property(nonatomic, assign) BOOL isAppInForeground;

@end


@implementation FlutterKeyboardScrollPlugin
{
    NSMutableDictionary* _eventDic;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"keyboard_observer"
                                     binaryMessenger:[registrar messenger]];
    
    //create eventChannel
    FlutterEventChannel* eventChannel=[FlutterEventChannel eventChannelWithName:@"keyboard_observer_event"
                                                                binaryMessenger:[registrar messenger]];
    //init
    FlutterKeyboardScrollPlugin* instance = [[FlutterKeyboardScrollPlugin alloc] init];
    
    //set eventChannel
    instance.eventChannel=eventChannel;
    
    //set Handler
    [instance.eventChannel setStreamHandler:instance];
    
    //set delegate
    [registrar addMethodCallDelegate:instance channel:channel];
}


- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if([@"openAnimListener" isEqualToString:call.method]){
        [self initFrameView];
        [self createDisplayLink];
        result(@"1");
    }
    else if([@"closeAnimListener" isEqualToString:call.method]){
        [self disposeDisplayLink];
        [self disposeFrameView];
        result(@"1");
    }else{
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Application Lifecycle
- (void)applicationDidEnterBackground {
    // 应用进入后台，设置标志为 NO
    self.isAppInForeground = NO;
}

- (void)applicationWillEnterForeground {
    // 应用返回前台，设置标志为 YES
    self.isAppInForeground = YES;
    
    __weak typeof(self) weakSelf = self;
    __weak typeof(_eventDic) eventDic = _eventDic;
    __weak typeof(_eventSink) eventSink = _eventSink;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGFloat keyboardHeight = [weakSelf getCurrentKeyboardHeight];
        eventDic[@"type"]=[NSNumber numberWithInt:2];
        eventDic[@"former"]=[NSString stringWithFormat:@"%.2f",keyboardHeight];
        eventDic[@"newer"]=[NSString stringWithFormat:@"%.2f",keyboardHeight];
        eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
        eventSink(eventDic);
        
        if(weakSelf.frameView!=nil){
            [weakSelf.frameView.layer removeAllAnimations];
            [weakSelf.showLink setPaused:false];
            [weakSelf.hideLink setPaused:true];
            [UIView animateWithDuration:420
                                  delay:0
                                options:UIViewAnimationOptionCurveLinear
                             animations:^{
                weakSelf.frameView.frame = CGRectMake(-1, 0 ,1,keyboardHeight);
            } completion:^(BOOL finished) {
                [weakSelf showDisplayLink:nil];
                [weakSelf.showLink setPaused:true];
            }];
        }
        
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
                    if (keyboardHeight > 0) {
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


- (void)initFrameView {
    UIWindow *activeWindow = [self activeWindow];
    if (!activeWindow) {
        return;
    }
    
    // 获取顶层控制器
    UIViewController *topController = [self _topViewController:activeWindow.rootViewController];
    
    // 创建并配置 frameView
    _frameView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // 将 frameView 添加到顶层控制器的视图中
    [topController.view addSubview:_frameView];
}



- (UIWindow *)activeWindow {
    if (@available(iOS 13.0, *)) {
        // iOS 13+ 使用 UIScene
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                return windowScene.windows.firstObject;
            }
        }
    } else {
        // iOS 13 以下使用 keyWindow
        return [UIApplication sharedApplication].keyWindow;
    }
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

//disposeFrameView
-(void)disposeFrameView{
    [_frameView removeFromSuperview];
    _frameView=nil;
}



//create display link
- (void)createDisplayLink
{
    //create show
    _showLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(showDisplayLink:)];
    [_showLink setPaused:true];
    [_showLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    //create hied
    _hideLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(hideDisplayLink:)];
    [_hideLink setPaused:true];
    [_hideLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

//dispose display link
- (void)disposeDisplayLink
{
    //dispose show
    [_showLink invalidate];
    _showLink = nil;
    //dispose hide
    [_hideLink invalidate];
    _hideLink = nil;
}



//handle event for view
- (void)showDisplayLink:(CADisplayLink *)displayLink
{
    //do something
    if(_frameView!=nil&&_eventSink!=nil){
        if(_eventDic==nil){
            _eventDic=[[NSMutableDictionary alloc] init];
        }
        _eventDic[@"type"]=[NSNumber numberWithInt:1];
        _eventDic[@"data"]=[NSString stringWithFormat:@"%.2f",_frameView.layer.presentationLayer.frame.size.height];
        _eventDic[@"end"]=[NSNumber numberWithBool:(displayLink==nil)];
        _eventSink(_eventDic);
    }
}

-(void)hideDisplayLink:(CADisplayLink *)displayLink
{
    //do something
    if(_frameView!=nil&&_eventSink!=nil){
        if(_eventDic==nil){
            _eventDic=[[NSMutableDictionary alloc] init];
        }
        _eventDic[@"type"]=[NSNumber numberWithInt:0];
        _eventDic[@"data"]=[NSString stringWithFormat:@"%.2f",_frameView.layer.presentationLayer.frame.size.height];
        _eventDic[@"end"]=[NSNumber numberWithBool:(displayLink==nil)];
        _eventSink(_eventDic);
    }
}

-(void)keyboardFrameChangeNotification:(NSNotification *)notification{
    
    // 检查标志变量
    if (!self.isAppInForeground) {
        // 应用在后台，直接返回
        return;
    }
    
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect startFrame            = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    
    //硬件键盘
    if(startFrame.origin.y==endFrame.origin.y){
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


//keyboard notificationsl
- (void)keyboardWillShowNotification:(NSNotification *)notification
{
    
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect startFrame            = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    double duration             = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve keyboardTransitionAnimationCurve=[[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    
    CGFloat height = endFrame.size.height;
    
    if(startFrame.origin.y==endFrame.origin.y){
        height=0;
    }
    
    
    //send show notification
    if(_eventDic==nil){
        _eventDic=[[NSMutableDictionary alloc] init];
    }
    _eventDic[@"type"]=[NSNumber numberWithInt:2];
    _eventDic[@"former"]=@"0.00";
    _eventDic[@"newer"]=[NSString stringWithFormat:@"%.2f",height];
    _eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
    _eventSink(_eventDic);
    
    if(_frameView!=nil){
        //remove former animation
        [self.frameView.layer removeAllAnimations];
        //set paused false
        [self.showLink setPaused:false];
        [self.hideLink setPaused:true];
        __weak typeof(self) safeSelf=self;
        [UIView animateWithDuration:duration
                              delay:0
                            options:keyboardTransitionAnimationCurve << 16
                         animations:^{
            safeSelf.frameView.frame = CGRectMake(-1, 0 ,1,height);
        } completion:^(BOOL finished) {
            [safeSelf showDisplayLink:nil];
            [safeSelf.showLink setPaused:true];
        }];
    }
}

//hide keyboard notifications
- (void)keyboardWillHideNotification:(NSNotification *)notification
{
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double duration             = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve keyboardTransitionAnimationCurve=[[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    //send hide notification
    if(_eventDic==nil){
        _eventDic=[[NSMutableDictionary alloc] init];
    }
    _eventDic[@"type"]=[NSNumber numberWithInt:3];
    _eventDic[@"former"]=[NSString stringWithFormat:@"%.2f",endFrame.size.height];
    _eventDic[@"newer"]=@"0.00";
    _eventDic[@"time"]= [NSString stringWithFormat:@"%ld",(long)([[NSDate date] timeIntervalSince1970] * 1000)];
    _eventSink(_eventDic);
    
    if(_frameView!=nil){
        //remove former animation
        [self.frameView.layer removeAllAnimations];
        //set paused false
        [self.hideLink setPaused:false];
        [self.showLink setPaused:true];
        __weak typeof(self) safeSelf=self;
        [UIView animateWithDuration:duration
                              delay:0
                            options:keyboardTransitionAnimationCurve << 16
                         animations:^{
            safeSelf.frameView.frame = CGRectMake(-1, 0 , 1, 0);
        } completion:^(BOOL finished) {
            [safeSelf hideDisplayLink:nil];
            [safeSelf.hideLink setPaused:true];
        }];
    }
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
