// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLAppDelegate.h"

#import <stdio.h>

#import "VFLHostService.h"
#import "VFLRootSplitViewController.h"
#import "VFLVMDefinition.h"

@implementation VFLAppDelegate

/// 未捕获的 Objective-C 异常先落到 app.log，闪退后至少能看到原因。
static void VFLHandleUncaughtException(NSException *exception) {
	fprintf(stderr, "[VFL] 未捕获异常：%s\n%s\n",
			exception.reason.UTF8String ?: "",
			exception.callStackSymbols.description.UTF8String ?: "");
	fflush(stderr);
}

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	[self redirectLogToFile];
	NSSetUncaughtExceptionHandler(VFLHandleUncaughtException);
	// 先抢 socket：GUI 要拿到 VZVirtualMachine 才能显示画面。
	[[VFLHostService shared] start];

	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [[VFLRootSplitViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

/// App 不在 Xcode 下运行时 NSLog 走 stderr；重定向到 Media/VFL/app.log 方便事后排查。
- (void)redirectLogToFile {
	NSString *directory = VFLDataDirectory();
	[NSFileManager.defaultManager createDirectoryAtPath:directory
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];
	NSString *path = [directory stringByAppendingPathComponent:@"app.log"];
	freopen(path.fileSystemRepresentation, "a", stderr);
	fprintf(stderr, "\n===== VFL 启动 %s =====\n",
			NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String ?: "");
}

@end
