#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "./FloatingButton/FloatingButton.h"
#import "./LocationManager/LocationManager.h"

static void showFloatingButtonNow(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[LocusFloatingButton sharedInstance] show];
	});
}

static void setupFloatingButtonLifecycleObservers(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserverForName:UIApplicationDidFinishLaunchingNotification
							object:nil
							 queue:[NSOperationQueue mainQueue]
						usingBlock:^(__unused NSNotification *note) {
							showFloatingButtonNow();
						}];
		[center addObserverForName:UIApplicationDidBecomeActiveNotification
							object:nil
							 queue:[NSOperationQueue mainQueue]
						usingBlock:^(__unused NSNotification *note) {
							showFloatingButtonNow();
						}];

		if (@available(iOS 13.0, *)) {
			[center addObserverForName:UISceneDidActivateNotification
								object:nil
								 queue:[NSOperationQueue mainQueue]
							usingBlock:^(__unused NSNotification *note) {
								showFloatingButtonNow();
							}];
			[center addObserverForName:UISceneWillEnterForegroundNotification
								object:nil
								 queue:[NSOperationQueue mainQueue]
							usingBlock:^(__unused NSNotification *note) {
								showFloatingButtonNow();
							}];
		}
	});
}

// =============================================================================
// MARK: - CLLocationManager Hooks
// =============================================================================

%hook CLLocationManager

// Hook the 'location' property getter — apps that read .location directly
// will get the fake CLLocation when spoofing is active
- (CLLocation *)location {
	if ([LocusLocationManager shared].isSpoofing) {
		return [[LocusLocationManager shared] fakeCLLocation];
	}
	return %orig;
}

// Hook setDelegate: to capture every CLLocationManager + its delegate
// so we can push fake locations to them later
- (void)setDelegate:(id<CLLocationManagerDelegate>)delegate {
	%orig;
	if (delegate) {
		[[LocusLocationManager shared] trackManager:self];
		[[LocusLocationManager shared] registerDelegateIfNeeded:delegate];
	}
}

// Hook startUpdatingLocation — when the app starts listening,
// immediately push a fake location if spoofing is active
- (void)startUpdatingLocation {
	%orig;
	[[LocusLocationManager shared] trackManager:self];
	if ([LocusLocationManager shared].isSpoofing) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[LocusLocationManager shared] pushFakeLocationToManager:self];
		});
	}
}

// Hook requestLocation — one-shot location request
// Push a fake location immediately after the real request
- (void)requestLocation {
	%orig;
	[[LocusLocationManager shared] trackManager:self];
	if ([LocusLocationManager shared].isSpoofing) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[LocusLocationManager shared] pushFakeLocationToManager:self];
		});
	}
}

// Hook significant location changes — some apps use this instead
- (void)startMonitoringSignificantLocationChanges {
	%orig;
	[[LocusLocationManager shared] trackManager:self];
	if ([LocusLocationManager shared].isSpoofing) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[LocusLocationManager shared] pushFakeLocationToManager:self];
		});
	}
}

%end

// =============================================================================
// MARK: - CLLocation Hook
// =============================================================================
// Hook the coordinate getter on CLLocation itself.
// This catches cases where the app reads .coordinate on a CLLocation
// object obtained from somewhere other than our fake injection
// (e.g., from a region monitoring callback, visit, etc.)

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
	if ([LocusLocationManager shared].isSpoofing) {
		return [LocusLocationManager shared].fakeCoordinate;
	}
	return %orig;
}

- (CLLocationSpeed)speed {
	if ([LocusLocationManager shared].isSpoofing) {
		return [LocusLocationManager shared].fakeSpeed;
	}
	return %orig;
}

- (CLLocationDirection)course {
	if ([LocusLocationManager shared].isSpoofing) {
		return [LocusLocationManager shared].fakeCourse;
	}
	return %orig;
}

%end

// =============================================================================
// MARK: - CMMotionActivity Hook
// =============================================================================
// Some apps infer driving/movement state from CoreMotion instead of location speed.
// While spoofing, force motion activity to stationary and non-automotive.

%hook CMMotionActivity

- (BOOL)automotive {
	if ([LocusLocationManager shared].isSpoofing) {
		return NO;
	}
	return %orig;
}

- (BOOL)stationary {
	if ([LocusLocationManager shared].isSpoofing) {
		return YES;
	}
	return %orig;
}

- (BOOL)walking {
	if ([LocusLocationManager shared].isSpoofing) {
		return NO;
	}
	return %orig;
}

- (BOOL)running {
	if ([LocusLocationManager shared].isSpoofing) {
		return NO;
	}
	return %orig;
}

- (BOOL)cycling {
	if ([LocusLocationManager shared].isSpoofing) {
		return NO;
	}
	return %orig;
}

%end

// =============================================================================
// MARK: - Constructor — Show Floating Button on App Launch
// =============================================================================

%ctor {
	setupFloatingButtonLifecycleObservers();

	// Show immediately and with delayed retries so we survive varying app startup flows.
	showFloatingButtonNow();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		showFloatingButtonNow();
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		showFloatingButtonNow();
	});
}
