#import "LocationManager.h"

#import <float.h>
#import <math.h>
#import <objc/runtime.h>

NSString *const LocusSpoofingDidChangeNotification = @"LocusSpoofingDidChangeNotification";

static NSString *const LocusPersistSpoofingEnabledKey = @"LocusPersistSpoofingEnabledKey";
static NSString *const LocusPersistLatitudeKey = @"LocusPersistLatitudeKey";
static NSString *const LocusPersistLongitudeKey = @"LocusPersistLongitudeKey";
static NSString *const LocusPersistSpeedKey = @"LocusPersistSpeedKey";
static NSString *const LocusPersistCourseKey = @"LocusPersistCourseKey";

static const void *kLocusDidUpdateLocationsOriginalIMPKey = &kLocusDidUpdateLocationsOriginalIMPKey;
static const void *kLocusDidUpdateToLocationOriginalIMPKey = &kLocusDidUpdateToLocationOriginalIMPKey;

#ifndef LOCUS_DEBUG_LOGGING
#define LOCUS_DEBUG_LOGGING 1
#endif

#if LOCUS_DEBUG_LOGGING
#define LocusLog(fmt, ...) NSLog((@"[Locus] " fmt), ##__VA_ARGS__)
#else
#define LocusLog(...)
#endif

typedef void (*LocusDidUpdateLocationsIMP)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *);
typedef void (*LocusDidUpdateToLocationIMP)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *);

static NSArray<NSString *> *LocusBackgroundModes(void) {
	id modes = NSBundle.mainBundle.infoDictionary[@"UIBackgroundModes"];
	return [modes isKindOfClass:[NSArray class]] ? modes : @[];
}

static void LocusSwizzledDidUpdateLocations(id self, SEL _cmd, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
	LocusDidUpdateLocationsIMP originalImp =
		(LocusDidUpdateLocationsIMP)[objc_getAssociatedObject(object_getClass(self), kLocusDidUpdateLocationsOriginalIMPKey) pointerValue];
	if (!originalImp) {
		return;
	}

	LocusLocationManager *spoofManager = [LocusLocationManager shared];
	if (!spoofManager.isSpoofing) {
		originalImp(self, _cmd, manager, locations);
		return;
	}

	originalImp(self, _cmd, manager, [spoofManager spoofedLocationsArrayFromIncoming:locations]);
}

static void LocusSwizzledDidUpdateToLocation(id self, SEL _cmd, CLLocationManager *manager, CLLocation *newLocation, CLLocation *oldLocation) {
	LocusDidUpdateToLocationIMP originalImp =
		(LocusDidUpdateToLocationIMP)[objc_getAssociatedObject(object_getClass(self), kLocusDidUpdateToLocationOriginalIMPKey) pointerValue];
	if (!originalImp) {
		return;
	}

	LocusLocationManager *spoofManager = [LocusLocationManager shared];
	if (!spoofManager.isSpoofing) {
		originalImp(self, _cmd, manager, newLocation, oldLocation);
		return;
	}

	originalImp(self, _cmd, manager, [spoofManager spoofedLocationFromIncoming:newLocation], oldLocation);
}

@interface LocusLocationManager ()
- (void)persistState;
- (void)detectHostCapabilities;
- (NSTimeInterval)heartbeatInterval;
- (void)heartbeatTimerFired;
- (void)handleAppDidEnterBackground:(NSNotification *)notification;
- (void)handleAppWillEnterForeground:(NSNotification *)notification;
- (void)handleAppDidBecomeActive:(NSNotification *)notification;
@end

@implementation LocusLocationManager

