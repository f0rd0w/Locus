#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern NSString *const LocusMapSheetDidDismissNotification;

@interface LocusMapViewController : UIViewController <MKMapViewDelegate>
@end