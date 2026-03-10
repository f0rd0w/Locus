#import <UIKit/UIKit.h>

@interface LocusFloatingButton : NSObject

+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;

@end