+ (instancetype)shared {
	static LocusLocationManager *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[LocusLocationManager alloc] init];
	});
	return instance;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_backgroundTaskID = UIBackgroundTaskInvalid;
		_appIsForeground = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
		_isSpoofing = [[NSUserDefaults standardUserDefaults] boolForKey:LocusPersistSpoofingEnabledKey];

		double latitude = [[NSUserDefaults standardUserDefaults] doubleForKey:LocusPersistLatitudeKey];
		double longitude = [[NSUserDefaults standardUserDefaults] doubleForKey:LocusPersistLongitudeKey];
		_fakeCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
		_fakeSpeed = [[NSUserDefaults standardUserDefaults] objectForKey:LocusPersistSpeedKey]
			? [[NSUserDefaults standardUserDefaults] doubleForKey:LocusPersistSpeedKey]
			: 0.0;
		_fakeCourse = [[NSUserDefaults standardUserDefaults] objectForKey:LocusPersistCourseKey]
			? [[NSUserDefaults standardUserDefaults] doubleForKey:LocusPersistCourseKey]
			: -1.0;
		_swizzledDelegateClasses = [NSMutableSet set];
		_trackedManagers = [NSHashTable weakObjectsHashTable];

		[self detectHostCapabilities];

		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self
				   selector:@selector(handleAppDidEnterBackground:)
					   name:UIApplicationDidEnterBackgroundNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(handleAppWillEnterForeground:)
					   name:UIApplicationWillEnterForegroundNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(handleAppDidBecomeActive:)
					   name:UIApplicationDidBecomeActiveNotification
					 object:nil];

		if (_isSpoofing) {
			[self startSpoofingWithCoordinate:_fakeCoordinate];
		}
	}
	return self;
}

- (void)detectHostCapabilities {
	self.hostSupportsBackgroundLocation = [LocusBackgroundModes() containsObject:@"location"];
	LocusLog(@"host background location support = %@", self.hostSupportsBackgroundLocation ? @"YES" : @"NO");
}

- (CLLocation *)fakeCLLocation {
	return [[CLLocation alloc] initWithCoordinate:self.fakeCoordinate
										 altitude:0
							   horizontalAccuracy:5.0
								 verticalAccuracy:5.0
										   course:self.fakeCourse
											speed:self.fakeSpeed
										timestamp:[NSDate date]];
}

- (NSArray<CLLocation *> *)spoofedLocationsArrayFromIncoming:(NSArray<CLLocation *> *)locations {
	if (!self.isSpoofing) {
		return locations ?: @[];
	}
	return @[[self fakeCLLocation]];
}

- (CLLocation *)spoofedLocationFromIncoming:(CLLocation *)location {
	if (!self.isSpoofing) {
		return location;
	}
	return [self fakeCLLocation];
}

- (void)persistState {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:self.isSpoofing forKey:LocusPersistSpoofingEnabledKey];
	[defaults setDouble:self.fakeCoordinate.latitude forKey:LocusPersistLatitudeKey];
	[defaults setDouble:self.fakeCoordinate.longitude forKey:LocusPersistLongitudeKey];
	[defaults setDouble:self.fakeSpeed forKey:LocusPersistSpeedKey];
	[defaults setDouble:self.fakeCourse forKey:LocusPersistCourseKey];
	[defaults synchronize];
}

- (void)trackManager:(CLLocationManager *)manager {
	if (!manager || manager == self.keeperManager) {
		return;
	}

	if (![self.trackedManagers containsObject:manager]) {
		[self.trackedManagers addObject:manager];
	}
}

