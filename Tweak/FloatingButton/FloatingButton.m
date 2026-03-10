#import "../LocationManager/LocationManager.h"
#import "../MapViewController/MapViewController.h"
#import "FloatingButton.h"

static NSArray<UIWindow *> *LocusAllAppWindows(void) {
	NSMutableArray<UIWindow *> *result = [NSMutableArray array];
	if (@available(iOS 13.0, *)) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:[UIWindowScene class]]) continue;
			[result addObjectsFromArray:((UIWindowScene *)scene).windows];
		}
	} else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[result addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
	}
	return result;
}

@interface LocusSpoofingBanner : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIButton *bannerButton;
+ (instancetype)sharedInstance;
@end

@implementation LocusSpoofingBanner

+ (instancetype)sharedInstance {
	static LocusSpoofingBanner *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[LocusSpoofingBanner alloc] init];
	});
	return instance;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		[self setupWindowAndView];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(handleSpoofChange:)
													 name:LocusSpoofingDidChangeNotification
												   object:nil];
		[self updateBanner];
	}
	return self;
}

- (void)setupWindowAndView {
	UIWindowScene *scene = nil;
	if (@available(iOS 13.0, *)) {
		for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
			if (s.activationState == UISceneActivationStateForegroundActive) {
				scene = s;
				break;
			}
		}
	}

	if (scene) {
		self.window = [[UIWindow alloc] initWithWindowScene:scene];
	} else {
		self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	}

	self.window.windowLevel = UIWindowLevelAlert + 200;
	self.window.backgroundColor = [UIColor clearColor];
	self.window.userInteractionEnabled = NO;

	UIViewController *rootVC = [[UIViewController alloc] init];
	rootVC.view.backgroundColor = [UIColor clearColor];
	self.window.rootViewController = rootVC;

	self.bannerButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.bannerButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.bannerButton.alpha = 0;
	self.bannerButton.userInteractionEnabled = NO;
	self.bannerButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.bannerButton.layer.cornerRadius = 18;
	self.bannerButton.layer.masksToBounds = YES;

	if (@available(iOS 15.0, *)) {
		UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
		config.imagePadding = 6;
		config.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
		config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);

		UIBackgroundConfiguration *bg = [UIBackgroundConfiguration clearConfiguration];
		bg.cornerRadius = 18;
		bg.visualEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
		bg.strokeColor = [UIColor separatorColor];
		bg.strokeWidth = 0.5;
		config.background = bg;

		self.bannerButton.configuration = config;
	} else {
		self.bannerButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
	}

	[rootVC.view addSubview:self.bannerButton];

	UILayoutGuide *safe = rootVC.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.bannerButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
		[self.bannerButton.centerXAnchor constraintEqualToAnchor:rootVC.view.centerXAnchor],
		[self.bannerButton.heightAnchor constraintEqualToConstant:36],
	]];

	self.window.hidden = NO;
}

- (void)handleSpoofChange:(NSNotification *)notification {
	[self updateBanner];
}

- (void)updateBanner {
	LocusLocationManager *mgr = [LocusLocationManager shared];
	if (mgr.isSpoofing) {
		NSString *title = [NSString stringWithFormat:@"Spoofing: %.4f, %.4f",
			mgr.fakeCoordinate.latitude, mgr.fakeCoordinate.longitude];
		UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
		UIImage *iconImage = [UIImage systemImageNamed:@"location.fill" withConfiguration:symbolConfig];

		if (@available(iOS 15.0, *)) {
			UIButtonConfiguration *config = self.bannerButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
			config.title = title;
			config.image = iconImage;
			config.baseForegroundColor = [UIColor systemGreenColor];
			self.bannerButton.configuration = config;
		} else {
			[self.bannerButton setTitle:title forState:UIControlStateNormal];
			[self.bannerButton setImage:iconImage forState:UIControlStateNormal];
			[self.bannerButton setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
		}

		[UIView animateWithDuration:0.3 animations:^{
			self.bannerButton.alpha = 1;
		}];
	} else {
		[UIView animateWithDuration:0.3 animations:^{
			self.bannerButton.alpha = 0;
		}];
	}
}

@end

@interface LocusFloatingButtonWindow : UIWindow
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, strong) NSTimer *dockTimer;
@property (nonatomic, assign) BOOL isDocked;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) id buttonTarget;
@property (nonatomic, assign) SEL buttonAction;
- (void)showButton;
- (void)hideButton;
@end

