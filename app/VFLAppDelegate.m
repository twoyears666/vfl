// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLAppDelegate.h"

#import "VFLRootSplitViewController.h"

@implementation VFLAppDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [[VFLRootSplitViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