- (void)registerDelegateIfNeeded:(id<CLLocationManagerDelegate>)delegate {
	if (!delegate) {
		return;
	}

	Class delegateClass = object_getClass(delegate);
	if (!delegateClass) {
		return;
	}

	NSString *className = NSStringFromClass(delegateClass);
	if ([self.swizzledDelegateClasses containsObject:className]) {
		return;
	}

	SEL didUpdateLocationsSelector = @selector(locationManager:didUpdateLocations:);
	Method didUpdateLocationsMethod = class_getInstanceMethod(delegateClass, didUpdateLocationsSelector);
	if (didUpdateLocationsMethod) {
		IMP originalImp = method_getImplementation(didUpdateLocationsMethod);
		if (originalImp != (IMP)LocusSwizzledDidUpdateLocations) {
			objc_setAssociatedObject(delegateClass,
									kLocusDidUpdateLocationsOriginalIMPKey,
									[NSValue valueWithPointer:originalImp],
									OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			method_setImplementation(didUpdateLocationsMethod, (IMP)LocusSwizzledDidUpdateLocations);
		}
	}

	SEL legacySelector = @selector(locationManager:didUpdateToLocation:fromLocation:);
	Method legacyMethod = class_getInstanceMethod(delegateClass, legacySelector);
	if (legacyMethod) {
		IMP originalImp = method_getImplementation(legacyMethod);
		if (originalImp != (IMP)LocusSwizzledDidUpdateToLocation) {
			objc_setAssociatedObject(delegateClass,
									kLocusDidUpdateToLocationOriginalIMPKey,
									[NSValue valueWithPointer:originalImp],
									OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			method_setImplementation(legacyMethod, (IMP)LocusSwizzledDidUpdateToLocation);
		}
	}

	[self.swizzledDelegateClasses addObject:className];
	LocusLog(@"swizzled delegate class %@", className);
}

- (void)startSpoofingWithCoordinate:(CLLocationCoordinate2D)coordinate {
	self.fakeCoordinate = coordinate;
	if (self.fakeSpeed < 0) {
		self.fakeSpeed = 0;
	}
	if (self.fakeCourse < -1 || self.fakeCourse > 360) {
		self.fakeCourse = -1;
	}

	self.isSpoofing = YES;
	[self persistState];
	[self startHeartbeat];
	[self startBackgroundKeeperIfPossible];
	[self beginShortBackgroundTask];
	[[NSNotificationCenter defaultCenter] postNotificationName:LocusSpoofingDidChangeNotification object:self];
	[self pushFakeLocationToAllManagers];
	[self endShortBackgroundTask];
	LocusLog(@"spoof started at %.5f, %.5f", coordinate.latitude, coordinate.longitude);
}

- (void)stopSpoofing {
	self.isSpoofing = NO;
	[self stopHeartbeat];
	[self stopBackgroundKeeper];
	[self endShortBackgroundTask];
	[self persistState];
	[[NSNotificationCenter defaultCenter] postNotificationName:LocusSpoofingDidChangeNotification object:self];
	LocusLog(@"spoof stopped");
}

- (NSTimeInterval)heartbeatInterval {
	return self.appIsForeground ? 1.0 : 15.0;
}

- (void)startHeartbeat {
	[self refreshHeartbeatForApplicationState];
}

- (void)refreshHeartbeatForApplicationState {
	if (!self.isSpoofing) {
		[self stopHeartbeat];
		return;
	}

	NSTimeInterval interval = [self heartbeatInterval];
	if (self.heartbeatTimer && fabs(self.heartbeatTimer.timeInterval - interval) < DBL_EPSILON) {
		return;
	}

	[self.heartbeatTimer invalidate];
	self.heartbeatTimer = [NSTimer timerWithTimeInterval:interval
												  target:self
												selector:@selector(heartbeatTimerFired)
												userInfo:nil
												 repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.heartbeatTimer forMode:NSRunLoopCommonModes];
	LocusLog(@"heartbeat interval = %.1fs", interval);
}

- (void)stopHeartbeat {
	[self.heartbeatTimer invalidate];
	self.heartbeatTimer = nil;
}

- (void)heartbeatTimerFired {
	if (!self.isSpoofing) {
		return;
	}

	[self beginShortBackgroundTask];
	[self pushFakeLocationToAllManagers];
	[self endShortBackgroundTask];
}

- (void)startBackgroundKeeperIfPossible {
	if (!self.isSpoofing) {
		return;
	}

	if (!self.hostSupportsBackgroundLocation) {
		LocusLog(@"background location unsupported by host app");
		return;
	}

	if (!self.keeperManager) {
		self.keeperManager = [[CLLocationManager alloc] init];
		self.keeperManager.delegate = self;
		self.keeperManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
		self.keeperManager.distanceFilter = kCLDistanceFilterNone;
		self.keeperManager.activityType = CLActivityTypeOther;
		if ([self.keeperManager respondsToSelector:@selector(setPausesLocationUpdatesAutomatically:)]) {
			self.keeperManager.pausesLocationUpdatesAutomatically = NO;
		}
		if (@available(iOS 9.0, *)) {
			self.keeperManager.allowsBackgroundLocationUpdates = YES;
		}
	}

	[self.keeperManager startUpdatingLocation];
	LocusLog(@"background keeper started");
}

- (void)stopBackgroundKeeper {
	if (!self.keeperManager) {
		return;
	}

	[self.keeperManager stopUpdatingLocation];
	LocusLog(@"background keeper stopped");
}

- (void)beginShortBackgroundTask {
	UIApplication *application = UIApplication.sharedApplication;
	if (!application || self.backgroundTaskID != UIBackgroundTaskInvalid) {
		return;
	}

	__weak typeof(self) weakSelf = self;
	self.backgroundTaskID = [application beginBackgroundTaskWithName:@"LocusSpoofPush" expirationHandler:^{
		[weakSelf endShortBackgroundTask];
	}];
}

- (void)endShortBackgroundTask {
	if (self.backgroundTaskID == UIBackgroundTaskInvalid) {
		return;
	}

	UIBackgroundTaskIdentifier taskID = self.backgroundTaskID;
	self.backgroundTaskID = UIBackgroundTaskInvalid;
	[UIApplication.sharedApplication endBackgroundTask:taskID];
}

- (void)pushFakeLocationToAllManagers {
	if (!self.isSpoofing) {
		return;
	}

	NSUInteger pushedCount = 0;
	for (CLLocationManager *manager in self.trackedManagers) {
		if (!manager || manager == self.keeperManager) {
			continue;
		}

		[self pushFakeLocationToManager:manager];
		pushedCount++;
	}

	if (pushedCount > 0) {
		LocusLog(@"pushed fake updates to %lu manager(s)", (unsigned long)pushedCount);
	}
}

- (void)pushFakeLocationToManager:(CLLocationManager *)manager {
	if (!self.isSpoofing || !manager || manager == self.keeperManager) {
		return;
	}

	id<CLLocationManagerDelegate> delegate = manager.delegate;
	if (!delegate || delegate == (id<CLLocationManagerDelegate>)self) {
		return;
	}

	if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
		[delegate locationManager:manager didUpdateLocations:@[[self fakeCLLocation]]];
		return;
	}

	if ([delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
		CLLocation *fake = [self fakeCLLocation];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[(id)delegate locationManager:manager didUpdateToLocation:fake fromLocation:fake];
#pragma clang diagnostic pop
	}
}

- (void)handleAppDidEnterBackground:(NSNotification *)notification {
	(void)notification;
	self.appIsForeground = NO;
	LocusLog(@"app entered background");
	[self beginShortBackgroundTask];
	[self refreshHeartbeatForApplicationState];
}

- (void)handleAppWillEnterForeground:(NSNotification *)notification {
	(void)notification;
	self.appIsForeground = YES;
	LocusLog(@"app will enter foreground");
	[self refreshHeartbeatForApplicationState];
}

- (void)handleAppDidBecomeActive:(NSNotification *)notification {
	(void)notification;
	self.appIsForeground = YES;
	LocusLog(@"app became active");
	[self refreshHeartbeatForApplicationState];
	if (self.isSpoofing) {
		[self pushFakeLocationToAllManagers];
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
	(void)locations;
	if (!self.isSpoofing || manager != self.keeperManager) {
		return;
	}

	[self beginShortBackgroundTask];
	[self pushFakeLocationToAllManagers];
	[self endShortBackgroundTask];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	if (manager != self.keeperManager) {
		return;
	}

	LocusLog(@"background keeper error: %@", error);
}

@end