@interface LocusFloatingButton () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) LocusFloatingButtonWindow *window;
@property (nonatomic, assign) BOOL isPresentingSheet;
@end

@implementation LocusFloatingButtonWindow

- (instancetype)init {
	self = [super initWithFrame:UIScreen.mainScreen.bounds];
	if (self) {
		[self setupWindow];
		[self setupButton];
		[self setupHandle];
	}
	return self;
}

- (void)setupWindow {
	if (@available(iOS 13.0, *)) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:[UIWindowScene class]]) continue;
			if (scene.activationState == UISceneActivationStateForegroundActive) {
				self.windowScene = (UIWindowScene *)scene;
				break;
			}
		}
		if (!self.windowScene) {
			for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
				if ([scene isKindOfClass:[UIWindowScene class]]) {
					self.windowScene = (UIWindowScene *)scene;
					break;
				}
			}
		}
	}

	self.windowLevel = UIWindowLevelAlert + 100;
	self.userInteractionEnabled = YES;
	self.backgroundColor = [UIColor clearColor];
	self.rootViewController = [[UIViewController alloc] init];
	self.rootViewController.view.backgroundColor = [UIColor clearColor];
	self.hidden = YES;
	self.isVisible = NO;
}

- (void)setupButton {
	self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.floatingButton.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - 50 - 24, 220, 50, 50);
	self.floatingButton.layer.cornerRadius = 25;
	self.floatingButton.layer.masksToBounds = YES;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
	UIImage *icon = [UIImage systemImageNamed:@"location.fill" withConfiguration:config];

	if (@available(iOS 15.0, *)) {
		UIButtonConfiguration *buttonConfig = [UIButtonConfiguration plainButtonConfiguration];
		buttonConfig.image = icon;
		buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(12, 12, 12, 12);
		buttonConfig.baseForegroundColor = [UIColor labelColor];

		UIBackgroundConfiguration *bg = [UIBackgroundConfiguration clearConfiguration];
		bg.cornerRadius = 25;
		bg.visualEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
		bg.strokeColor = [UIColor separatorColor];
		bg.strokeWidth = 0.5;
		buttonConfig.background = bg;

		self.floatingButton.configuration = buttonConfig;
	} else {
		self.floatingButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
		self.floatingButton.tintColor = [UIColor labelColor];
		[self.floatingButton setImage:icon forState:UIControlStateNormal];
	}

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	[self.floatingButton addGestureRecognizer:pan];
	[self.floatingButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];

	[self.rootViewController.view addSubview:self.floatingButton];
	[self snapButtonToNearestEdge:self.floatingButton];
}

- (void)setupHandle {
	self.handleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 50)];
	self.handleView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.72];
	self.handleView.layer.cornerRadius = 6;
	self.handleView.layer.masksToBounds = YES;
	self.handleView.alpha = 0;
	self.handleView.hidden = YES;

	UIView *line = [[UIView alloc] initWithFrame:CGRectMake((self.handleView.frame.size.width - 2.5) / 2.0,
													 (self.handleView.frame.size.height - 28) / 2.0,
													 2.5,
													 28)];
	line.backgroundColor = [UIColor whiteColor];
	line.layer.cornerRadius = 1.25;
	[self.handleView addSubview:line];

	UIPanGestureRecognizer *handlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHandlePan:)];
	[self.handleView addGestureRecognizer:handlePan];
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(undockButton)];
	[self.handleView addGestureRecognizer:tap];

	[self.rootViewController.view addSubview:self.handleView];
}

- (void)setButtonTarget:(id)buttonTarget {
	_buttonTarget = buttonTarget;
}

- (void)setButtonAction:(SEL)buttonAction {
	_buttonAction = buttonAction;
}

- (void)buttonTapped {
	[self resetDockTimer];

	if (self.buttonTarget && self.buttonAction && [self.buttonTarget respondsToSelector:self.buttonAction]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self.buttonTarget performSelector:self.buttonAction];
#pragma clang diagnostic pop
	}
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
	[self resetDockTimer];

	CGPoint translation = [gesture translationInView:self];
	CGPoint center = gesture.view.center;
	center.x += translation.x;
	center.y += translation.y;
	gesture.view.center = center;
	[gesture setTranslation:CGPointZero inView:self];

	if (gesture.state == UIGestureRecognizerStateEnded) {
		[self snapButtonToNearestEdge:(UIButton *)gesture.view];
		[self startDockTimer];
	}
}

