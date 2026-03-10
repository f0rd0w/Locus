#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const LocusSpoofingDidChangeNotification;

@interface LocusLocationManager : NSObject <CLLocationManagerDelegate>

@property (nonatomic, assign) BOOL isSpoofing;
@property (nonatomic, assign) CLLocationCoordinate2D fakeCoordinate;
@property (nonatomic, assign) CLLocationSpeed fakeSpeed;
@property (nonatomic, assign) CLLocationDirection fakeCourse;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) CLLocationManager *keeperManager;
@property (nonatomic, assign) BOOL hostSupportsBackgroundLocation;
@property (nonatomic, assign) BOOL appIsForeground;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskID;
@property (nonatomic, strong) NSMutableSet<NSString *> *swizzledDelegateClasses;
@property (nonatomic, strong) NSHashTable<CLLocationManager *> *trackedManagers;

+ (instancetype)shared;

- (void)startSpoofingWithCoordinate:(CLLocationCoordinate2D)coordinate;
- (void)stopSpoofing;
- (CLLocation *)fakeCLLocation;
- (void)trackManager:(CLLocationManager *)manager;
- (void)registerDelegateIfNeeded:(id<CLLocationManagerDelegate>)delegate;
- (NSArray<CLLocation *> *)spoofedLocationsArrayFromIncoming:(NSArray<CLLocation *> *)locations;
- (CLLocation *)spoofedLocationFromIncoming:(CLLocation *)location;
- (void)pushFakeLocationToManager:(CLLocationManager *)manager;
- (void)pushFakeLocationToAllManagers;
- (void)startBackgroundKeeperIfPossible;
- (void)stopBackgroundKeeper;
- (void)startHeartbeat;
- (void)refreshHeartbeatForApplicationState;
- (void)stopHeartbeat;
- (void)beginShortBackgroundTask;
- (void)endShortBackgroundTask;

@end
