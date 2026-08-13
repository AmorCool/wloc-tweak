#import <UIKit/UIKit.h>

@protocol WLOCMapPickerDelegate <NSObject>
- (void)mapPickerDidPickLatitude:(double)lat longitude:(double)lon;
- (void)mapPickerDidCancel;
@end

@interface WLOCMapPicker : UIViewController
@property (nonatomic, weak) id<WLOCMapPickerDelegate> delegate;
@property (nonatomic, assign) double initialLatitude;
@property (nonatomic, assign) double initialLongitude;
@end