- (void)handleHandlePan:(UIPanGestureRecognizer *)gesture {
	CGPoint translation = [gesture translationInView:self];

	if (gesture.state == UIGestureRecognizerStateBegan) {
		[self undockButton];
		return;
	}

	CGPoint newCenter = CGPointMake(gesture.view.center.x + translation.x, gesture.view.center.y + translation.y);
	self.floatingButton.center = newCenter;
	[gesture setTranslation:CGPointZero inView:self];

	if (gesture.state == UIGestureRecognizerStateEnded) {
		[self snapButtonToNearestEdge:self.floatingButton];
		[self startDockTimer];
	}
}

- (void)snapButtonToNearestEdge:(UIButton *)button {
	CGRect buttonFrame = button.frame;
	CGPoint newCenter = button.center;
	CGFloat screenWidth = self.bounds.size.width;
	CGFloat buttonWidth = buttonFrame.size.width;

	if (newCenter.x < screenWidth / 2.0) {
		newCenter.x = buttonWidth / 2.0;
	} else {
		newCenter.x = screenWidth - buttonWidth / 2.0;
	}

	newCenter.y = MAX(buttonFrame.size.height / 2.0, MIN(self.bounds.size.height - buttonFrame.size.height / 2.0, newCenter.y));

	[UIView animateWithDuration:0.25 animations:^{
		button.center = newCenter;
	}];
}

- (void)startDockTimer {
	[self.dockTimer invalidate];
	self.dockTimer = [NSTimer timerWithTimeInterval:5.0
											 target:self
										   selector:@selector(dockButton)
										   userInfo:nil
											repeats:NO];
	[[NSRunLoop mainRunLoop] addTimer:self.dockTimer forMode:NSRunLoopCommonModes];
}

- (void)resetDockTimer {
	if (self.isDocked) return;
	[self.dockTimer invalidate];
	[self startDockTimer];
}

- (void)dockButton {
	if (self.isDocked) return;
	self.isDocked = YES;

	CGRect buttonFrame = self.floatingButton.frame;
	CGRect handleFrame = self.handleView.frame;
	BOOL isLeftEdge = self.floatingButton.center.x < self.bounds.size.width / 2.0;
	CGFloat handleX = isLeftEdge ? 0 : self.bounds.size.width - handleFrame.size.width;
	handleFrame.origin = CGPointMake(handleX, buttonFrame.origin.y + (buttonFrame.size.height - handleFrame.size.height) / 2.0);
	self.handleView.frame = handleFrame;

	[UIView animateWithDuration:0.25 animations:^{
		self.floatingButton.alpha = 0;
		self.floatingButton.transform = CGAffineTransformMakeScale(0.5, 0.5);
	} completion:^(BOOL finished) {
		self.floatingButton.hidden = YES;
		self.handleView.hidden = NO;
		[UIView animateWithDuration:0.2 animations:^{
			self.handleView.alpha = 1;
		}];
	}];
}

- (void)undockButton {
	if (!self.isDocked) return;

	self.isDocked = NO;
	self.floatingButton.hidden = NO;

	BOOL isLeftEdge = self.handleView.frame.origin.x < self.bounds.size.width / 2.0;
	CGPoint buttonCenter = self.handleView.center;
	buttonCenter.x = isLeftEdge
		? self.handleView.frame.size.width + self.floatingButton.frame.size.width / 2.0
		: self.bounds.size.width - self.handleView.frame.size.width - self.floatingButton.frame.size.width / 2.0;
	self.floatingButton.center = buttonCenter;

	[UIView animateWithDuration:0.25 animations:^{
		self.handleView.alpha = 0;
		self.floatingButton.alpha = 1;
		self.floatingButton.transform = CGAffineTransformIdentity;
	} completion:^(BOOL finished) {
		self.handleView.hidden = YES;
		[self startDockTimer];
	}];
}

