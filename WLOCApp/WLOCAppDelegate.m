#import "WLOCAppDelegate.h"
#import "WLOCViewController.h"

@implementation WLOCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.backgroundColor = [UIColor systemBackgroundColor];

	WLOCViewController *vc = [[WLOCViewController alloc] init];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.navigationBar.prefersLargeTitles = YES;

	self.window.rootViewController = nav;
	[self.window makeKeyAndVisible];
	return YES;
}

@end
