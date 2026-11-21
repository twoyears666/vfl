// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLAppDelegate.h"

#import "VFLHostService.h"
#import "VFLRootSplitViewController.h"

@implementation VFLAppDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// 先抢 socket：GUI 要拿到 VZVirtualMachine 才能显示画面。
	[[VFLHostService shared] start];

	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [[VFLRootSplitViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
