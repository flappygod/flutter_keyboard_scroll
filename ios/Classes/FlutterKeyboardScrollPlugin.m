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


//init frame view
-(void)initFrameView{
    //get root controller
    UIViewController* root=[[UIApplication sharedApplication].keyWindow rootViewController];
    //top controller
    UIViewController *topController = [self _topViewController:root];
    //create frame view
    _frameView  = [[UIView alloc]initWithFrame:CGRectMake(0,
                                                          0,
                                                          1,
                                                          0)];
    //add frame view
    [topController.view addSubview:_frameView];
}

//disposeFrameView
-(void)disposeFrameView{
    [_frameView removeFromSuperview];
    _frameView=nil;
}

//get top
- (UIViewController *)_topViewController:(UIViewController *)vc {
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self _topViewController:[(UINavigationController *)vc topViewController]];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self _topViewController:[(UITabBarController *)vc selectedViewController]];
    } else {
        return vc;
    }
    return nil;
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
    CGRect endFrame            = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect startFrame            = [notification.userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];

    //硬件键盘
    if(startFrame.origin.y==endFrame.origin.y){
        return;
    }

    if(startFrame.origin.y<endFrame.origin.y){
        [self keyboardWillHideNotification:notification];
    }else{
        [self keyboardWillShowNotification:notification];
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardFrameChangeNotification:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    return nil;
}


- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink=nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillChangeFrameNotification
                                                  object:nil];
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {

}

@end
