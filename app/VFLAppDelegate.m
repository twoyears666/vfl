// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLAppDelegate.h"

#import "VFLRootViewController.h"

@implementation VFLAppDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	VFLRootViewController *root =
		[[VFLRootViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	UINavigationController *navigation =
		[[UINavigationController alloc] initWithRootViewController:root];
	navigation.navigationBar.prefersLargeTitles = YES;
	self.window.rootViewController = navigation;
	[self.window makeKeyAndVisible];
	return YES;
}

@end