- (void)showButton {
	if (@available(iOS 13.0, *)) {
		if (!self.windowScene || self.windowScene.activationState != UISceneActivationStateForegroundActive) {
			for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
				if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
					self.windowScene = (UIWindowScene *)scene;
					break;
				}
			}
		}
	}

	if (self.isVisible && !self.hidden) {
		if (!self.isDocked) {
			[self resetDockTimer];
		}
		return;
	}

	self.isVisible = YES;
	self.hidden = NO;
	if (!self.isDocked) {
		[self startDockTimer];
	} else {
		// Ensure handle remains visible when restoring an already docked state.
		self.handleView.hidden = NO;
		self.handleView.alpha = 1;
		self.floatingButton.hidden = YES;
	}
}

- (void)hideButton {
	self.isVisible = NO;
	self.hidden = YES;
	[self.dockTimer invalidate];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	CGPoint buttonPoint = [self convertPoint:point toView:self.floatingButton];
	if (!self.floatingButton.hidden && [self.floatingButton pointInside:buttonPoint withEvent:event]) {
		return [super hitTest:point withEvent:event];
	}

	CGPoint handlePoint = [self convertPoint:point toView:self.handleView];
	if (!self.handleView.hidden && [self.handleView pointInside:handlePoint withEvent:event]) {
		return [super hitTest:point withEvent:event];
	}

	return nil;
}

@end

@implementation LocusFloatingButton

+ (instancetype)sharedInstance {
	static LocusFloatingButton *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[LocusFloatingButton alloc] init];
		instance.window = [[LocusFloatingButtonWindow alloc] init];
		instance.window.buttonTarget = instance;
		instance.window.buttonAction = @selector(buttonTapped);
		[[NSNotificationCenter defaultCenter] addObserver:instance
												 selector:@selector(handleMapSheetDismissed:)
													 name:LocusMapSheetDidDismissNotification
												   object:nil];
		[LocusSpoofingBanner sharedInstance];
	});
	return instance;
}

- (void)show {
	[self.window showButton];
}

- (void)hide {
	[self.window hideButton];
}

- (UIViewController *)_topMostViewController {
	// Walk the app's main windows to find top-most presented VC.
	// Explicitly avoid presenting from our own floating button window.
	UIViewController *root = nil;
	for (UIWindow *window in LocusAllAppWindows()) {
		if (window == self.window) continue;
		if (!window.rootViewController) continue;
		if (window.windowLevel >= self.window.windowLevel) continue;
		if (window.isHidden) continue;
		if (window.alpha <= 0.01) continue;

		if (window.isKeyWindow) {
			root = window.rootViewController;
			break;
		}
		if (!root) {
			root = window.rootViewController;
		}
	}

	if (!root) {
		root = UIApplication.sharedApplication.delegate.window.rootViewController;
	}

	UIViewController *topVC = root;
	while (topVC.presentedViewController) {
		topVC = topVC.presentedViewController;
	}
	return topVC;
}

- (BOOL)_isMapSheetPresented {
	for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
		for (UIWindow *window in scene.windows) {
			UIViewController *vc = window.rootViewController;
			while (vc) {
				if ([vc isKindOfClass:[LocusMapViewController class]]) return YES;
				if ([vc isKindOfClass:[UINavigationController class]]) {
					UINavigationController *nav = (UINavigationController *)vc;
					if ([nav.topViewController isKindOfClass:[LocusMapViewController class]]) return YES;
				}
				vc = vc.presentedViewController;
			}
		}
	}
	return NO;
}

- (void)buttonTapped {
	UIViewController *presenter = [self _topMostViewController];
	if (!presenter) return;
	if (self.isPresentingSheet) return;
	if ([self _isMapSheetPresented]) return;

	LocusMapViewController *mapVC = [[LocusMapViewController alloc] init];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:mapVC];
	navVC.navigationBarHidden = YES;
	navVC.modalPresentationStyle = UIModalPresentationPageSheet;

	UISheetPresentationController *sheet = navVC.sheetPresentationController;
	if (sheet) {
		sheet.detents = @[
			UISheetPresentationControllerDetent.largeDetent,
		];
		sheet.prefersGrabberVisible = YES;
		sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
	}
	if (navVC.presentationController) {
		navVC.presentationController.delegate = self;
	}

	self.isPresentingSheet = YES;
	[presenter presentViewController:navVC animated:YES completion:^{
		self.isPresentingSheet = NO;
	}];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
	self.isPresentingSheet = NO;
}

- (void)handleMapSheetDismissed:(NSNotification *)notification {
	self.isPresentingSheet = NO;
}

@end
